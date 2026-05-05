#!/usr/bin/env bash
THRESHOLD_LID_OPEN_MIN=30
THRESHOLD_LID_CLOSED_MIN=5
BATTERY_STATUS_PATH="/sys/class/power_supply/BAT0/status"
CHARGING_GRACE_MIN=5
LAST_CHARGING_EPOCH=0

CHARGING_GRACE_SEC=$(( CHARGING_GRACE_MIN * 60 ))
THRESHOLD_LID_OPEN_MS=$(( THRESHOLD_LID_OPEN_MIN * 60 * 1000 ))
THRESHOLD_LID_CLOSED_MS=$(( THRESHOLD_LID_CLOSED_MIN * 60 * 1000 ))

get_idle_time_ms() {
    gdbus call \
        --session \
        --dest org.gnome.Mutter.IdleMonitor \
        --object-path /org/gnome/Mutter/IdleMonitor/Core \
        --method org.gnome.Mutter.IdleMonitor.GetIdletime \
    | sed -E 's/.*uint64 ([0-9]+).*/\1/'
}

has_active_ssh_connections() {
    who | grep -qE '\(.*\)'
}

is_battery_charging() {
    [[ -r "$BATTERY_STATUS_PATH" ]] && [[ "$(< "$BATTERY_STATUS_PATH")" == "Charging" ]]
}

is_lid_open() {
    gpioget --chip gpiochip0 GPIO27 | grep -q '=active$'
}

get_threshold() {
    if is_lid_open; then
        echo ${THRESHOLD_LID_OPEN_MS}
    else
        echo ${THRESHOLD_LID_CLOSED_MS}
    fi
}

should_skip_shutdown_due_to_charging() {
    local now
    now=$(date +%s)

    if is_battery_charging; then
        LAST_CHARGING_EPOCH=$now
        return 0
    fi

    (( LAST_CHARGING_EPOCH > 0 && now - LAST_CHARGING_EPOCH <= CHARGING_GRACE_SEC ))
}

while true; do
    IDLE_TIME_MS=$(get_idle_time_ms)
    THRESHOLD_MS=$(get_threshold)

    if (( IDLE_TIME_MS >= THRESHOLD_MS )); then
        if ! has_active_ssh_connections && ! should_skip_shutdown_due_to_charging; then
            sleep 5

            IDLE_TIME_NEW_MS=$(get_idle_time_ms)
            THRESHOLD_MS=$(get_threshold)

            if (( IDLE_TIME_NEW_MS >= THRESHOLD_MS )) && ! has_active_ssh_connections && ! should_skip_shutdown_due_to_charging; then
                systemctl poweroff -i
            fi
        fi
    fi

    sleep 20
done

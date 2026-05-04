#!/usr/bin/env bash
THRESHOLD_MIN=30
THRESHOLD_MS=$(( THRESHOLD_MIN * 60 * 1000 ))
BATTERY_STATUS_PATH="/sys/class/power_supply/BAT0/status"
CHARGING_GRACE_MIN=5
CHARGING_GRACE_SEC=$(( CHARGING_GRACE_MIN * 60 ))
LAST_CHARGING_EPOCH=0

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

    if (( IDLE_TIME_MS >= THRESHOLD_MS )); then
        if ! has_active_ssh_connections && ! should_skip_shutdown_due_to_charging; then
            sleep 5

            IDLE_TIME_NEW_MS=$(get_idle_time_ms)
            if (( IDLE_TIME_NEW_MS >= THRESHOLD_MS )) && ! has_active_ssh_connections && ! should_skip_shutdown_due_to_charging; then
                systemctl poweroff -i
            fi
        fi
    fi

    sleep 20
done

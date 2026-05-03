#!/usr/bin/env bash
THRESHOLD_MIN=30
THRESHOLD_MS=$(( THRESHOLD_MIN * 60 * 1000 ))

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

while true; do
    IDLE_TIME_MS=$(get_idle_time_ms)

    if (( IDLE_TIME_MS >= THRESHOLD_MS )); then
        if ! has_active_ssh_connections; then
            sleep 5

            IDLE_TIME_NEW_MS=$(get_idle_time_ms)
            if (( IDLE_TIME_NEW_MS >= THRESHOLD_MS )) && ! has_active_ssh_connections; then
                systemctl poweroff -i
            fi
        fi
    fi

    sleep 20
done

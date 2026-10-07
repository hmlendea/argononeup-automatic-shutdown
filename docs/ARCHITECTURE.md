# Architecture Documentation

## Repository Purpose

This repository provides an automatic shutdown mechanism for the **Argon ONE UP CM5** laptop. The device lacks sleep/suspend support, so this utility powers off the machine when it has been idle long enough, there are no active SSH sessions, and the battery is not charging.

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        User Session                              │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │              systemd --user Service Manager                │  │
│  │  ┌─────────────────────────────────────────────────────┐  │  │
│  │  │  argononeup-automatic-shutdown.service              │  │  │
│  │  │  ┌───────────────────────────────────────────────┐  │  │  │
│  │  │  │  argononeup-automatic-shutdown.sh (daemon)    │  │  │  │
│  │  │  │  ┌─────────────────────────────────────────┐  │  │  │  │
│  │  │  │  │           Main Loop (20s interval)      │  │  │  │  │
│  │  │  │  │  1. Get idle time (D-Bus → Mutter)      │  │  │  │  │
│  │  │  │  │  2. Get lid state (gpioget GPIO27)      │  │  │  │  │
│  │  │  │  │  3. Select threshold (30m open / 5m closed)│  │  │  │
│  │  │  │  │  4. Check SSH sessions (who)            │  │  │  │  │
│  │  │  │  │  5. Check battery status (/sys/class/...)│  │  │  │  │
│  │  │  │  │  6. Apply charging grace period (5 min) │  │  │  │  │
│  │  │  │  │  7. If all conditions met → poweroff    │  │  │  │  │
│  │  │  │  └─────────────────────────────────────────┘  │  │  │  │
│  │  │  └───────────────────────────────────────────────┘  │  │  │
│  │  └─────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## Component Breakdown

### 1. Installation Scripts

| File | Purpose |
|------|---------|
| `install` | Copies script and service to user directories, enables systemd service |
| `uninstall` | Stops/disables service, removes installed files, reloads systemd |

**Installation paths:**
- Script: `~/.local/bin/argononeup-automatic-shutdown` (mode 755)
- Service: `~/.config/systemd/user/argononeup-automatic-shutdown.service` (mode 644)

### 2. Systemd Service (`argononeup-automatic-shutdown.service`)

```ini
[Unit]
Description=Auto poweroff after 30 min idle and no SSH
After=graphical-session.target
PartOf=graphical-session.target

[Service]
ExecStart=%h/.local/bin/argononeup-automatic-shutdown
Restart=always
RestartSec=10
StartLimitIntervalSec=0
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=graphical-session.target
```

**Key properties:**
- **User-level service** — tied to graphical session lifecycle
- **Auto-restart** — `Restart=always` with 10s delay on crash
- **No start limit** — `StartLimitIntervalSec=0` prevents restart throttling
- **Journal logging** — stdout/stderr captured to systemd journal

### 3. Main Daemon Script (`argononeup-automatic-shutdown.sh`)

#### Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `THRESHOLD_LID_OPEN_MIN` | 30 | Idle threshold when lid is open (minutes) |
| `THRESHOLD_LID_CLOSED_MIN` | 5 | Idle threshold when lid is closed (minutes) |
| `BATTERY_STATUS_PATH` | `/sys/class/power_supply/BAT0/status` | Battery status sysfs path |
| `CHARGING_GRACE_MIN` | 5 | Grace period after charging stops (minutes) |

#### Functions

| Function | Purpose | External Dependencies |
|----------|---------|----------------------|
| `get_idle_time_ms()` | Queries GNOME Mutter idle monitor via D-Bus | `gdbus`, `sed` |
| `has_active_ssh_connections()` | Checks `who` output for remote sessions | `who`, `grep` |
| `is_battery_charging()` | Reads battery status from sysfs | `/sys/class/power_supply/BAT0/status` |
| `is_lid_open()` | Reads GPIO27 state via gpioget | `gpioget` (gpiochip0) |
| `get_threshold()` | Returns threshold in ms based on lid state | `is_lid_open()` |
| `should_skip_shutdown_due_to_charging()` | Implements charging grace period logic | `is_battery_charging()`, `date` |

#### Main Loop Logic

```
while true:
    IDLE_TIME_MS = get_idle_time_ms()
    THRESHOLD_MS = get_threshold()

    if IDLE_TIME_MS >= THRESHOLD_MS:
        if not has_active_ssh_connections() and not should_skip_shutdown_due_to_charging():
            sleep 5  # confirmation delay

            IDLE_TIME_NEW_MS = get_idle_time_ms()
            THRESHOLD_MS = get_threshold()  # re-check (lid may have changed)

            if IDLE_TIME_NEW_MS >= THRESHOLD_MS and not has_active_ssh_connections() and not should_skip_shutdown_due_to_charging():
                systemctl poweroff -i

    sleep 20
```

**Key behaviors:**
- **Double-check pattern** — 5s confirmation delay prevents false positives
- **Re-evaluation** — threshold and conditions re-checked after delay
- **Lid-aware thresholds** — 30 min (open) vs 5 min (closed)
- **SSH protection** — never shuts down with active remote sessions
- **Charging grace** — 5 min grace after charger unplugged

### 4. External Dependencies

| Dependency | Purpose | Provided By |
|------------|---------|-------------|
| `systemd` (user) | Service management | Base system |
| `gdbus` | D-Bus communication with Mutter | `glib2` / `dbus` |
| `gpioget` | GPIO pin reading | `libgpiod-tools` |
| `who` | SSH session detection | `util-linux` |
| `sed`, `grep` | Text processing | GNU coreutils |
| `bash` | Script interpreter | Base system |
| GNOME/Mutter | Idle monitor D-Bus service | Desktop environment |

## Data Flow

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Mutter    │────▶│  get_idle_  │────▶│  IDLE_TIME  │
│  (D-Bus)    │     │  time_ms()  │     │    (ms)     │
└─────────────┘     └─────────────┘     └──────┬──────┘
                                               │
┌─────────────┐     ┌─────────────┐            │
│  GPIO27     │────▶│ is_lid_open │────────────┤
│  (gpioget)  │     │   ()        │            ▼
└─────────────┘     └─────────────┘     ┌─────────────┐
                                        │ get_threshold│
┌─────────────┐     ┌─────────────┐     │    ()       │
│   who       │────▶│ has_active_ │────▶└──────┬──────┘
│  (SSH)      │     │ _ssh_conn() │            │
└─────────────┘     └─────────────┘            ▼
                                        ┌─────────────┐
┌─────────────┐     ┌─────────────┐     │  THRESHOLD  │
│  BAT0/      │────▶│ is_battery_ │────▶│    (ms)     │
│  status     │     │ _charging() │     └──────┬──────┘
└─────────────┘     └─────────────┘            │
                                               ▼
                                        ┌─────────────┐
                                        │  Decision   │
                                        │  Logic      │
                                        └──────┬──────┘
                                               │
                                               ▼
                                        ┌─────────────┐
                                        │ systemctl   │
                                        │ poweroff -i │
                                        └─────────────┘
```

## State Management

### Persistent State (in-memory only)

| Variable | Scope | Purpose |
|----------|-------|---------|
| `LAST_CHARGING_EPOCH` | Global (script) | Tracks last time battery was charging for grace period |

### No Persistent Storage

- No configuration files
- No state files
- No database
- All state is ephemeral (lost on service restart)

## Failure Modes & Handling

| Failure | Behavior |
|---------|----------|
| D-Bus unavailable | `get_idle_time_ms` returns empty/non-numeric → comparison fails → no shutdown |
| `gpioget` fails | `is_lid_open` returns false (lid closed) → uses 5 min threshold |
| Battery status unreadable | `is_battery_charging` returns false → no charging skip |
| `who` fails | `has_active_ssh_connections` returns false → allows shutdown |
| `systemctl poweroff` fails | Service logs error, continues loop |
| Script crashes | systemd restarts after 10s (`Restart=always`) |

## Security Considerations

- **No elevated privileges** — runs as user, uses `systemctl --user poweroff -i` (inhibitors respected)
- **No network exposure** — purely local monitoring
- **No sensitive data** — only reads system status
- **User-scoped** — cannot affect other users' sessions

## Testing Strategy

Currently no automated tests exist. Manual verification:

```bash
# Check service status
systemctl --user status argononeup-automatic-shutdown.service

# View live logs
journalctl --user -u argononeup-automatic-shutdown.service -f

# Test idle detection
gdbus call --session --dest org.gnome.Mutter.IdleMonitor \
  --object-path /org/gnome/Mutter/IdleMonitor/Core \
  --method org.gnome.Mutter.IdleMonitor.GetIdletime

# Test lid detection
gpioget --chip gpiochip0 GPIO27

# Test battery status
cat /sys/class/power_supply/BAT0/status

# Test SSH detection
who
```

## Modification Impact Analysis

| Change | Affected Components | Risk |
|--------|---------------------|------|
| Threshold values | `argononeup-automatic-shutdown.sh` constants | Low |
| Lid GPIO pin | `is_lid_open()` function | Medium (hardware-specific) |
| Battery path | `BATTERY_STATUS_PATH` constant | Low |
| Check interval | `sleep 20` in main loop | Low |
| Confirmation delay | `sleep 5` in double-check | Low |
| Service restart policy | `.service` file `Restart*` | Medium |
| Install paths | `install`/`uninstall` scripts | Medium |

## Invariants

1. **Service runs only in graphical session** — `PartOf=graphical-session.target`
2. **Never shuts down with active SSH** — `who` check is mandatory
3. **Charging always prevents shutdown** — immediate skip + 5 min grace
4. **Lid state dynamically affects threshold** — re-checked each iteration
5. **Double-confirmation before poweroff** — 5s delay with re-validation
6. **User-level only** — no system-wide effects, no sudo required
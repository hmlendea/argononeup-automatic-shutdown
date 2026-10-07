# Capabilities Documentation

## Overview

This document describes the functional capabilities of the argononeup-automatic-shutdown system, organized by user-facing features and internal behaviors.

## Primary Capability: Automatic Power Management

### Idle-Based Shutdown

**Description:** Automatically powers off the machine after a configurable period of user inactivity.

**Behavior:**
- Monitors GNOME Mutter idle time via D-Bus (`org.gnome.Mutter.IdleMonitor.GetIdletime`)
- Idle time measured in milliseconds since last user input (keyboard, mouse, touch)
- Threshold varies dynamically based on laptop lid state

**Thresholds:**
| Lid State | Idle Threshold | Rationale |
|-----------|----------------|-----------|
| Open | 30 minutes | User likely nearby, longer grace period |
| Closed | 5 minutes | User likely away, aggressive power saving |

**Implementation:** `get_threshold()` function in `argononeup-automatic-shutdown.sh`

### SSH Session Protection

**Description:** Prevents shutdown when remote SSH sessions are active.

**Behavior:**
- Executes `who` command to list logged-in users
- Detects remote sessions by checking for parentheses in output (e.g., `user pts/0 2024-01-15 10:30 (192.168.1.50)`)
- If any remote session exists, shutdown is skipped for current iteration

**Implementation:** `has_active_ssh_connections()` function

**Limitations:**
- Only detects SSH sessions with allocated PTYs
- Does not detect SSH tunnels, port forwards, or connection-sharing sessions without PTY
- Does not detect other remote access methods (VNC, RDP, etc.)

### Battery Charging Awareness

**Description:** Prevents shutdown while battery is charging, with grace period after unplugging.

**Behavior:**
- Reads `/sys/class/power_supply/BAT0/status`
- If status is `Charging`: immediately skips shutdown, records timestamp
- If status is not `Charging`: checks if last charging was within 5 minutes (grace period)
- Grace period prevents immediate shutdown after unplugging (allows brief unplug/replug)

**Implementation:** `is_battery_charging()` and `should_skip_shutdown_due_to_charging()` functions

**Parameters:**
| Parameter | Value | Description |
|-----------|-------|-------------|
| Battery status path | `/sys/class/power_supply/BAT0/status` | Sysfs path for battery status |
| Charging grace period | 5 minutes | Time after unplugging before shutdown allowed |

### Lid State Detection

**Description:** Reads physical lid switch state via GPIO to adjust idle threshold.

**Behavior:**
- Uses `gpioget --chip gpiochip0 GPIO27` to read GPIO pin 27
- Pin state `inactive` = lid open, `active` = lid closed (hardware-specific)
- Threshold re-evaluated on every loop iteration (20s) and during confirmation delay

**Implementation:** `is_lid_open()` function

**Hardware Dependency:** Specific to Argon ONE UP CM5 GPIO mapping (GPIO27 on gpiochip0)

### Double-Confirmation Shutdown

**Description:** Two-phase verification before executing poweroff to prevent false positives.

**Behavior:**
1. First check: idle time exceeds threshold, no SSH, not charging/grace
2. Wait 5 seconds
3. Second check: re-verify all conditions (idle time, threshold, SSH, charging)
4. Only if both checks pass: execute `systemctl poweroff -i`

**Rationale:**
- Handles transient idle spikes
- Accounts for lid state changes during delay
- Respects inhibitors (`-i` flag honors systemd inhibitors)

**Implementation:** Main loop in `argononeup-automatic-shutdown.sh`

## Service Management Capabilities

### User-Level Systemd Integration

**Description:** Runs as a user systemd service tied to graphical session lifecycle.

**Features:**
- **Auto-start on login** — `WantedBy=graphical-session.target`
- **Auto-stop on logout** — `PartOf=graphical-session.target`
- **Crash recovery** — `Restart=always` with 10s delay
- **No restart throttling** — `StartLimitIntervalSec=0`
- **Journal logging** — stdout/stderr captured to systemd journal

**Service File:** `argononeup-automatic-shutdown.service`

### Installation Management

**Description:** Self-contained install/uninstall scripts for user-level deployment.

**Install (`install` script):**
- Validates source files exist
- Creates destination directories (`~/.local/bin`, `~/.config/systemd/user`)
- Installs script (mode 755) and service (mode 644)
- Runs `systemctl --user daemon-reload`
- Enables and starts service (`systemctl --user enable --now`)

**Uninstall (`uninstall` script):**
- Stops and disables service (`systemctl --user disable --now`)
- Removes service file and script
- Runs `systemctl --user daemon-reload`
- Graceful handling if service not installed

**Requirements:** No sudo required; operates entirely in user space

## Observability Capabilities

### Status Inspection

```bash
systemctl --user status argononeup-automatic-shutdown.service
```

Shows: active state, PID, memory usage, recent log lines

### Live Log Streaming

```bash
journalctl --user -u argononeup-automatic-shutdown.service -f
```

Real-time log output from daemon

### Historical Logs

```bash
journalctl --user -u argononeup-automatic-shutdown.service -n 50
```

Last 50 log entries

### Manual Component Testing

Each detection component can be tested independently:

| Component | Test Command |
|-----------|--------------|
| Idle monitor | `gdbus call --session --dest org.gnome.Mutter.IdleMonitor --object-path /org/gnome/Mutter/IdleMonitor/Core --method org.gnome.Mutter.IdleMonitor.GetIdletime` |
| Lid state | `gpioget --chip gpiochip0 GPIO27` |
| Battery status | `cat /sys/class/power_supply/BAT0/status` |
| SSH sessions | `who` |

## Configuration Capabilities

### Current: Hardcoded Constants

All thresholds and paths are compile-time constants in the script:

```bash
THRESHOLD_LID_OPEN_MIN=30
THRESHOLD_LID_CLOSED_MIN=5
BATTERY_STATUS_PATH="/sys/class/power_supply/BAT0/status"
CHARGING_GRACE_MIN=5
```

### Extensibility Points

| Capability | Current State | Extension Effort |
|------------|---------------|------------------|
| Configurable thresholds | Hardcoded | Low (add config file parsing) |
| Custom battery path | Hardcoded | Low (env var or config) |
| Custom GPIO chip/pin | Hardcoded | Low (env var or config) |
| Custom check interval | Hardcoded (20s) | Low (constant change) |
| Custom confirmation delay | Hardcoded (5s) | Low (constant change) |
| Additional inhibit conditions | None | Medium (new functions) |
| Multiple battery support | Single (BAT0) | Medium (iteration logic) |
| Non-GNOME idle detection | GNOME only | High (abstraction layer) |

## Integration Capabilities

### Systemd Inhibitors

The `systemctl poweroff -i` command respects systemd inhibitors. If another application has registered a shutdown inhibitor (e.g., unsaved work, active backup), the poweroff will be blocked.

### Graphical Session Binding

Service starts/stops with `graphical-session.target`, ensuring:
- Only runs when user has active graphical session
- Stops cleanly on logout
- No orphaned processes after session ends

### User Namespace Isolation

- Runs entirely in user context
- Cannot affect other users
- No system-wide configuration changes
- Compatible with multi-user systems

## Limitations & Non-Capabilities

| Non-Capability | Reason |
|----------------|--------|
| Sleep/suspend support | Hardware limitation (Argon ONE UP CM5) |
| Hibernate support | Not implemented |
| Per-application idle tracking | Only system-wide Mutter idle monitor |
| Network activity detection | Only SSH PTY detection |
| Custom idle definitions | Fixed to Mutter's definition |
| Multi-monitor awareness | Not applicable to idle detection |
| Scheduled shutdown windows | Time-based scheduling not implemented |
| Notification before shutdown | No desktop notification integration |
| AC power detection | Only battery charging state monitored |
| Thermal throttling awareness | Not monitored |
| Custom action on threshold | Only poweroff supported |

## Capability Matrix

| Capability | Implemented | Configurable | Tested | Documented |
|------------|-------------|--------------|--------|------------|
| Idle detection (GNOME) | ✅ | ❌ | Manual | ✅ |
| Lid-aware thresholds | ✅ | ❌ | Manual | ✅ |
| SSH session protection | ✅ | ❌ | Manual | ✅ |
| Charging skip + grace | ✅ | ❌ | Manual | ✅ |
| Double-confirmation | ✅ | ❌ | Manual | ✅ |
| User systemd service | ✅ | ❌ | Manual | ✅ |
| Auto-restart on crash | ✅ | ❌ | Manual | ✅ |
| Install/uninstall scripts | ✅ | ❌ | Manual | ✅ |
| Journal logging | ✅ | ❌ | Manual | ✅ |
| Inhibitor respect | ✅ | ❌ | Manual | ✅ |
| Config file support | ❌ | N/A | N/A | N/A |
| Non-GNOME DE support | ❌ | N/A | N/A | N/A |
| Automated tests | ❌ | N/A | N/A | N/A |
| Desktop notifications | ❌ | N/A | N/A | N/A |
| Multi-battery support | ❌ | N/A | N/A | N/A |
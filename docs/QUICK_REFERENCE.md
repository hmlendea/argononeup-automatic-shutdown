# Quick Reference

## Repository Structure

```
argononeup-automatic-shutdown/
├── argononeup-automatic-shutdown.sh   # Main daemon script
├── argononeup-automatic-shutdown.service  # systemd user service
├── install                            # Installation script
├── uninstall                          # Uninstallation script
├── LICENSE                            # GPL v3
├── README.md                          # User documentation
├── .github/FUNDING.yml                # Funding links
└── docs/
    ├── ARCHITECTURE.md                # System architecture
    ├── CAPABILITIES.md                # Functional capabilities
    ├── EXECUTION.md                   # Execution flow traces
    ├── DEPENDENCIES.md                # External dependencies
    ├── TESTING.md                     # Testing procedures
    └── OPERATIONS.md                  # Operational procedures
```

## Key Files & Locations

| File | Installed Location | Purpose |
|------|-------------------|---------|
| `argononeup-automatic-shutdown.sh` | `~/.local/bin/argononeup-automatic-shutdown` | Main daemon |
| `argononeup-automatic-shutdown.service` | `~/.config/systemd/user/argononeup-automatic-shutdown.service` | systemd service |

## Core Constants (in script)

```bash
THRESHOLD_LID_OPEN_MIN=30        # 30 minutes (lid open)
THRESHOLD_LID_CLOSED_MIN=5       # 5 minutes (lid closed)
BATTERY_STATUS_PATH="/sys/class/power_supply/BAT0/status"
CHARGING_GRACE_MIN=5             # 5 minutes grace after unplugging
CHECK_INTERVAL_SEC=20            # Main loop sleep
CONFIRMATION_DELAY_SEC=5         # Double-check delay
```

## Service Commands

```bash
# Status
systemctl --user status argononeup-automatic-shutdown.service

# Start/Stop/Restart
systemctl --user start|stop|restart argononeup-automatic-shutdown.service

# Enable/Disable (auto-start on login)
systemctl --user enable|disable argononeup-automatic-shutdown.service

# Logs
journalctl --user -u argononeup-automatic-shutdown.service -f    # Follow
journalctl --user -u argononeup-automatic-shutdown.service -n 50 # Last 50
```

## Component Test Commands

```bash
# Idle time (ms)
gdbus call --session --dest org.gnome.Mutter.IdleMonitor \
    --object-path /org/gnome/Mutter/IdleMonitor/Core \
    --method org.gnome.Mutter.IdleMonitor.GetIdletime

# Lid state
gpioget --chip gpiochip0 GPIO27

# Battery status
cat /sys/class/power_supply/BAT0/status

# SSH sessions
who
```

## Decision Logic Summary

```
SHUTDOWN IF ALL TRUE:
  ✓ Idle time ≥ threshold (30m open / 5m closed)
  ✓ No active SSH sessions (who shows no (IP))
  ✓ Battery not charging
  ✓ Not in 5-min grace period after charging
  ✓ Confirmed after 5s delay (re-check all above)
  ✓ systemctl poweroff -i succeeds (respects inhibitors)
```

## Failure Behaviors

| Failure | Behavior |
|---------|----------|
| D-Bus/Mutter unavailable | Idle = 0 → no shutdown (safe) |
| GPIO read fails | Assumes lid closed → 5 min threshold |
| Battery sysfs unreadable | Assumes not charging → allows shutdown |
| `who` fails | Assumes no SSH → allows shutdown |
| Script crashes | systemd restarts in 10s |
| `poweroff` blocked by inhibitor | Shutdown aborted, loop continues |

## Install/Uninstall

```bash
# Install
chmod +x install uninstall argononeup-automatic-shutdown.sh
./install

# Uninstall
./uninstall
```

## Hardware Specifics (Argon ONE UP CM5)

| Component | Interface | Value |
|-----------|-----------|-------|
| Lid switch | GPIO | gpiochip0, GPIO27 (active-low) |
| Battery | Sysfs | /sys/class/power_supply/BAT0/status |
| Idle monitor | D-Bus | org.gnome.Mutter.IdleMonitor |

## Requirements

- Linux + systemd (user services)
- GNOME Shell ≥ 3.36
- `bash`, `gdbus`, `gpioget`, `who`, `sed`, `grep`, `date`, `sleep`
- User in `gpio` group (for lid detection)
- Graphical session (service tied to `graphical-session.target`)

## No Configuration File

All settings are hardcoded constants in the script. To customize, edit `~/.local/bin/argononeup-automatic-shutdown` and restart service.

## License

GPL v3 — see LICENSE file.
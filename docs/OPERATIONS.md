# Operations Documentation

## Overview

This document covers operational procedures for deploying, monitoring, maintaining, and troubleshooting the argononeup-automatic-shutdown system in production environments.

## Deployment

### Prerequisites

**Target System Requirements:**
- Linux with systemd (user service support)
- GNOME Shell ≥ 3.36 (for Mutter IdleMonitor)
- Argon ONE UP CM5 hardware (GPIO27 on gpiochip0, BAT0 battery)
- User in `gpio` group (for lid detection)
- Graphical login (service tied to `graphical-session.target`)

**Verify Prerequisites:**
```bash
# Check systemd user support
systemctl --user status >/dev/null && echo "✅ systemd user" || echo "❌ systemd user"

# Check GNOME version
gnome-shell --version | grep -E '^GNOME Shell 3\.(3[6-9]|[4-9][0-9])|4[0-9]' && echo "✅ GNOME" || echo "❌ GNOME version"

# Check GPIO access
groups | grep -q gpio && echo "✅ gpio group" || echo "⚠️  Add user to gpio group: sudo usermod -aG gpio $USER"

# Check battery
[[ -r /sys/class/power_supply/BAT0/status ]] && echo "✅ BAT0" || echo "❌ BAT0 missing"

# Check required commands
for cmd in bash systemctl gdbus gpioget who sed grep date sleep; do
    command -v "$cmd" >/dev/null && echo "✅ $cmd" || echo "❌ $cmd"
done
```

### Installation Procedure

```bash
# 1. Clone or download repository
git clone https://github.com/hmlendea/argononeup-automatic-shutdown.git
cd argononeup-automatic-shutdown

# 2. Make scripts executable
chmod +x install uninstall argononeup-automatic-shutdown.sh

# 3. Run installer
./install

# 4. Verify installation
systemctl --user status argononeup-automatic-shutdown.service
```

**Installer Actions:**
1. Validates source files exist
2. Creates `~/.local/bin/` and `~/.config/systemd/user/`
3. Installs script (755) and service (644)
4. Runs `systemctl --user daemon-reload`
5. Enables and starts service (`systemctl --user enable --now`)

**No sudo required** — entirely user-scoped.

### Post-Installation Verification

```bash
# Check service status
systemctl --user status argononeup-automatic-shutdown.service

# Expected output:
# ● argononeup-automatic-shutdown.service - Auto poweroff after 30 min idle and no SSH
#      Loaded: loaded (/home/user/.config/systemd/user/argononeup-automatic-shutdown.service; enabled; preset: enabled)
#      Active: active (running) since ...
#    Main PID: 12345 (argononeup-auto)
#       Tasks: 1 (limit: ...)
#      Memory: 2.5M
#         CPU: 10ms
#      CGroup: /user.slice/user-1000.slice/user@1000.service/.../argononeup-automatic-shutdown.service
#              └─12345 /bin/bash /home/user/.local/bin/argononeup-automatic-shutdown

# Check logs
journalctl --user -u argononeup-automatic-shutdown.service -n 20
```

## Monitoring

### Health Checks

#### 1. Service Status Check

```bash
# Quick status
systemctl --user is-active argononeup-automatic-shutdown.service
# Returns: active / inactive / failed

# Detailed status
systemctl --user status argononeup-automatic-shutdown.service
```

**Healthy indicators:**
- `Active: active (running)`
- `Main PID` present
- Memory stable (~2-4 MB)
- No restart loops

#### 2. Log Monitoring

```bash
# Follow live logs
journalctl --user -u argononeup-automatic-shutdown.service -f

# Recent errors
journalctl --user -u argononeup-automatic-shutdown.service -p err -n 50

# Since last boot
journalctl --user -u argononeup-automatic-shutdown.service -b
```

**Expected log pattern:** Minimal output (daemon is silent during normal operation). Logs appear only on:
- Service start/stop
- Restart events
- Script errors (if any)

#### 3. Component Health Checks

```bash
# Idle monitor
gdbus call --session --dest org.gnome.Mutter.IdleMonitor \
    --object-path /org/gnome/Mutter/IdleMonitor/Core \
    --method org.gnome.Mutter.IdleMonitor.GetIdletime

# Lid state
gpioget --chip gpiochip0 GPIO27

# Battery
cat /sys/class/power_supply/BAT0/status

# SSH sessions
who
```

**Automated health check script:**
```bash
#!/bin/bash
# health-check.sh
set -euo pipefail

check() {
    local name="$1"
    local cmd="$2"
    if eval "$cmd" >/dev/null 2>&1; then
        echo "✅ $name"
        return 0
    else
        echo "❌ $name"
        return 1
    fi
}

check "Service active" "systemctl --user is-active --quiet argononeup-automatic-shutdown.service"
check "Idle monitor" "gdbus call --session --dest org.gnome.Mutter.IdleMonitor --object-path /org/gnome/Mutter/IdleMonitor/Core --method org.gnome.Mutter.IdleMonitor.GetIdletime"
check "GPIO access" "gpioget --chip gpiochip0 GPIO27"
check "Battery sysfs" "[[ -r /sys/class/power_supply/BAT0/status ]]"
check "who command" "who"
```

### Alerting Rules (for monitoring systems)

| Metric | Warning | Critical | Action |
|--------|---------|----------|--------|
| Service inactive | > 1 min | > 5 min | Check logs, restart service |
| Service restarting | > 3/hour | > 10/hour | Investigate crashes |
| Idle monitor failing | Any failure | Persistent | Check GNOME/Mutter |
| GPIO access failing | Any failure | Persistent | Check permissions/hardware |
| Battery sysfs unreadable | Any failure | Persistent | Check kernel/power supply |

## Maintenance

### Routine Maintenance

**No routine maintenance required.** The system is designed to be self-sustaining.

**Optional periodic checks:**
- Monthly: Verify service status and logs
- After kernel updates: Verify GPIO access still works
- After GNOME updates: Verify idle monitor still works

### Configuration Changes

**Current:** All configuration is hardcoded in script constants.

**To modify thresholds:**
```bash
# Edit the installed script
nano ~/.local/bin/argononeup-automatic-shutdown

# Change constants at top:
THRESHOLD_LID_OPEN_MIN=30
THRESHOLD_LID_CLOSED_MIN=5
CHARGING_GRACE_MIN=5

# Restart service
systemctl --user restart argononeup-automatic-shutdown.service
```

**To modify check interval:**
```bash
# Edit sleep 20 in main loop to desired interval
# Restart service
```

**To modify confirmation delay:**
```bash
# Edit sleep 5 in double-check to desired delay
# Restart service
```

### Log Rotation

Handled by systemd journal. No manual rotation needed.

**Journal limits (default):**
- Per-user journal: 10% of disk, max 4GB
- Max file size: 1/8 of limit

**Adjust if needed:**
```bash
# Edit user journal config
mkdir -p ~/.config/systemd/journald.conf.d
cat > ~/.config/systemd/journald.conf.d/argononeup.conf <<'EOF'
[Journal]
SystemMaxUse=500M
SystemMaxFileSize=50M
EOF

# Reload
systemctl --user restart systemd-journald
```

## Troubleshooting

### Common Issues

#### Issue 1: Service Not Starting

**Symptoms:** `systemctl --user status` shows `inactive (dead)` or `failed`

**Diagnosis:**
```bash
# Check logs
journalctl --user -u argononeup-automatic-shutdown.service -n 50

# Check if script exists and executable
ls -la ~/.local/bin/argononeup-automatic-shutdown

# Test script manually
~/.local/bin/argononeup-automatic-shutdown
```

**Common causes:**
| Cause | Fix |
|-------|-----|
| Script not executable | `chmod +x ~/.local/bin/argononeup-automatic-shutdown` |
| Missing dependency | Install `libgpiod-tools`, `glib2` |
| GNOME not running | Service requires graphical session |
| D-Bus session missing | Log in graphically, not via SSH only |

#### Issue 2: Shutdown Not Triggering

**Symptoms:** Machine stays on past idle threshold

**Diagnosis:**
```bash
# Check current idle time
gdbus call --session --dest org.gnome.Mutter.IdleMonitor \
    --object-path /org/gnome/Mutter/IdleMonitor/Core \
    --method org.gnome.Mutter.IdleMonitor.GetIdletime

# Check lid state
gpioget --chip gpiochip0 GPIO27

# Check threshold being used
# (Add debug to script temporarily)

# Check SSH sessions
who

# Check battery
cat /sys/class/power_supply/BAT0/status

# Check charging grace
# (Check LAST_CHARGING_EPOCH in script - add debug)
```

**Common causes:**
| Cause | Fix |
|-------|-----|
| Active SSH session | Close SSH connections |
| Battery charging | Unplug charger, wait 5 min grace |
| Lid closed but GPIO says open | Check GPIO wiring/hardware |
| Non-GNOME desktop | Idle monitor unavailable |
| Inhibitor active | Check `systemd-inhibit --list` |

#### Issue 3: False Positive Shutdowns

**Symptoms:** Machine shuts down unexpectedly

**Diagnosis:**
```bash
# Check logs around shutdown time
journalctl --user -u argononeup-automatic-shutdown.service --since="1 hour ago"

# Check for inhibitors
systemd-inhibit --list --what=shutdown

# Verify thresholds
# Lid open: 30 min, Lid closed: 5 min
```

**Common causes:**
| Cause | Fix |
|-------|-----|
| Lid GPIO misreporting | Check `gpioget` output, verify hardware |
| Idle monitor resetting | Check for background activity (updates, etc.) |
| Grace period not working | Check `LAST_CHARGING_EPOCH` logic |
| SSH detection missing session | Check `who` output format |

#### Issue 4: Service Restarting Frequently

**Symptoms:** `systemctl --user status` shows frequent restarts

**Diagnosis:**
```bash
# Check restart count
systemctl --user show argononeup-automatic-shutdown.service --property=NRestarts

# Check logs for errors
journalctl --user -u argononeup-automatic-shutdown.service -p err

# Test script manually for crashes
~/.local/bin/argononeup-automatic-shutdown
```

**Common causes:**
| Cause | Fix |
|-------|-----|
| Script syntax error | Fix script, reinstall |
| Missing command (`gpioget`, etc.) | Install missing package |
| Permission denied (GPIO) | Add user to `gpio` group, relogin |
| D-Bus permission | Check session bus access |

#### Issue 5: GPIO Permission Denied

**Symptoms:** `gpioget` fails with permission error

**Fix:**
```bash
# Add user to gpio group
sudo usermod -aG gpio $USER

# Relogin required (or new session)
# Verify
groups | grep gpio
gpioget --chip gpiochip0 GPIO27
```

**Alternative (udev rule):**
```bash
# /etc/udev/rules.d/99-gpio.rules
SUBSYSTEM=="gpio", KERNEL=="gpiochip*", GROUP="gpio", MODE="0660"

# Reload
sudo udevadm control --reload-rules
sudo udevadm trigger
```

### Debug Mode

**Enable verbose logging temporarily:**

```bash
# Edit script to add debug
nano ~/.local/bin/argononeup-automatic-shutdown

# Add after shebang:
set -x
exec 2>>/tmp/argononeup-debug.log

# Restart
systemctl --user restart argononeup-automatic-shutdown.service

# Watch debug log
tail -f /tmp/argononeup-debug.log
```

**Disable after debugging:**
```bash
# Remove set -x and exec line
# Restart service
```

### Emergency Procedures

#### Prevent Shutdown Temporarily

```bash
# Option 1: Stop service
systemctl --user stop argononeup-automatic-shutdown.service

# Option 2: Add inhibitor
systemd-inhibit --what=shutdown --why="maintenance" sleep 3600

# Option 3: Keep SSH session open
# (SSH session prevents shutdown)
```

#### Force Shutdown If Stuck

```bash
# If script hangs and system won't shut down
systemctl poweroff -i
# Or force
systemctl poweroff --force
```

#### Complete Removal

```bash
# From repository directory
./uninstall

# Or manually:
systemctl --user disable --now argononeup-automatic-shutdown.service
rm -f ~/.config/systemd/user/argononeup-automatic-shutdown.service
rm -f ~/.local/bin/argononeup-automatic-shutdown
systemctl --user daemon-reload
```

## Backup & Recovery

### Backup Configuration

**No persistent configuration to backup.** All settings in script constants.

**To backup customizations:**
```bash
# Backup modified script
cp ~/.local/bin/argononeup-automatic-shutdown ~/argononeup-automatic-shutdown.backup
```

### Recovery

```bash
# Restore from backup
cp ~/argononeup-automatic-shutdown.backup ~/.local/bin/argononeup-automatic-shutdown
systemctl --user restart argononeup-automatic-shutdown.service
```

**Full reinstall:**
```bash
./uninstall
./install
```

## Upgrading

### From Repository Update

```bash
cd argononeup-automatic-shutdown
git pull

# Reinstall (preserves no state)
./uninstall
./install
```

### Version Compatibility

| From Version | To Version | Action |
|--------------|------------|--------|
| Any | Any | Full reinstall (no migration needed) |

**No data migration needed** — no persistent state.

## Security Operations

### Permission Audit

```bash
# Check file permissions
ls -la ~/.local/bin/argononeup-automatic-shutdown
# Should be: -rwxr-xr-x (755)

ls -la ~/.config/systemd/user/argononeup-automatic-shutdown.service
# Should be: -rw-r--r-- (644)

# Check service runs as user (not root)
systemctl --user show argononeup-automatic-shutdown.service --property=User
# Should show your UID
```

### Attack Surface

| Vector | Exposure | Mitigation |
|--------|----------|------------|
| D-Bus | Session bus only | User-scoped |
| GPIO | `/dev/gpiochip0` | Group permissions |
| Sysfs | `/sys/class/power_supply/BAT0` | World-readable |
| `who` | utmp file | World-readable |
| `systemctl poweroff` | User authorization | Polkit + inhibitors |

**No network exposure, no root privileges, no setuid binaries.**

## Capacity Planning

### Resource Usage

| Resource | Typical | Peak | Scaling |
|----------|---------|------|---------|
| Memory | 2-4 MB | 5 MB | Constant |
| CPU | <0.1% | <1% (burst) | Constant |
| Disk I/O | None | Log writes | Journal only |
| Network | None | None | N/A |

**No capacity concerns** — negligible resource usage.

### Multi-User Systems

- Each user runs independent instance
- No cross-user interference
- Each user must install separately
- Resource usage multiplies linearly (still negligible)

## Decommissioning

### Permanent Removal

```bash
# Run uninstall
./uninstall

# Verify
systemctl --user status argononeup-automatic-shutdown.service 2>&1 | grep -q "not found" && echo "Removed"
ls ~/.local/bin/argononeup-automatic-shutdown 2>/dev/null || echo "Script removed"
ls ~/.config/systemd/user/argononeup-automatic-shutdown.service 2>/dev/null || echo "Service removed"
```

### Cleanup Verification

```bash
# No orphaned processes
pgrep -f argononeup-automatic-shutdown || echo "No processes"

# No systemd units
systemctl --user list-unit-files | grep argononeup || echo "No units"

# No journal entries (optional - will age out)
journalctl --user -u argononeup-automatic-shutdown.service --no-pager | head -5
```

## Operational Runbooks

### Runbook: Service Down Alert

```
1. Check service status: systemctl --user status argononeup-automatic-shutdown.service
2. If failed: check logs: journalctl --user -u argononeup-automatic-shutdown.service -n 50
3. If missing dependencies: install missing packages
4. If permission issue: check gpio group membership
5. Restart: systemctl --user restart argononeup-automatic-shutdown.service
6. Verify: systemctl --user status argononeup-automatic-shutdown.service
7. If persistent: reinstall: ./uninstall && ./install
```

### Runbook: Unexpected Shutdown

```
1. Check journal: journalctl --user -u argononeup-automatic-shutdown.service --since="30 min ago"
2. Check inhibitors at time: (not logged, check systemd-inhibit --list now)
3. Verify thresholds: check lid state, battery, SSH at time
4. If false positive: check GPIO reliability, idle monitor accuracy
5. Consider increasing thresholds or confirmation delay
```

### Runbook: Hardware Change (New Laptop)

```
1. Identify new GPIO pin for lid: check kernel docs or gpiofind
2. Identify new battery path: ls /sys/class/power_supply/
3. Update script constants:
   - gpioget chip/pin in is_lid_open()
   - BATTERY_STATUS_PATH
4. Reinstall: ./uninstall && ./install
5. Test all components
6. Verify thresholds appropriate for new hardware
```

## Contact & Escalation

**Repository:** https://github.com/hmlendea/argononeup-automatic-shutdown

**Issues:** GitHub Issues for bugs, feature requests

**Documentation:** This repository's `docs/` directory

**Author:** hmlendea (https://hmlendea.go.ro)
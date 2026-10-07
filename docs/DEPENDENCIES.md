# Dependencies Documentation

## Overview

This document catalogs all external dependencies of the argononeup-automatic-shutdown system, their contracts, version requirements, and failure behaviors.

## Dependency Matrix

| Dependency | Type | Purpose | Required | Version Constraint | Failure Behavior |
|------------|------|---------|----------|-------------------|------------------|
| `bash` | Runtime | Script interpreter | ✅ | ≥ 4.0 | Script won't execute |
| `systemd` (user) | Runtime | Service management | ✅ | ≥ 230 | Service won't start |
| `gdbus` | CLI tool | D-Bus communication | ✅ | Part of glib2 | Idle detection fails |
| `gpioget` | CLI tool | GPIO reading | ✅ | Part of libgpiod-tools | Lid detection fails |
| `who` | CLI tool | SSH session detection | ✅ | Part of util-linux | SSH detection fails |
| `sed` | CLI tool | Text processing | ✅ | GNU sed | Idle parsing fails |
| `grep` | CLI tool | Pattern matching | ✅ | GNU grep | SSH/lid detection fails |
| `date` | CLI tool | Timestamp generation | ✅ | GNU coreutils | Charging grace fails |
| `sleep` | CLI tool | Timing control | ✅ | GNU coreutils | Loop timing fails |
| `install` | CLI tool | File installation | ✅ | GNU coreutils | Install script fails |
| `mkdir` | CLI tool | Directory creation | ✅ | GNU coreutils | Install script fails |
| `rm` | CLI tool | File removal | ✅ | GNU coreutils | Uninstall script fails |
| `systemctl` | CLI tool | Service control | ✅ | Part of systemd | Install/uninstall fails |
| GNOME Mutter | Service | Idle monitor D-Bus | ✅ | GNOME ≥ 3.36 | Idle detection fails |
| Linux kernel | Kernel | GPIO, sysfs, poweroff | ✅ | ≥ 5.0 | Hardware access fails |

## Detailed Dependency Contracts

### 1. bash (GNU Bash)

**Role:** Script interpreter for `argononeup-automatic-shutdown.sh`, `install`, `uninstall`

**Required features:**
- Arithmetic evaluation: `(( ... ))`
- Local variables: `local`
- Function definitions
- Command substitution: `$(...)`
- Process substitution: `<(...)`
- Array support (not used but available)
- `set -euo pipefail` support

**Version:** ≥ 4.0 (released 2009) — universally available on supported systems

**Failure mode:** Script fails to parse/execute with syntax errors

**Location:** `/usr/bin/bash` (shebang: `#!/usr/bin/env bash`)

### 2. systemd (User Instance)

**Role:** Service manager for user-level service

**Required features:**
- User service support (`systemctl --user`)
- `graphical-session.target` integration
- `Restart=always`, `RestartSec`, `StartLimitIntervalSec`
- `StandardOutput=journal`, `StandardError=journal`
- `systemctl --user daemon-reload`
- `systemctl --user enable --now`
- `systemctl --user disable --now`
- `systemctl poweroff -i` (inhibitor support)

**Version:** ≥ 230 (2016) — user service support mature

**Failure mode:** Service cannot be installed/started; install script exits with error

**Integration points:**
- Service file: `~/.config/systemd/user/argononeup-automatic-shutdown.service`
- Commands: `systemctl --user *`

### 3. gdbus (GLib D-Bus Tool)

**Role:** Query GNOME Mutter idle monitor over session D-Bus

**Command signature:**
```bash
gdbus call \
    --session \
    --dest org.gnome.Mutter.IdleMonitor \
    --object-path /org/gnome/Mutter/IdleMonitor/Core \
    --method org.gnome.Mutter.IdleMonitor.GetIdletime
```

**Expected response format:**
```
(uint64 <milliseconds>,)
```

**Parsing:** `sed -E 's/.*uint64 ([0-9]+).*/\1/'`

**Contract:**
- Must be run in user session with D-Bus session bus
- Requires GNOME/Mutter running with IdleMonitor enabled
- Returns idle time in milliseconds since last user input

**Package:** `glib2` (provides `gdbus`)

**Failure modes:**
| Failure | Output | Parsed result |
|---------|--------|---------------|
| D-Bus not running | Error to stderr | Empty string |
| Mutter not running | Error to stderr | Empty string |
| IdleMonitor not available | Error to stderr | Empty string |
| Permission denied | Error to stderr | Empty string |

**Downstream:** Empty string → arithmetic treats as 0 → no shutdown (safe)

### 4. gpioget (libgpiod-tools)

**Role:** Read GPIO pin state for lid detection

**Command signature:**
```bash
gpioget --chip gpiochip0 GPIO27
```

**Expected output format:**
```
GPIO27=inactive
```
or
```
GPIO27=active
```

**Parsing:** `grep -q '=inactive$'`

**Hardware contract (Argon ONE UP CM5):**
- GPIO chip: `gpiochip0`
- GPIO line: `27`
- `inactive` = lid open
- `active` = lid closed
- Active-low logic (switch pulls to ground when closed)

**Package:** `libgpiod-tools`

**Failure modes:**
| Failure | Output | Parsed result |
|---------|--------|---------------|
| gpiochip0 not found | Error to stderr | Empty → grep fails → false |
| GPIO27 not exported | Error to stderr | Empty → grep fails → false |
| Permission denied | Error to stderr | Empty → grep fails → false |
| libgpiod not installed | Command not found | Script error |

**Downstream:** `is_lid_open` returns false → uses 5-min threshold (conservative)

**Note:** Requires user to be in `gpio` group or udev rules for GPIO access

### 5. who (util-linux)

**Role:** List logged-in users to detect SSH sessions

**Command signature:**
```bash
who
```

**Expected output format:**
```
user     tty7         2024-01-15 10:30 (:0)
user     pts/0        2024-01-15 10:35 (192.168.1.50)
user     pts/1        2024-01-15 10:40 (10.0.0.42)
```

**Detection pattern:** `grep -qE '\(.*\)'`

**Matches:** Lines containing parentheses with content (remote IP/hostname)

**Does NOT match:** Local sessions (`:0`, `:1`, etc.)

**Package:** `util-linux`

**Failure modes:**
| Failure | Output | Parsed result |
|---------|--------|---------------|
| Command not found | Error | grep finds nothing → false |
| Permission denied | Error | grep finds nothing → false |
| utmp corrupted | Garbled | Unpredictable |

**Downstream:** False negative (no SSH detected) → shutdown allowed

**Limitations:**
- Only detects PTY-allocated sessions
- Misses: SSH tunnels, connection sharing, SCP/SFTP-only, Mosh, non-PTY remoting

### 6. sed (GNU sed)

**Role:** Extract numeric value from D-Bus response

**Command:**
```bash
sed -E 's/.*uint64 ([0-9]+).*/\1/'
```

**Input:** `(uint64 1234567,)`

**Output:** `1234567`

**Package:** `sed` (GNU sed required for `-E` extended regex)

**Failure modes:**
| Failure | Result |
|---------|--------|
| No match | Empty output |
| Multiple matches | First match |
| Non-GNU sed | `-E` may not work |

### 7. grep (GNU grep)

**Role:** Pattern matching for SSH detection and lid state

**Commands:**
```bash
grep -qE '\(.*\)'      # SSH detection
grep -q '=inactive$'   # Lid open detection
```

**Package:** `grep` (GNU grep)

**Flags used:**
- `-q`: Quiet (exit code only)
- `-E`: Extended regex

**Failure modes:** Exit code 1 (no match) or 2 (error) — both treated as "not found"

### 8. date (GNU coreutils)

**Role:** Get current epoch timestamp for charging grace period

**Command:**
```bash
date +%s
```

**Output:** Unix timestamp (seconds since 1970-01-01 UTC)

**Package:** `coreutils`

**Failure modes:** Non-zero exit → empty output → arithmetic error → script crash

### 9. sleep (GNU coreutils)

**Role:** Timing control for loop interval and confirmation delay

**Commands:**
```bash
sleep 20   # Main loop interval
sleep 5    # Confirmation delay
```

**Package:** `coreutils`

**Failure modes:** Interrupted by signal → exits early → shorter interval

### 10. install (GNU coreutils)

**Role:** Copy files with mode preservation during installation

**Command:**
```bash
install -m 755 source destination
install -m 644 source destination
```

**Package:** `coreutils`

**Failure modes:** Permission denied, source missing, destination unwritable

### 11. mkdir (GNU coreutils)

**Role:** Create destination directories

**Command:**
```bash
mkdir -p "$(dirname destination)"
```

**Package:** `coreutils`

### 12. rm (GNU coreutils)

**Role:** Remove installed files during uninstall

**Command:**
```bash
rm -f path
```

**Package:** `coreutils`

### 13. systemctl (systemd)

**Role:** Service control for install/uninstall and poweroff

**Commands:**
```bash
systemctl --user daemon-reload
systemctl --user enable --now service-name
systemctl --user disable --now service-name
systemctl poweroff -i
```

**Package:** `systemd`

**Failure modes:** Non-zero exit → install/uninstall script exits with error

### 14. GNOME Mutter (Desktop Environment)

**Role:** Provides idle monitor D-Bus service

**D-Bus Service:** `org.gnome.Mutter.IdleMonitor`

**Object Path:** `/org/gnome/Mutter/IdleMonitor/Core`

**Method:** `org.gnome.Mutter.IdleMonitor.GetIdletime`

**Return:** `uint64` (milliseconds)

**Version:** GNOME ≥ 3.36 (2020) — IdleMonitor introduced

**Availability:** Only in GNOME Shell sessions (Wayland or X11)

**Non-GNOME environments:** Not available (KDE, XFCE, i3, sway, etc.)

**Failure mode:** D-Bus call fails → idle detection returns 0 → no shutdown

### 15. Linux Kernel Interfaces

#### 15.1 GPIO Sysfs / libgpiod

**Interface:** `gpiochip0` character device (`/dev/gpiochip0`)

**Access:** Via `libgpiod` library (used by `gpioget`)

**Requirements:**
- Kernel config: `CONFIG_GPIO_SYSFS` or `CONFIG_GPIO_LIBGPIO`
- User permissions: `gpio` group or udev rules
- Hardware: Argon ONE UP CM5 GPIO mapping

#### 15.2 Power Supply Sysfs

**Path:** `/sys/class/power_supply/BAT0/status`

**Possible values:** `Charging`, `Discharging`, `Full`, `Not charging`, `Unknown`

**Read permissions:** World-readable (typically)

**Failure mode:** Unreadable → `[[ -r ... ]]` fails → charging check passes

#### 15.3 System Poweroff

**Command:** `systemctl poweroff -i`

**Mechanism:** systemd → logind → kernel `reboot(RB_POWER_OFF)`

**Inhibitor support:** `-i` flag respects `org.freedesktop.login1.Inhibit`

**Requirements:** User session with logind, polkit authorization for poweroff

## Installation-Time Dependencies

| Tool | Purpose | Required for |
|------|---------|--------------|
| `install` | Copy files with modes | `install` script |
| `mkdir` | Create directories | `install` script |
| `systemctl --user` | Service management | `install`/`uninstall` scripts |
| `bash` | Run install/uninstall | Both scripts |

## Runtime Dependencies (Daemon)

| Tool | Purpose | Called from |
|------|---------|-------------|
| `gdbus` | Idle time query | `get_idle_time_ms()` |
| `gpioget` | Lid state | `is_lid_open()` |
| `who` | SSH sessions | `has_active_ssh_connections()` |
| `cat`/`read` | Battery status | `is_battery_charging()` |
| `date` | Timestamps | `should_skip_shutdown_due_to_charging()` |
| `sleep` | Loop timing | Main loop |
| `sed` | D-Bus parsing | `get_idle_time_ms()` |
| `grep` | Pattern matching | SSH/lid functions |
| `systemctl` | Poweroff | Main loop (shutdown) |

## Optional / Future Dependencies

| Dependency | Purpose | Status |
|------------|---------|--------|
| `notify-send` | Desktop notifications | Not used |
| `loginctl` | Session info | Not used |
| `upower` | Battery info (alternative) | Not used |
| `acpi` | AC power detection | Not used |
| `dbus-monitor` | Debugging | Not used |

## Dependency Verification Commands

```bash
# Check all CLI tools
for cmd in bash systemctl gdbus gpioget who sed grep date sleep install mkdir rm; do
    command -v "$cmd" >/dev/null && echo "✅ $cmd" || echo "❌ $cmd MISSING"
done

# Check GNOME IdleMonitor
gdbus call --session --dest org.gnome.Mutter.IdleMonitor \
    --object-path /org/gnome/Mutter/IdleMonitor/Core \
    --method org.gnome.Mutter.IdleMonitor.GetIdletime 2>/dev/null && echo "✅ IdleMonitor" || echo "❌ IdleMonitor unavailable"

# Check GPIO access
gpioget --chip gpiochip0 GPIO27 2>/dev/null && echo "✅ GPIO access" || echo "❌ GPIO access failed"

# Check battery sysfs
[[ -r /sys/class/power_supply/BAT0/status ]] && echo "✅ Battery sysfs" || echo "❌ Battery sysfs unreadable"

# Check systemd user
systemctl --user status >/dev/null 2>&1 && echo "✅ systemd user" || echo "❌ systemd user unavailable"
```

## Version Compatibility Matrix

| Component | Minimum Version | Tested Version | Notes |
|-----------|-----------------|----------------|-------|
| bash | 4.0 | 5.2 | Universal |
| systemd | 230 | 255 | User services stable |
| glib2 (gdbus) | 2.56 | 2.80 | D-Bus API stable |
| libgpiod-tools | 1.6 | 2.0 | GPIO character device |
| util-linux (who) | 2.33 | 2.40 | utmp format stable |
| coreutils | 8.30 | 9.5 | All tools stable |
| GNOME | 3.36 | 46 | IdleMonitor since 3.36 |
| Linux kernel | 5.0 | 6.8 | GPIO, sysfs stable |

## Packaging Dependencies (Distribution Packages)

### Debian/Ubuntu
```bash
apt install bash systemd libglib2.0-bin libgpiod-tools util-linux coreutils
```

### Fedora/RHEL
```bash
dnf install bash systemd glib2 libgpiod util-linux coreutils
```

### Arch Linux
```bash
pacman -S bash systemd glib2 libgpiod util-linux coreutils
```

### openSUSE
```bash
zypper install bash systemd glib2-tools libgpiod-tools util-linux coreutils
```

## Hardware-Specific Dependencies

| Hardware | Dependency | Notes |
|----------|------------|-------|
| Argon ONE UP CM5 | GPIO27 on gpiochip0 | Lid switch |
| Argon ONE UP CM5 | BAT0 power supply | Battery status |
| Any x86_64/ARM64 | Linux kernel | Generic |

**Portability:** Script is hardware-specific (GPIO pin, battery path). Porting requires:
1. Different GPIO chip/line for lid
2. Different battery path (BAT1, BATC, etc.)
3. Different idle monitor for non-GNOME DEs

## Security Dependencies

| Mechanism | Purpose |
|-----------|---------|
| User namespace | Service runs as user, not root |
| systemd inhibitors | `-i` flag respects app vetoes |
| D-Bus session bus | User-scoped, no system access |
| GPIO permissions | Requires `gpio` group or udev rule |
| polkit | `systemctl poweroff` authorization |

No network dependencies, no setuid, no capabilities required.
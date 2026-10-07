# Testing Documentation

## Overview

This document describes the testing strategy, verification procedures, and test cases for the argononeup-automatic-shutdown system.

## Current Test Status

**Automated tests:** None exist.

**Manual verification:** Primary validation method.

**Test infrastructure:** No test framework, no CI/CD pipeline.

## Manual Verification Procedures

### 1. Installation Verification

```bash
# From repository root
chmod +x install uninstall argononeup-automatic-shutdown.sh
./install

# Verify files installed
ls -la ~/.local/bin/argononeup-automatic-shutdown
ls -la ~/.config/systemd/user/argononeup-automatic-shutdown.service

# Verify service status
systemctl --user status argononeup-automatic-shutdown.service
```

**Expected:**
- Script installed at `~/.local/bin/argononeup-automatic-shutdown` (mode 755)
- Service installed at `~/.config/systemd/user/argononeup-automatic-shutdown.service` (mode 644)
- Service shows `active (running)`

### 2. Component-Level Testing

Each detection component can be tested independently:

#### 2.1 Idle Monitor (GNOME Mutter)

```bash
# Query idle time
gdbus call --session \
    --dest org.gnome.Mutter.IdleMonitor \
    --object-path /org/gnome/Mutter/IdleMonitor/Core \
    --method org.gnome.Mutter.IdleMonitor.GetIdletime

# Expected output format: (uint64 <milliseconds>,)
# Example: (uint64 1234567,)
```

**Verification:**
- Command succeeds (exit code 0)
- Output contains `uint64` followed by number
- Value increases when no input, resets on input

#### 2.2 Lid State (GPIO)

```bash
# Read lid GPIO
gpioget --chip gpiochip0 GPIO27

# Expected output:
# GPIO27=inactive   (lid open)
# GPIO27=active     (lid closed)
```

**Verification:**
- Command succeeds
- Output matches `GPIO27=inactive` or `GPIO27=active`
- State changes when lid opened/closed

#### 2.3 Battery Status

```bash
# Read battery status
cat /sys/class/power_supply/BAT0/status

# Expected values:
# Charging
# Discharging
# Full
# Not charging
# Unknown
```

**Verification:**
- File readable
- Value is one of expected states
- Changes when charger plugged/unplugged

#### 2.4 SSH Session Detection

```bash
# List sessions
who

# Expected output with remote session:
# user     pts/0        2024-01-15 10:30 (192.168.1.50)

# Test detection logic
who | grep -qE '\(.*\)' && echo "SSH detected" || echo "No SSH"
```

**Verification:**
- Local session shows `(:0)` or `(:1)` — no parentheses with IP
- Remote SSH shows `(IP)` or `(hostname)` — matches pattern
- Detection logic returns correct result

### 3. End-to-End Behavior Testing

#### 3.1 Idle Threshold Test (Lid Open)

**Setup:** Lid open, no SSH, battery not charging

**Procedure:**
1. Ensure lid is open (`gpioget` shows `inactive`)
2. Ensure no SSH sessions (`who` shows no `(IP)`)
3. Ensure battery not charging (`cat /sys/class/power_supply/BAT0/status` ≠ `Charging`)
4. Wait 30+ minutes without input
5. Observe shutdown

**Expected:** System powers off after ~30 minutes idle

#### 3.2 Idle Threshold Test (Lid Closed)

**Setup:** Lid closed, no SSH, battery not charging

**Procedure:**
1. Close lid (`gpioget` shows `active`)
2. Ensure no SSH sessions
3. Ensure battery not charging
4. Wait 5+ minutes without input
5. Observe shutdown

**Expected:** System powers off after ~5 minutes idle

#### 3.3 SSH Protection Test

**Setup:** Active SSH session, idle threshold exceeded

**Procedure:**
1. Establish SSH connection to machine
2. Verify `who` shows remote session
3. Wait for idle threshold to exceed (30 min open / 5 min closed)
4. Observe: system should NOT shut down

**Expected:** Shutdown skipped while SSH active

#### 3.4 Charging Protection Test

**Setup:** Battery charging, idle threshold exceeded

**Procedure:**
1. Plug in charger (verify `Charging` status)
2. Wait for idle threshold to exceed
3. Observe: system should NOT shut down

**Expected:** Shutdown skipped while charging

#### 3.5 Charging Grace Period Test

**Setup:** Was charging, now unplugged, idle threshold exceeded

**Procedure:**
1. Plug in charger, wait for `Charging` status
2. Unplug charger (status becomes `Discharging`)
3. Wait for idle threshold to exceed
4. Within 5 minutes: system should NOT shut down
5. After 5+ minutes: system SHOULD shut down (if other conditions met)

**Expected:** 5-minute grace period after unplugging

#### 3.6 Double-Confirmation Test

**Setup:** Idle threshold exceeded, all conditions met

**Procedure:**
1. Wait for idle > threshold
2. At moment of threshold crossing, immediately provide input (mouse/keyboard)
3. Observe: system should NOT shut down

**Expected:** 5-second confirmation window allows abort

#### 3.7 Inhibitor Respect Test

**Setup:** Application with shutdown inhibitor running

**Procedure:**
1. Run app that registers inhibitor (e.g., `systemd-inhibit --what=shutdown --why="test" sleep 300`)
2. Wait for idle threshold to exceed
3. Observe: `systemctl poweroff -i` should be blocked

**Expected:** Shutdown inhibited, system stays on

### 4. Service Management Testing

#### 4.1 Service Auto-Start

```bash
# Log out and log back in
# Verify service starts automatically
systemctl --user status argononeup-automatic-shutdown.service
```

**Expected:** Service `active (running)` after graphical login

#### 4.2 Service Auto-Stop

```bash
# Log out
# Verify service stops
systemctl --user status argononeup-automatic-shutdown.service
```

**Expected:** Service `inactive (dead)` after logout

#### 4.3 Crash Recovery

```bash
# Kill the script process
pkill -f argononeup-automatic-shutdown

# Verify systemd restarts it (within 10s)
systemctl --user status argononeup-automatic-shutdown.service
```

**Expected:** Service restarts automatically, new PID

#### 4.4 Uninstall Verification

```bash
./uninstall

# Verify removal
ls ~/.local/bin/argononeup-automatic-shutdown 2>/dev/null || echo "Script removed"
ls ~/.config/systemd/user/argononeup-automatic-shutdown.service 2>/dev/null || echo "Service removed"

# Verify service gone
systemctl --user status argononeup-automatic-shutdown.service 2>&1 | grep -q "not found" && echo "Service unregistered"
```

**Expected:** All files removed, service unregistered

## Test Cases Matrix

| Test Case | Component | Conditions | Expected Result | Priority |
|-----------|-----------|------------|-----------------|----------|
| TC-01 | Idle monitor | GNOME running | Returns uint64 ms | Critical |
| TC-02 | Idle monitor | Non-GNOME DE | Fails gracefully | High |
| TC-03 | Lid detection | Lid open | Returns `inactive` | Critical |
| TC-04 | Lid detection | Lid closed | Returns `active` | Critical |
| TC-05 | Lid detection | GPIO unavailable | Returns false (closed) | High |
| TC-06 | Battery status | Charging | Returns `Charging` | Critical |
| TC-07 | Battery status | Discharging | Returns `Discharging` | Critical |
| TC-08 | Battery status | Sysfs unreadable | Treats as not charging | High |
| TC-09 | SSH detection | Local only | No SSH detected | Critical |
| TC-10 | SSH detection | Remote SSH | SSH detected | Critical |
| TC-11 | SSH detection | SSH tunnel only | No SSH detected (limitation) | Medium |
| TC-12 | Threshold selection | Lid open | 30 min (1,800,000 ms) | Critical |
| TC-13 | Threshold selection | Lid closed | 5 min (300,000 ms) | Critical |
| TC-14 | Main loop | Idle < threshold | No action, sleep 20s | Critical |
| TC-15 | Main loop | Idle ≥ threshold, SSH active | No shutdown | Critical |
| TC-16 | Main loop | Idle ≥ threshold, charging | No shutdown | Critical |
| TC-17 | Main loop | Idle ≥ threshold, grace period | No shutdown | Critical |
| TC-18 | Main loop | All conditions met | Shutdown after 5s confirm | Critical |
| TC-19 | Confirmation | Input during 5s | Shutdown aborted | High |
| TC-20 | Confirmation | Lid change during 5s | Threshold re-evaluated | High |
| TC-21 | Poweroff | Inhibitor present | Shutdown blocked | High |
| TC-22 | Service | Graphical login | Auto-starts | Critical |
| TC-23 | Service | Graphical logout | Auto-stops | Critical |
| TC-24 | Service | Script crash | Restarts in 10s | High |
| TC-25 | Install | Clean system | Files + service installed | Critical |
| TC-26 | Uninstall | Installed system | Files + service removed | Critical |

## Regression Testing Checklist

Run after any code changes:

- [ ] Install script completes without error
- [ ] Uninstall script completes without error
- [ ] Service starts and shows `active (running)`
- [ ] `gdbus` idle query returns valid uint64
- [ ] `gpioget` returns valid lid state
- [ ] Battery status readable
- [ ] `who` output parsed correctly
- [ ] Threshold calculation correct for both lid states
- [ ] Charging grace period logic correct
- [ ] Double-confirmation delay works
- [ ] `systemctl poweroff -i` executes (test with inhibitor)
- [ ] Service restarts after `pkill`
- [ ] Logs appear in `journalctl --user -u argononeup-automatic-shutdown.service`

## Performance Benchmarks

### Resource Usage (Typical)

| Metric | Value | Measurement |
|--------|-------|-------------|
| Memory (RSS) | ~2-4 MB | `ps -o rss= -p <pid>` |
| CPU (idle) | ~0% | `top -p <pid>` |
| CPU (active check) | <1% for <10ms | Per iteration |
| Disk I/O | None (except logs) | `iotop` |
| Network I/O | None | `nethogs` |

### Timing Characteristics

| Operation | Duration | Frequency |
|-----------|----------|-----------|
| Idle query (gdbus) | 5-20 ms | Every 20s |
| Lid query (gpioget) | 2-10 ms | Every 20s + confirm |
| SSH query (who) | 1-5 ms | Every 20s + confirm |
| Battery read (sysfs) | <1 ms | Every 20s + confirm |
| Full iteration | 10-40 ms | Every 20s |

## Failure Injection Testing

### Simulated Failures

```bash
# 1. D-Bus unavailable
# Stop D-Bus session bus (not recommended on running system)
# Or mock: rename gdbus temporarily

# 2. GPIO unavailable
sudo chmod 000 /dev/gpiochip0  # Remove permissions
# Test: should use closed-lid threshold (5 min)

# 3. Battery sysfs unreadable
sudo chmod 000 /sys/class/power_supply/BAT0/status
# Test: should allow shutdown (no charging protection)

# 4. who command fails
# Mock: create wrapper that fails
# Test: should allow shutdown (no SSH protection)

# 5. systemctl poweroff fails
# Mock: create wrapper that returns error
# Test: should log error, continue loop
```

**Expected:** All failures degrade gracefully (no shutdown on false positive)

## Test Environment Requirements

### Minimum Test Environment

- Linux with systemd (user services)
- GNOME Shell ≥ 3.36
- Argon ONE UP CM5 hardware (or GPIO mock)
- Battery (BAT0) or mock sysfs
- SSH server for remote session testing

### Mock Environment (for CI)

```bash
# Mock gdbus for idle time
cat > /usr/local/bin/gdbus <<'EOF'
#!/bin/bash
if [[ "$*" == *"GetIdletime"* ]]; then
    echo "(uint64 1800000,)"  # 30 min
fi
EOF
chmod +x /usr/local/bin/gdbus

# Mock gpioget for lid state
cat > /usr/local/bin/gpioget <<'EOF'
#!/bin/bash
echo "GPIO27=inactive"  # lid open
EOF
chmod +x /usr/local/bin/gpioget

# Mock who for SSH
cat > /usr/local/bin/who <<'EOF'
#!/bin/bash
echo "user     tty7         2024-01-15 10:30 (:0)"
EOF
chmod +x /usr/local/bin/who

# Mock battery status
mkdir -p /tmp/mock_sysfs/power_supply/BAT0
echo "Discharging" > /tmp/mock_sysfs/power_supply/BAT0/status
export BATTERY_STATUS_PATH="/tmp/mock_sysfs/power_supply/BAT0/status"
```

## Future Test Infrastructure

### Recommended Additions

| Test Type | Framework | Effort | Value |
|-----------|-----------|--------|-------|
| Unit tests (bash) | bats-core | Low | Function-level verification |
| Integration tests | bats + mocks | Medium | Full flow verification |
| Hardware-in-loop | Custom + device | High | Real hardware validation |
| CI/CD pipeline | GitHub Actions | Low | Automated regression |

### Example bats Test Structure

```bash
# test/argononeup.bats
@test "get_idle_time_ms returns numeric value" {
    run get_idle_time_ms
    [[ "$output" =~ ^[0-9]+$ ]]
}

@test "is_lid_open returns true for inactive" {
    # Mock gpioget
    function gpioget() { echo "GPIO27=inactive"; }
    run is_lid_open
    [ "$status" -eq 0 ]
}

@test "should_skip_shutdown_due_to_charging respects grace period" {
    # Mock date and battery
    function date() { echo "1000"; }
    function is_battery_charging() { return 1; }
    LAST_CHARGING_EPOCH=500
    CHARGING_GRACE_SEC=300
    run should_skip_shutdown_due_to_charging
    [ "$status" -eq 0 ]  # within grace
}
```

## Debugging Aids

### Verbose Mode (Manual)

Add to script temporarily:
```bash
set -x  # Enable debug tracing
```

### Log Inspection

```bash
# Follow logs live
journalctl --user -u argononeup-automatic-shutdown.service -f

# Last 100 lines
journalctl --user -u argononeup-automatic-shutdown.service -n 100

# Since boot
journalctl --user -u argononeup-automatic-shutdown.service -b
```

### Dry-Run Mode (Proposed)

Add `--dry-run` flag to script:
```bash
# Would log decisions without executing poweroff
DRY_RUN=1 ./argononeup-automatic-shutdown.sh
```

## Known Test Gaps

| Gap | Impact | Mitigation |
|-----|--------|------------|
| No automated tests | Regression risk | Manual checklist |
| No non-GNOME testing | Portability unknown | Document limitation |
| No multi-battery testing | Edge case | Single BAT0 assumption |
| No inhibitor stress test | Reliability | Manual verification |
| No long-run stability test | Memory leaks | systemd restart safety net |
| No concurrent user test | Multi-user | User-scoped service isolation |

## Test Reporting

For manual test runs, record:

```
Test Run: YYYY-MM-DD
Tester: <name>
Environment: <distro, kernel, GNOME version, hardware>
Results:
  TC-01: PASS/FAIL - <notes>
  TC-02: PASS/FAIL - <notes>
  ...
Overall: PASS/FAIL
Blockers: <any critical failures>
```
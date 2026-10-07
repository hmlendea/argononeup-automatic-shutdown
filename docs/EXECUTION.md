# Execution Flow Documentation

## Overview

This document traces the complete execution flow of the argononeup-automatic-shutdown system, from service startup through shutdown decision, including all branches, failure paths, and state transitions.

## Startup Sequence

### 1. Service Activation

```
User logs in → graphical-session.target fires → systemd --user
  → argononeup-automatic-shutdown.service activated
  → ExecStart: %h/.local/bin/argononeup-automatic-shutdown
  → bash interpreter loads script
  → constants initialized
  → main loop begins
```

**Timing:** Service starts when graphical session starts (login).

**Lifecycle:** Service stops when graphical session ends (logout) due to `PartOf=graphical-session.target`.

### 2. Script Initialization

```bash
# Line 1-12: Constants
THRESHOLD_LID_OPEN_MIN=30
THRESHOLD_LID_CLOSED_MIN=5
BATTERY_STATUS_PATH="/sys/class/power_supply/BAT0/status"
CHARGING_GRACE_MIN=5
LAST_CHARGING_EPOCH=0

# Line 14-16: Derived constants (computed once)
CHARGING_GRACE_SEC=$(( CHARGING_GRACE_MIN * 60 ))        # 300 seconds
THRESHOLD_LID_OPEN_MS=$(( THRESHOLD_LID_OPEN_MIN * 60 * 1000 ))   # 1,800,000 ms
THRESHOLD_LID_CLOSED_MS=$(( THRESHOLD_LID_CLOSED_MIN * 60 * 1000 )) # 300,000 ms
```

**State:** `LAST_CHARGING_EPOCH` initialized to 0 (no charging recorded).

**Failure:** If any constant is malformed, script exits with syntax error before loop.

## Main Loop Execution

### Loop Structure

```
┌─────────────────────────────────────────────────────────────┐
│                    while true (iteration N)                 │
├─────────────────────────────────────────────────────────────┤
│  1. IDLE_TIME_MS = get_idle_time_ms()                       │
│  2. THRESHOLD_MS = get_threshold()                          │
│  3. if IDLE_TIME_MS >= THRESHOLD_MS:                        │
│       4. if !ssh && !charging:                              │
│            5. sleep 5 (confirmation delay)                  │
│            6. Re-check: IDLE_TIME_NEW_MS, THRESHOLD_MS      │
│            7. if all conditions met:                        │
│                 8. systemctl poweroff -i                    │
│  9. sleep 20 (check interval)                              │
└─────────────────────────────────────────────────────────────┘
```

### Step 1: Idle Time Query

**Function:** `get_idle_time_ms()`

**Execution:**
```bash
gdbus call \
    --session \
    --dest org.gnome.Mutter.IdleMonitor \
    --object-path /org/gnome/Mutter/IdleMonitor/Core \
    --method org.gnome.Mutter.IdleMonitor.GetIdletime \
| sed -E 's/.*uint64 ([0-9]+).*/\1/'
```

**D-Bus contract:**
- **Bus:** Session bus (`--session`)
- **Destination:** `org.gnome.Mutter.IdleMonitor`
- **Object path:** `/org/gnome/Mutter/IdleMonitor/Core`
- **Method:** `org.gnome.Mutter.IdleMonitor.GetIdletime`
- **Return type:** `uint64` (milliseconds since last user activity)

**Parsing:** `sed` extracts the numeric value from D-Bus response format `uint64 <value>`.

**Return value:** Idle time in milliseconds, or empty string on failure.

**Failure paths:**
| Failure | Return | Downstream effect |
|---------|--------|-------------------|
| D-Bus unavailable | empty string | `IDLE_TIME_MS` empty → comparison fails → no shutdown |
| Mutter not running | empty string | Same as above |
| `sed` fails | empty string | Same as above |

**Note:** Empty string in arithmetic comparison `(( IDLE_TIME_MS >= THRESHOLD_MS ))` evaluates to 0, which is less than any threshold → safe no-op.

### Step 2: Threshold Selection

**Function:** `get_threshold()`

**Execution:**
```bash
if is_lid_open; then
    echo ${THRESHOLD_LID_OPEN_MS}   # 1,800,000 ms (30 min)
else
    echo ${THRESHOLD_LID_CLOSED_MS} # 300,000 ms (5 min)
fi
```

**Dependency:** `is_lid_open()` — reads GPIO27 state.

**Failure path:** If `gpioget` fails, `is_lid_open` returns false → closed threshold (5 min) used. Conservative default.

### Step 3: Idle Threshold Check

**Condition:** `IDLE_TIME_MS >= THRESHOLD_MS`

**Semantics:** Idle time must be *at least* the threshold (inclusive).

**Branches:**
- **True:** Proceed to SSH and charging checks
- **False:** Skip to `sleep 20` (next iteration)

### Step 4: SSH and Charging Checks

**Condition:** `!has_active_ssh_connections() && !should_skip_shutdown_due_to_charging()`

**Both must be false** for shutdown to proceed.

#### 4a: SSH Check — `has_active_ssh_connections()`

**Execution:**
```bash
who | grep -qE '\(.*\)'
```

**Detection logic:** `who` output format for remote sessions:
```
user     pts/0        2024-01-15 10:30   (192.168.1.50)
```
The `(IP)` suffix matches `\(.*\)`.

**Return:** 0 (true) if remote session detected, 1 (false) otherwise.

**Failure path:** If `who` fails, grep finds nothing → returns false → SSH check passes (allows shutdown).

**Limitation:** Only detects PTY-allocated SSH sessions. Connection sharing (`ssh -M`), tunnels, and non-PTY sessions are invisible.

#### 4b: Charging Check — `should_skip_shutdown_due_to_charging()`

**Execution:**
```bash
local now
now=$(date +%s)

if is_battery_charging; then
    LAST_CHARGING_EPOCH=$now
    return 0  # skip shutdown
fi

(( LAST_CHARGING_EPOCH > 0 && now - LAST_CHARGING_EPOCH <= CHARGING_GRACE_SEC ))
```

**Logic:**
1. If battery currently charging: record epoch, skip shutdown
2. If last charging was within 5 minutes: skip shutdown (grace period)
3. Otherwise: allow shutdown

**State mutation:** `LAST_CHARGING_EPOCH` updated whenever charging detected.

**Failure path:** If `is_battery_charging` fails (unreadable sysfs), returns false → charging check passes.

### Step 5: Confirmation Delay

**Action:** `sleep 5`

**Purpose:** 5-second confirmation window before final verification.

**Rationale:**
- Prevents shutdown on transient idle spikes
- Allows lid state to stabilize
- Gives time for user to interact (which resets idle timer)

### Step 6: Re-verification

**Execution:**
```bash
IDLE_TIME_NEW_MS=$(get_idle_time_ms())
THRESHOLD_MS=$(get_threshold())
```

**Re-checks:**
- Idle time (may have increased)
- Threshold (may have changed if lid state changed)

**Note:** SSH and charging are NOT re-checked here (assumed stable during 5s window).

### Step 7: Final Decision

**Condition:**
```bash
IDLE_TIME_NEW_MS >= THRESHOLD_MS &&
!has_active_ssh_connections() &&
!should_skip_shutdown_due_to_charging()
```

**All three must hold** for shutdown to proceed.

### Step 8: Poweroff

**Command:** `systemctl poweroff -i`

**Flags:**
- `poweroff`: Request system power-off
- `-i`: Respect systemd inhibitors (allows other apps to block shutdown)

**Failure:** If poweroff fails, error logged to journal, loop continues.

### Step 9: Check Interval

**Action:** `sleep 20`

**Purpose:** 20-second polling interval between iterations.

**Total cycle time:** 20s (normal) or 25s (when idle threshold exceeded and conditions met).

## State Transition Diagram

```
                    ┌─────────────────────────────────────┐
                    │           MAIN LOOP                 │
                    │  (20s polling interval)             │
                    └───────────────┬─────────────────────┘
                                    │
                    ┌───────────────▼──────────────────────┐
                    │  IDLE_TIME >= THRESHOLD?             │
                    └───────┬──────────────┬───────────────┘
                            │              │
                          NO│              │YES
                            │              ▼
                            │     ┌────────────────────────────┐
                            │     │ SSH active OR charging?    │
                            │     └───────┬──────────────┬─────┘
                            │             │              │
                            │           YES│             │NO
                            │             │              ▼
                            │             │     ┌────────────────────┐
                            │             │     │ sleep 5 (confirm)  │
                            │             │     └──────────┬─────────┘
                            │             │                │
                            │             │                ▼
                            │             │     ┌────────────────────┐
                            │             │     │ Re-verify all      │
                            │             │     │ conditions         │
                            │             │     └──────────┬─────────┘
                            │             │                │
                            │             │              YES│
                            │             │                │
                            │             │                ▼
                            │             │     ┌────────────────────┐
                            │             │     │ systemctl          │
                            │             │     │ poweroff -i        │
                            │             │     └────────────────────┘
                            │             │
                            │             │
                            │             ▼
                            │     ┌────────────────────┐
                            │     │ sleep 20           │
                            │     └────────────────────┘
                            │
                            ▼
                    ┌────────────────────┐
                    │ sleep 20           │
                    └────────────────────┘
```

## Charging State Machine

```
                    ┌─────────────────────────────────────┐
                    │         CHARGING STATE MACHINE       │
                    └─────────────────────────────────────┘

    ┌──────────────────────────────────────────────────────────────┐
    │  STATE: CHARGING (or within grace period)                    │
    │  LAST_CHARGING_EPOCH = <current time>                        │
    │  Behavior: shutdown ALWAYS skipped                           │
    └──────────────────────────────────────────────────────────────┘
                                    │
                                    │ battery status != "Charging"
                                    │ AND grace period expired
                                    ▼
    ┌──────────────────────────────────────────────────────────────┐
    │  STATE: GRACE EXPIRED                                        │
    │  LAST_CHARGING_EPOCH = <old time>                            │
    │  Behavior: shutdown allowed if other conditions met          │
    └──────────────────────────────────────────────────────────────┘
                                    │
                                    │ battery status == "Charging"
                                    ▼
    ┌──────────────────────────────────────────────────────────────┐
    │  STATE: CHARGING (re-entered)                                │
    │  LAST_CHARGING_EPOCH = <new time>                            │
    │  Behavior: shutdown ALWAYS skipped                           │
    └──────────────────────────────────────────────────────────────┘
```

**Grace period:** 5 minutes after last `Charging` state.

## Failure Mode Execution Traces

### Trace 1: D-Bus Unavailable

```
Iteration N:
  get_idle_time_ms() → gdbus fails → empty output
  IDLE_TIME_MS = ""
  THRESHOLD_MS = 300000 (lid closed)
  (( "" >= 300000 )) → bash treats "" as 0 → FALSE
  → sleep 20
  → next iteration
```

**Result:** No shutdown, no error (silent degradation).

### Trace 2: Lid GPIO Failure

```
Iteration N:
  get_threshold() → is_lid_open() → gpioget fails → "=inactive$" not matched
  → is_lid_open returns FALSE
  → THRESHOLD_MS = 300000 (5 min, conservative)
  → proceeds with closed-lid threshold
```

**Result:** Uses 5-minute threshold (aggressive). Potential false positives if lid is actually open.

### Trace 3: Battery Sysfs Unreadable

```
Iteration N:
  is_battery_charging() → [[ -r "$BATTERY_STATUS_PATH" ]] → FALSE
  → returns FALSE
  → should_skip_shutdown_due_to_charging() → LAST_CHARGING_EPOCH=0 → FALSE
  → charging check PASSES (allows shutdown)
```

**Result:** Charging protection disabled. Shutdown allowed even if battery is charging.

### Trace 4: Grace Period Expiration

```
T0: Battery status = "Charging"
    → is_battery_charging() = TRUE
    → LAST_CHARGING_EPOCH = T0
    → shutdown skipped

T0 + 3 min: Battery status = "Not charging"
    → is_battery_charging() = FALSE
    → now - LAST_CHARGING_EPOCH = 180s <= 300s
    → shutdown skipped (grace)

T0 + 6 min: Battery status = "Not charging"
    → now - LAST_CHARGING_EPOCH = 360s > 300s
    → shutdown allowed (if idle + no SSH)
```

### Trace 5: Lid State Change During Confirmation

```
T0: Idle > threshold, no SSH, not charging
    → sleep 5

T0 + 2s: User opens lid
    → lid state changes: open → threshold becomes 30 min

T0 + 5s: Re-verification
    → THRESHOLD_MS = 1,800,000 (30 min)
    → IDLE_TIME_NEW_MS may still be < 1,800,000
    → shutdown CANCELLED
```

**Result:** Lid change during confirmation window can prevent shutdown.

## Concurrency Considerations

### Single-Threaded Execution

- Script runs as single process, single thread
- No internal concurrency
- No race conditions within script

### External Concurrency

| Actor | Interaction | Race condition? |
|-------|-------------|-----------------|
| systemd | restarts script on crash | No (old process dies before new starts) |
| User | logs out | No (service stopped by systemd) |
| Other apps | register shutdown inhibitors | Yes (handled by `-i` flag) |
| Hardware | lid/battery state changes | Yes (handled by re-verification) |

### Restart Behavior

```
Script crashes → systemd waits 10s → restarts script
  → LAST_CHARGING_EPOCH reset to 0 (in-memory state lost)
  → charging grace effectively reset
```

**Implication:** After a crash, charging protection resumes from scratch.

## Timing Analysis

| Event | Duration |
|-------|----------|
| Normal iteration | 20s |
| Idle threshold exceeded (no shutdown) | 20s |
| Idle threshold exceeded (shutdown path) | 25s |
| Grace period | 5 min |
| Max false-positive window | 25s (one full cycle) |
| Min detection latency | 20s (idle just after threshold) |
| Max detection latency | 40s (idle just before threshold) |

## Log Output

The script produces **no stdout/stderr output** during normal operation. All logging is handled by systemd journal for the service itself.

**Service logs:**
- Service start/stop events (systemd)
- Restart events (systemd)
- Any script errors (if script prints to stderr)

**Note:** The daemon is intentionally silent — no status logging during normal operation.

## Exit Conditions

| Condition | Exit code | Restart behavior |
|-----------|-----------|------------------|
| Normal (logout) | 0 | No (service stopped) |
| Script error | non-zero | Yes (Restart=always) |
| `systemctl poweroff` | varies | N/A (system shutting down) |
| Killed by signal | varies | Yes (Restart=always) |
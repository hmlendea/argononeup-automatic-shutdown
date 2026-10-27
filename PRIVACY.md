# Privacy and Personal Data

This document describes how argononeup-automatic-shutdown at https://github.com/hmlendea/argononeup-automatic-shutdown handles personal data. It covers the application behaviour and verified integrations described below. Where the software is self-hosted, the instance operator may have separate responsibilities described below.

## 📑 Table of Contents

- [What This Document Covers](#what-this-document-covers)
- [Self-Hosted Deployments](#self-hosted-deployments)
- [Data We Handle](#data-we-handle)
  - [Data Provided to the Application](#data-provided-to-the-application)
  - [Data Generated or Collected by the Application](#data-generated-or-collected-by-the-application)
  - [Data Received from Integrations](#data-received-from-integrations)
- [Processing and Use](#processing-and-use)
- [Storage, Retention, and Deletion](#storage-retention-and-deletion)
- [External Processing and Integrations](#external-processing-and-integrations)
- [Data Protection and Security](#data-protection-and-security)
- [Document Changes](#document-changes)
- [Contact](#contact)

## 🔎 What This Document Covers

This document describes how argononeup-automatic-shutdown at https://github.com/hmlendea/argononeup-automatic-shutdown handles personal data. It covers the application behaviour and verified integrations described below. Where the software is self-hosted, the instance operator may have separate responsibilities described below.

## 🏠 Self-Hosted Deployments

This project is a self-hosted utility installed and operated by the user on their own machine. The instance operator (the user who installs and runs the software) controls the instance's configuration, local storage, logs, backups, access controls, retention, and request handling. The project maintainers do not operate any instance and do not receive any data from self-hosted deployments.

No data is sent from a self-hosted instance to project maintainers or external services. There is no telemetry, no update checks, no crash reports, no email, no authentication, no reverse-proxy, no object-storage, and no monitoring integrations built into the application.

## 📥 Data We Handle

### Data Provided to the Application

No personal data is requested or provided to the application. The script does not accept user input, configuration files containing personal data, or any form of user-provided information.

### Data Generated or Collected by the Application

The application reads the following system information during its operation:

- **System idle time** — Obtained from GNOME's Mutter IdleMonitor over D-Bus (`org.gnome.Mutter.IdleMonitor`). This is the duration since the last user input event (keyboard, mouse, touch). It does not contain personal identifiers.
- **Lid state** — Read via `gpioget --chip gpiochip0 GPIO27` to determine whether the laptop lid is open or closed. This is a hardware GPIO state.
- **Active SSH sessions** — Determined by parsing the output of the `who` command. This may include usernames of users currently logged in via SSH. This information is used only to decide whether to skip shutdown; it is not logged, stored, or transmitted.
- **Battery charging status** — Read from `/sys/class/power_supply/BAT0/status` to determine if the battery is currently charging. This is a hardware power supply state.

No personal data is generated, collected, logged, or persisted by the application. All checks are performed in memory during each loop iteration and discarded.

### Data Received from Integrations

No personal data is received from integrations or third parties. The application has no built-in integrations with external services.

## 🧭 Processing and Use

The application processes the data described above for these verified functions:

- **Idle threshold evaluation** — Compares system idle time against a threshold (30 minutes when lid is open, 5 minutes when lid is closed) to determine if the machine has been idle long enough.
- **SSH session check** — Checks for active SSH sessions via `who` output; if any are present, shutdown is skipped.
- **Battery charging check** — Reads battery status; if charging, shutdown is skipped. A 5-minute grace period applies after charging stops.
- **Power-off decision** — If all conditions are met (idle threshold exceeded, no SSH sessions, not charging or in grace period), the system is powered off via `systemctl poweroff -i`.

No data is used for any other purpose. No profiling, analytics, advertising, or other processing occurs.

## 🗄️ Storage, Retention, and Deletion

The application does not store any data. All variables exist only in memory during the script's execution and are discarded on each loop iteration or when the service stops. No databases, files, logs, caches, or backups are created by the application.

Systemd journal logs may contain service start/stop messages and any output written to stdout/stderr by the script. These logs are controlled by the instance operator via systemd's journald configuration. The project maintainers do not have access to these logs.

## 🔗 External Processing and Integrations

The application has no built-in external data transfer. It does not communicate with any external services, APIs, or servers. All operations are performed locally using standard Linux utilities (`gdbus`, `gpioget`, `who`, `systemctl`, `sed`, `grep`, `date`, `sleep`).

| Service or integration | Purpose | Data involved | Configuration or documentation |
|-----------------------|---------|---------------|--------------------------------|
| GNOME Mutter IdleMonitor (D-Bus) | Obtain system idle time | Idle time in milliseconds (no personal data) | https://gitlab.gnome.org/GNOME/mutter |
| Linux kernel GPIO subsystem (`gpioget`) | Read lid state from GPIO27 | Hardware GPIO state (open/closed) | https://www.kernel.org/doc/html/latest/driver-api/gpio/ |
| `who` command (util-linux) | List active login sessions | Usernames of logged-in users (used only in-memory) | https://www.kernel.org/pub/linux/utils/util-linux/ |
| Linux kernel power supply subsystem | Read battery status | Battery charging state (Charging/Discharging/Full) | https://www.kernel.org/doc/html/latest/driver-api/power/ |
| systemd (`systemctl`) | Power off the machine | None (triggers system shutdown) | https://systemd.io/ |

## 🛡️ Data Protection and Security

The application performs only local reads of system state and a local power-off action. It does not write to any persistent storage, does not open network ports, does not accept external input, and does not execute untrusted code.

For self-hosted deployments, the instance operator is responsible for:
- Keeping the underlying system and dependencies updated
- Managing systemd journal retention and access controls
- Configuring appropriate file permissions on the installed script and service files
- Ensuring the user session and D-Bus are appropriately secured

The original maintainers are not responsible for changes, modifications, or privacy issues introduced by downstream forks.

## 🔄 Document Changes

Update this document when application data flows, storage, integrations, or deployment responsibilities change. The current version is published at https://github.com/hmlendea/argononeup-automatic-shutdown/blob/master/PRIVACY.md.

## 📬 Contact

For questions about application data handling, contact the project maintainers via GitHub issues at https://github.com/hmlendea/argononeup-automatic-shutdown/issues. For a self-hosted instance, contact the instance operator (yourself), as the project does not operate any instances. Include information about your deployment (distribution, GNOME version, kernel version) if relevant; do not send passwords, access tokens, or other secrets.
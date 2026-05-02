[![Donate](https://img.shields.io/badge/-%E2%99%A5%20Donate-%23ff69b4)](https://hmlendea.go.ro/fund.html)
[![Latest GitHub release](https://img.shields.io/github/v/release/hmlendea/argononeup-automatic-shutdown)](https://github.com/hmlendea/argononeup-automatic-shutdown/releases/latest)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://gnu.org/licenses/gpl-3.0)

# argononeup-automatic-shutdown

Automatically powers off the machine when it has been idle for about 30 minutes **and** there are no active SSH sessions.

This project installs:
- A script at `/usr/local/bin/argononeup-automatic-shutdown`
- A systemd service at `/etc/systemd/system/argononeup-automatic-shutdown.service`

The service is enabled and started immediately on install.

## How it works

The script runs in a loop and:
1. Queries GNOME's idle monitor over D-Bus (`org.gnome.Mutter.IdleMonitor`) to get idle time.
2. Checks for active SSH sessions (`who`).
3. If idle time is over the threshold and no SSH sessions are active, it powers off the machine.

## Requirements

- Linux with `systemd`
- GNOME session (uses Mutter idle monitor over D-Bus)
- `bash`, `gdbus`, `sed`, `grep`, `who`, `sudo`

## Install

From the repository directory:

```bash
chmod +x install uninstall argononeup-automatic-shutdown.sh
./install
```

What `install` does:
- Copies `argononeup-automatic-shutdown.sh` to `/usr/local/bin/argononeup-automatic-shutdown`
- Copies `argononeup-automatic-shutdown.service` to `/etc/systemd/system/`
- Runs `systemctl daemon-reload`
- Enables and starts the service with `systemctl enable --now`

## Uninstall

From the repository directory:

```bash
./uninstall
```

What `uninstall` does:
- Disables and stops the service (if running)
- Removes `/etc/systemd/system/argononeup-automatic-shutdown.service`
- Removes `/usr/local/bin/argononeup-automatic-shutdown`
- Runs `systemctl daemon-reload`

## Verify status

```bash
systemctl status argononeup-automatic-shutdown.service
```

## View logs

```bash
journalctl -u argononeup-automatic-shutdown.service -f
```

## Notes

- The service is installed as a system service and starts at boot.
- SSH session detection is based on `who` output.
- If your desktop environment is not GNOME/Mutter, idle detection in this script may not work.

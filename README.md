[![Donate](https://img.shields.io/badge/-%E2%99%A5%20Donate-%23ff69b4)](https://hmlendea.go.ro/fund.html)
[![Latest GitHub release](https://img.shields.io/github/v/release/hmlendea/argononeup-automatic-shutdown)](https://github.com/hmlendea/argononeup-automatic-shutdown/releases/latest)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://gnu.org/licenses/gpl-3.0)

# argononeup-automatic-shutdown

Automatically powers off the machine when it has been idle for about 30 minutes, there are no active SSH sessions, and the battery is not charging.

This is intended for the **Argon ONE UP CM5** laptop, to help save battery power: the device does not currently support sleep, so it remains continuously on by default.

This project installs:
- A script at `~/.local/bin/argononeup-automatic-shutdown`
- A user systemd service at `~/.config/systemd/user/argononeup-automatic-shutdown.service`

The service is enabled and started immediately on install, and will automatically restart if it exits unexpectedly.

## How it works

The script runs in a loop and:
1. Queries GNOME's idle monitor over D-Bus (`org.gnome.Mutter.IdleMonitor`) to get idle time.
2. Checks for active SSH sessions (`who`).
3. Checks battery charging state from `/sys/class/power_supply/BAT0/status`.
4. If battery status is `Charging`, shutdown is skipped.
5. If charging has just stopped, shutdown is still skipped for up to 5 minutes after the last `Charging` state.
6. If idle time is over the threshold, no SSH sessions are active, and charging/grace conditions are not active, it powers off the machine.

## Requirements

- Linux with `systemd` (user-level systemd service support)
- GNOME session (uses Mutter idle monitor over D-Bus)
- `bash`, `gdbus`, `sed`, `grep`, `who`
- Standard Unix utilities (`install`, `mkdir`)

## Install

From the repository directory:

```bash
chmod +x install uninstall argononeup-automatic-shutdown.sh
./install
```

What `install` does:
- Copies `argononeup-automatic-shutdown.sh` to `~/.local/bin/argononeup-automatic-shutdown` (user-local)
- Copies `argononeup-automatic-shutdown.service` to `~/.config/systemd/user/` (user-level systemd)
- Runs `systemctl --user daemon-reload`
- Enables and starts the service with `systemctl --user enable --now`
- No `sudo` required

## Uninstall

From the repository directory:

```bash
./uninstall
```

What `uninstall` does:
- Disables and stops the service (if running)
- Removes `~/.config/systemd/user/argononeup-automatic-shutdown.service`
- Removes `~/.local/bin/argononeup-automatic-shutdown`
- Runs `systemctl --user daemon-reload`
- No `sudo` required

## Verify status

```bash
systemctl --user status argononeup-automatic-shutdown.service
```

## View logs

```bash
journalctl --user -u argononeup-automatic-shutdown.service -f
```

Or view recent logs:

```bash
journalctl --user -u argononeup-automatic-shutdown.service -n 50
```

## Notes

- The service is a **user-level service** and is tied to the graphical session. It starts when you log in and stops when you log out.
- SSH session detection is based on `who` output.
- If your desktop environment is not GNOME/Mutter, idle detection in this script may not work.
- The service automatically restarts if it crashes, with a 10-second delay between restarts.
- Logs are sent to the systemd journal and can be viewed with `journalctl --user`.


## Contributing

Contributions are welcome.

Please:

- keep the pull requests focused and consistent with the existing style
- update the documentation when the behaviour changes

## License

Licensed under the GNU General Public License v3.0 or later.
See [LICENSE](./LICENSE) for details.
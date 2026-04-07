# RepeaterWatch

> **Credits:**
> [MrAlders0n](https://github.com/MrAlders0n) — original developer of RepeaterWatch and SerialMux
> [sskerry](https://github.com/sskerry) — security hardening (CSRF protection, rate limiting, auth improvements)

A web dashboard for monitoring a MeshCore repeater node running on a Raspberry Pi. Displays radio stats, sensor data (environmental, power, lightning), packet history, and provides a firmware flash interface and serial terminal.

**Full stack:** [RepeaterWatch](https://github.com/MrAlders0n/RepeaterWatch) works alongside [SerialMux](https://github.com/MrAlders0n/SerialMux) (serial port multiplexer) and [mctomqtt](https://github.com/Cisien/meshcoretomqtt) (MeshCore → MQTT bridge). The installer sets up all three.

## Quick Install

On a fresh Raspberry Pi OS (Bookworm or later):

```bash
curl -fsSL https://raw.githubusercontent.com/jjkroell/RepeaterWatch/main/install.sh -o /tmp/rw-install.sh && sudo bash /tmp/rw-install.sh
```

The installer will ask for:

1. **Physical serial port** — the USB by-id path for your MeshCore radio (auto-detected)
2. **Hardware name** — description of your radio hardware (e.g. `Heltec T114`, `Ikoka Stick 30dB`)
3. **Web port** — port for the dashboard (default: `5000`)
4. **Trusted proxy IP** — enter `127.0.0.1` if using a cloudflared tunnel, leave blank for direct LAN access
5. **Login password** — bcrypt-hashed, set interactively

> **Note:** Items 4 and 5 can also be configured (or changed) after installation via the **Settings → Login Protection** and **Settings → Authentication** cards in the web dashboard.

Then it installs and starts everything automatically. The dashboard will be available at `http://<pi-ip>:5000`.

## Uninstall

```bash
sudo bash /opt/RepeaterWatch/uninstall.sh
```

Stops and removes all three services, offers to back up the database, and cleans up users and config files.

## Upgrading

To pull the latest changes from GitHub and restart the service:

```bash
curl -fsSL https://raw.githubusercontent.com/jjkroell/RepeaterWatch/main/upgrade.sh -o /tmp/rw-upgrade.sh && sudo bash /tmp/rw-upgrade.sh
```

Or if already installed:

```bash
sudo bash /opt/RepeaterWatch/upgrade.sh
```

The upgrade script will:
- Pull the latest code from GitHub
- Update Python dependencies
- Add any new `.env` variables with safe defaults
- Restart the service automatically

## Changing the password

```bash
sudo -u meshcoremon /opt/RepeaterWatch/venv/bin/python3 /opt/RepeaterWatch/setup_auth.py
sudo systemctl restart RepeaterWatch
```

To disable login entirely:

```bash
sudo -u meshcoremon /opt/RepeaterWatch/venv/bin/python3 /opt/RepeaterWatch/setup_auth.py --clear
sudo systemctl restart RepeaterWatch
```

## Useful commands

```bash
sudo systemctl status RepeaterWatch
sudo systemctl status mctomqtt
sudo systemctl status SerialMux

sudo journalctl -u RepeaterWatch -f
sudo journalctl -u mctomqtt -f
sudo journalctl -u SerialMux -f
```

## Configuration reference

All RepeaterWatch configuration is in `/opt/RepeaterWatch/.env`. The installer writes this automatically — edit it to make changes, then restart the service.

| Variable | Default | Description |
|---|---|---|
| `MESHCORE_SERIAL_PORT` | `/dev/ttyV0` | MeshCore radio serial port (via SerialMux) |
| `MESHCORE_SERIAL_BAUD` | `115200` | Serial baud rate |
| `MESHCORE_POLL_INTERVAL` | `300` | Polling interval in seconds |
| `MESHCORE_DB_PATH` | `meshcore.db` | SQLite database path |
| `MESHCORE_RETENTION_DAYS` | `30` | Days of data to retain |
| `MESHCORE_HOST` | `0.0.0.0` | Flask bind address |
| `MESHCORE_PORT` | `5000` | Flask port |
| `MESHCORE_SECRET_KEY` | — | Flask session secret (auto-generated on install) |
| `MESHCORE_PASSWORD_HASH` | — | bcrypt hash — set via `setup_auth.py` |
| `MESHCORE_LOGIN_MAX_ATTEMPTS` | `5` | Failed login attempts before lockout |
| `MESHCORE_LOGIN_LOCKOUT_SECS` | `300` | Lockout duration in seconds |
| `MESHCORE_TRUSTED_PROXIES` | — | Comma-separated private/localhost IPs of trusted reverse proxies (e.g. `127.0.0.1` for cloudflared) |
| `MESHCORE_FLASH_SERIAL_PORT` | — | Physical serial port for firmware flashing |
| `MESHCORE_FIRMWARE_UPLOAD_DIR` | `/tmp/meshcore-fw` | Temp dir for firmware uploads |
| `MESHCORE_TERMINAL_SERIAL_PORT` | `/dev/ttyV2` | Serial port for terminal (via SerialMux) |
| `MESHCORE_RADIO_RESET_GPIO` | `4` | GPIO pin for radio reset |
| `MESHCORE_USB_RELAY_GPIO` | `17` | GPIO pin for USB relay |
| `MESHCORE_SENSOR_POLL` | `1` | Enable sensor polling (`0` to disable) |
| `MESHCORE_AS3935_IRQ_GPIO` | `18` | GPIO pin for AS3935 lightning sensor IRQ |
| `MESHCORE_AS3935_AFE_MODE` | `indoor` | AS3935 mode (`indoor` or `outdoor`) |
| `MESHCORE_AS3935_NOISE_FLOOR` | `3` | AS3935 noise floor (0–7) |
| `MESHCORE_AS3935_MASK_DIST` | `1` | Mask AS3935 disturber events (`0` to show) |
| `MESHCORE_BQ24074_CHG_GPIO` | `19` | GPIO for BQ24074 charge status |
| `MESHCORE_BQ24074_PGOOD_GPIO` | `13` | GPIO for BQ24074 power good |
| `MESHCORE_BQ24074_CE_GPIO` | `6` | GPIO for BQ24074 charge enable |

mctomqtt configuration is in `/etc/mctomqtt/config.d/00-user.toml`. Edit that file and run `sudo systemctl restart mctomqtt` to apply changes.

SerialMux configuration (physical serial port and baud rate) is at the top of `/opt/SerialMux/SerialMux.py`. Edit and run `sudo systemctl restart SerialMux` to apply.

## Security

RepeaterWatch is designed for trusted LAN use by default. If you expose it to the internet (e.g. via a cloudflared tunnel), set a strong password and configure the following:

- **Set a password** — run `setup_auth.py` or use the Admin tab in the dashboard
- **Set `MESHCORE_TRUSTED_PROXIES=127.0.0.1`** — required for correct client IP detection behind cloudflared
- **CSRF protection** is enabled automatically once a password is set
- **Rate limiting** — 5 failed login attempts triggers a 5-minute lockout (configurable via env vars above)
- **Session cookies** are set `HttpOnly` and `SameSite=Strict`; `Secure` is set automatically when a trusted proxy is configured

Access model:
- **No password set:** full access to everything (trusted LAN mode — a warning badge is shown in the dashboard)
- **Password set, not logged in:** read-only access (can view dashboards, cannot access terminal, reboot, flash, GPIO, or settings)
- **Password set, logged in:** full access

## Manual installation

If you prefer to install components individually, see the steps below.

<details>
<summary>Manual install steps</summary>

### SerialMux

```bash
git clone https://github.com/MrAlders0n/SerialMux.git /opt/SerialMux
sudo apt install python3-serial
```

Edit `REAL_PORT` at the top of `/opt/SerialMux/SerialMux.py` to match your USB serial device, then create `/etc/systemd/system/SerialMux.service`:

```ini
[Unit]
Description=SerialMux - Python Serial Port Multiplexer
After=local-fs.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /opt/SerialMux/SerialMux.py
Restart=on-failure
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl enable --now SerialMux
```

### mctomqtt

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Cisien/meshcoretomqtt/main/install.sh)
```

Write your settings to `/etc/mctomqtt/config.d/00-user.toml` (see `.env.example` for structure), then add a systemd override to wait for SerialMux:

```bash
sudo mkdir -p /etc/systemd/system/mctomqtt.service.d
sudo tee /etc/systemd/system/mctomqtt.service.d/override.conf <<'EOF'
[Service]
ExecStartPre=
ExecStartPre=/bin/bash -c 'for i in $(seq 30); do [ -e /dev/ttyV1 ] && exit 0; sleep 1; done; exit 1'
Restart=on-failure
RestartSec=15

# RepeaterWatch

A real-time web dashboard for monitoring a [MeshCore](https://meshcore.co.uk) LoRa repeater node running on a Raspberry Pi. Polls the node over serial, stores history in SQLite, and presents live data through a Flask/WebSocket interface.

**Full stack:** SerialMux → mctomqtt → RepeaterWatch — **fully installed via the one-line installer below**

---

## Requirements

- Raspberry Pi (any model with USB)
- MeshCore LoRa node connected via USB serial
- Raspberry Pi OS (Bookworm recommended)
- Internet access for the installer (pulls packages and clones repos)

---

## Installation

Run the one-line installer as root. It will guide you through configuration interactively:

```bash
sudo bash <(curl -fsSL https://raw.githubusercontent.com/jjkroell/RepeaterWatch/main/install.sh)
```

The installer will ask for:
1. **Serial port** — auto-detected from `/dev/serial/by-id/`; manual entry if multiple devices found
2. **Hardware name** — description of the radio hardware (e.g. `Heltec T114`, `RAK 4631`)
3. **Web port** — port the dashboard listens on (default: `5000`)
4. **Trusted proxy IP** — leave blank unless behind a reverse proxy (e.g. cloudflared: `127.0.0.1`)
5. **ntfy.sh URL** — optional push notification topic URL for offline alerts

It then installs and configures the full stack automatically:

| Step | What happens |
|---|---|
| 1 | Installs system packages (`git`, `python3`, `python3-venv`, etc.) |
| 2 | Clones and starts **SerialMux** — multiplexes the physical serial port into three virtual ports (`/dev/ttyV0`, `ttyV1`, `ttyV2`) |
| 3 | Runs the **mctomqtt** installer — bridges the node to LetsMesh MQTT; prompts for your IATA code and LetsMesh credentials |
| 4 | Clones **RepeaterWatch**, creates the `meshcoremon` service user, writes `.env`, prompts for a dashboard password, and starts the service |

Once complete, the dashboard is available at `http://<pi-ip>:<port>`.

---

## Upgrading

Pull the latest code and restart in one step:

```bash
cd /opt/RepeaterWatch && sudo bash upgrade.sh
```

The upgrade script pulls from `main`, migrates the `.env` if new variables were added, reinstalls Python dependencies, and restarts the service.

---

## Dashboard Overview

### Tabs

#### MeshCore
Live node stats: device info, GPS coordinates, radio metrics (SNR, RSSI, airtime), power levels, packet counters, and channel activity charts. Time window selectable from 1 h to 7 days.

#### Raspberry Pi
Host system health: CPU temperature and load, memory and disk usage, plotted over time.

#### Sensors
Connected I²C/GPIO sensors (temperature, humidity, pressure, etc.) with time-series charts and a sensor management panel for adding or removing entries.

#### Neighbours
All nodes heard by the repeater:
- **Map** — Leaflet map showing neighbour positions relative to the repeater. Click the map to pan/zoom; click again to lock.
- **Table** — Neighbour list with last-seen time, distance, SNR, RSSI, and packet counts.
- **SNR History / RSSI History** — Time-series charts showing per-neighbour signal trends over the selected period. Each neighbour gets a consistent color derived from its public key. Hover a data point for a tooltip; **click** to open a detail modal with the exact values at that moment plus min/avg/max statistics over the loaded period.

Time window is selectable independently from other tabs (1 h / 6 h / 24 h / 7 d).

#### Tools
- **Repeater CLI** — Browser-based serial terminal for direct interaction with the MeshCore node. Supports command history (↑/↓). The stats poller pauses automatically on connect and resumes on disconnect. Sessions time out after 90 seconds of inactivity.
- **Firmware Update** — OTA firmware flash via the MeshCore bootloader.
- **Settings** — Manage stored neighbours, sensor config, and service control.

---

## Configuration

All settings live in `/opt/RepeaterWatch/.env`. The installer writes this file during setup — do not edit `MESHCORE_PASSWORD_HASH` manually; use `setup_auth.py` instead.

| Variable | Default | Description |
|---|---|---|
| `MESHCORE_SERIAL_PORT` | `/dev/ttyV0` | Virtual serial port (SerialMux) for polling |
| `MESHCORE_TERMINAL_SERIAL_PORT` | `/dev/ttyV2` | Virtual serial port for the CLI terminal |
| `MESHCORE_FLASH_SERIAL_PORT` | *(physical port)* | Physical serial port used for firmware flashing |
| `MESHCORE_POLL_INTERVAL` | `300` | Node poll interval in seconds |
| `MESHCORE_PORT` | `5000` | Dashboard web port |
| `MESHCORE_TRUSTED_PROXIES` | *(empty)* | Trusted reverse proxy IP (e.g. `127.0.0.1` for cloudflared) |
| `MESHCORE_RETENTION_DAYS` | `30` | Days of history to keep in the database |
| `MESHCORE_NTFY_URL` | *(empty)* | ntfy.sh topic URL for offline alerts — leave blank to disable |
| `MESHCORE_NTFY_USER` | *(empty)* | ntfy username (self-hosted only) |
| `MESHCORE_NTFY_PASSWORD` | *(empty)* | ntfy password (self-hosted only) |
| `MESHCORE_NTFY_OFFLINE_THRESHOLD` | `3` | Consecutive failed polls before an offline alert fires |
| `MESHCORE_HARDWARE` | *(set at install)* | Hardware description shown in the dashboard |

After editing `.env`, restart the service:

```bash
sudo systemctl restart RepeaterWatch
```

---

## Password Management

To set or change the dashboard password:

```bash
sudo -u meshcoremon /opt/RepeaterWatch/venv/bin/python3 /opt/RepeaterWatch/setup_auth.py
```

To disable password protection:

```bash
sudo -u meshcoremon /opt/RepeaterWatch/venv/bin/python3 /opt/RepeaterWatch/setup_auth.py --clear
```

---

## Notifications (ntfy.sh)

RepeaterWatch can send push notifications when the node goes offline or recovers. It uses [ntfy.sh](https://ntfy.sh) — a simple pub/sub notification service with free apps for iOS and Android.

### Using the public ntfy.sh server

No account or password needed. Just pick a unique topic name and set it in `.env`:

```
MESHCORE_NTFY_URL=https://ntfy.sh/<your-topic-here>
MESHCORE_NTFY_OFFLINE_THRESHOLD=3
```

Subscribe to the same topic in the ntfy app on your phone. For the public server leave `MESHCORE_NTFY_USER` and `MESHCORE_NTFY_PASSWORD` blank.

### Using a self-hosted ntfy server

Install ntfy on the same Pi:

```bash
wget https://github.com/binwiederhier/ntfy/releases/download/v2.23.0/ntfy_2.23.0_linux_arm64.tar.gz
tar zxf ntfy_2.23.0_linux_arm64.tar.gz
sudo cp ntfy_2.23.0_linux_arm64/ntfy /usr/bin/
sudo mkdir -p /etc/ntfy /var/lib/ntfy
sudo cp ntfy_2.23.0_linux_arm64/server/server.yml /etc/ntfy/
sudo useradd --system --home-dir /var/lib/ntfy --shell /bin/false ntfy
sudo cp ntfy_2.23.0_linux_arm64/server/ntfy.service /etc/systemd/system/
```

Minimal `/etc/ntfy/server.yml`:

```yaml
listen-http: "0.0.0.0:8080"
auth-file: "/var/lib/ntfy/user.db"
auth-default-access: "deny-all"
cache-file: "/var/lib/ntfy/cache.db"
```

Create a user and start the service:

```bash
sudo systemctl daemon-reload && sudo systemctl enable --now ntfy
sudo ntfy user add --role=admin <your-username>
```

Then set in `/opt/RepeaterWatch/.env`:

```
MESHCORE_NTFY_URL=http://localhost:8080/<your-topic-here>
MESHCORE_NTFY_USER=<your-username>
MESHCORE_NTFY_PASSWORD=<your-password>
MESHCORE_NTFY_OFFLINE_THRESHOLD=3
```

---

## Node Swap

When swapping the physical MeshCore radio node, run the node swap script to update the serial port, hardware description, and clear cached device info:

```bash
sudo python3 /opt/RepeaterWatch/setup_node.py
```

The script will:
1. Show available serial ports and let you select the new one
2. Prompt for an updated hardware description
3. Clear the cached device name, public key, firmware, and GPS from the database
4. Restart SerialMux with the new port
5. Restart RepeaterWatch to re-query the new node

The dashboard should populate with the new node info within 10 seconds of restart.

---

## Repeater CLI

The Tools tab includes a browser-based serial CLI for direct interaction with the MeshCore node. When connected, the stats poller automatically pauses so its background commands don't appear in the terminal output. The poller resumes when you disconnect.

---

## Sudoers Configuration

The firmware flash feature requires the `meshcoremon` service user to stop and start `SerialMux` and `mctomqtt` via `systemctl`. Add a sudoers drop-in file so these specific commands run without a password prompt:

```bash
sudo visudo -f /etc/sudoers.d/meshcoremon
```

Contents:

```
meshcoremon ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop SerialMux, /usr/bin/systemctl stop mctomqtt, /usr/bin/systemctl start SerialMux, /usr/bin/systemctl start mctomqtt, /usr/bin/systemctl restart RepeaterWatch, /usr/bin/systemctl reboot
```

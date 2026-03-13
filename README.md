# RepeaterWatch — Community Contributions

Enhancements to [RepeaterWatch](https://github.com/MrAlders0n/RepeaterWatch) developed and tested on a Raspberry Pi 4 running Raspberry Pi OS Bookworm. These changes add bcrypt authentication, a responsive dark-mode dashboard UI, dynamic sensor management, and a one-command installer for the full SerialMux → mctomqtt → RepeaterWatch stack.

---

## What's Included

| File | Description |
|------|-------------|
| `install.sh` | One-command installer for the full stack |
| `uninstall.sh` | Clean uninstaller (`--purge` to remove data too) |
| `app.py` | Bcrypt login, logout route, auth guard |
| `setup_auth.py` | Interactive password setup (bcrypt) |
| `api/routes.py` | All API routes including sensor config endpoints |
| `patch_sensors.py` | Adds sensor config routes to an existing install |
| `static/css/dashboard.css` | Responsive dark/light theme (DM Sans + JetBrains Mono) |
| `static/js/sensors_manage.js` | Sensor config modal + dynamic section visibility |
| `templates/index.html` | Full dashboard template with dynamic Sensors tab |
| `.env.example` | All supported environment variables |

---

## Quick Install (fresh Pi)

```bash
git clone https://github.com/YOUR_USERNAME/RepeaterWatch-contrib.git
cd RepeaterWatch-contrib
chmod +x install.sh
sudo ./install.sh
```

Then set a password:

```bash
sudo -u meshcoremon /opt/RepeaterWatch/venv/bin/python3 /opt/RepeaterWatch/setup_auth.py
```

Dashboard is available at `http://<pi-ip>:5000`

---

## Serial Port Architecture

This stack uses [SerialMux](https://github.com/MrAlders0n/SerialMux) to multiplex one physical USB serial port (the Ikoka/XIAO nRF52840 stick) across three virtual PTY ports:

| Virtual Port | Consumer | Purpose |
|---|---|---|
| `/dev/ttyV0` | RepeaterWatch | Main data polling (`MESHCORE_SERIAL_PORT`) |
| `/dev/ttyV1` | mctomqtt | LetsMesh / MQTT cloud relay |
| `/dev/ttyV2` | RepeaterWatch | Web terminal (`MESHCORE_TERMINAL_SERIAL_PORT`) |

The physical device is auto-detected at install time from `/dev/serial/by-id/`.

> **Important:** Service names are case-sensitive. The RepeaterWatch systemd unit **must** be named `RepeaterWatch.service` (capital R and W) — this exact string is referenced in `api/routes.py`.

---

## Authentication

Authentication uses bcrypt hashing. Set a password interactively:

```bash
sudo -u meshcoremon /opt/RepeaterWatch/venv/bin/python3 /opt/RepeaterWatch/setup_auth.py
```

This writes `MESHCORE_PASSWORD_HASH` to `.env` and clears any plaintext `MESHCORE_PASSWORD`.

To disable authentication, clear both `MESHCORE_PASSWORD_HASH` and `MESHCORE_PASSWORD` in `.env` and restart the service.

---

## Applying to an Existing Install

If RepeaterWatch is already installed, copy the modified files individually:

```bash
# Backend
sudo cp app.py        /opt/RepeaterWatch/app.py
sudo cp api/routes.py /opt/RepeaterWatch/api/routes.py
sudo cp setup_auth.py /opt/RepeaterWatch/setup_auth.py

# Or use patch_sensors.py to add only the sensor API routes
sudo python3 patch_sensors.py

# Frontend
sudo cp static/css/dashboard.css     /opt/RepeaterWatch/static/css/dashboard.css
sudo cp static/js/sensors_manage.js  /opt/RepeaterWatch/static/js/sensors_manage.js
sudo cp templates/index.html         /opt/RepeaterWatch/templates/index.html

# Fix ownership
sudo chown -R meshcoremon:meshcoremon \
    /opt/RepeaterWatch/app.py \
    /opt/RepeaterWatch/api/routes.py \
    /opt/RepeaterWatch/setup_auth.py \
    /opt/RepeaterWatch/static/css/dashboard.css \
    /opt/RepeaterWatch/static/js/sensors_manage.js \
    /opt/RepeaterWatch/templates/index.html

# Install bcrypt
sudo /opt/RepeaterWatch/venv/bin/pip install bcrypt

sudo systemctl restart RepeaterWatch
```

---

## Sensor Management

The Sensors tab is fully dynamic — it only shows sections for sensors that are enabled in `.env`. Use the **Manage Sensors** modal in the dashboard to toggle sensors on and off without editing files manually.

### Supported sensors

| Sensor | Variable | Capability |
|---|---|---|
| INA3221 | `MESHCORE_SENSOR_INA3221` | 3-channel voltage / current / power |
| BME280 | `MESHCORE_SENSOR_BME280` | Temperature, humidity, pressure |
| LIS2DW12 | `MESHCORE_SENSOR_LIS2DW12` | Accelerometer / vibration |
| AS3935 | `MESHCORE_SENSOR_AS3935` | Lightning strike detector |
| BQ24074 | `MESHCORE_SENSOR_BQ24074` | Solar charger status |

`MESHCORE_SENSOR_POLL` is managed automatically — it is set to `1` when any sensor is enabled, and `0` when all are disabled.

A service restart is required after changing sensor configuration for polling to take effect.

---

## Sudoers

The `meshcoremon` service user needs permission to control services and reboot the Pi. The installer creates `/etc/sudoers.d/meshcoremon` automatically. To add it manually:

```bash
sudo visudo -f /etc/sudoers.d/meshcoremon
```

Contents:

```
meshcoremon ALL=(ALL) NOPASSWD: \
    /usr/bin/systemctl stop SerialMux, \
    /usr/bin/systemctl start SerialMux, \
    /usr/bin/systemctl stop mctomqtt, \
    /usr/bin/systemctl start mctomqtt, \
    /usr/bin/systemctl restart SerialMux, \
    /usr/bin/systemctl restart mctomqtt, \
    /usr/bin/systemctl restart RepeaterWatch, \
    /usr/bin/systemctl reboot
```

---

## mctomqtt Startup Delay

mctomqtt starts before SerialMux has fully initialized the virtual ports on first boot. The systemd unit includes `ExecStartPre=/bin/sleep 10` to work around this. If mctomqtt still fails on boot, increase the delay:

```bash
sudo systemctl edit mctomqtt
```

```ini
[Service]
ExecStartPre=/bin/sleep 15
```

---

## Environment Variables

See [`.env.example`](.env.example) for a full reference. Key variables:

```env
MESHCORE_PASSWORD_HASH=        # bcrypt hash — set via setup_auth.py
MESHCORE_SECRET_KEY=           # Flask session key — auto-generated at install
MESHCORE_SERIAL_PORT=/dev/ttyV0
MESHCORE_TERMINAL_SERIAL_PORT=/dev/ttyV2
MESHCORE_FLASH_SERIAL_PORT=/dev/serial/by-id/usb-...
MESHCORE_SENSOR_BME280=1       # Enable BME280
MESHCORE_SENSOR_POLL=1         # Auto-managed
```

---

## Uninstall

```bash
# Safe — preserves database and .env
sudo ./uninstall.sh

# Full purge — removes everything
sudo ./uninstall.sh --purge
```

---

## Tested On

- Raspberry Pi 4 Model B (4 GB)
- Raspberry Pi OS Bookworm (64-bit), March 2025
- Ikoka repeater with Seeed Studio XIAO nRF52840 USB stick
- Python 3.11, Flask 3.x, bcrypt 4.x

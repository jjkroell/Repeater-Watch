#!/usr/bin/env python3
"""
patch_sensors.py — Adds GET/POST /api/v1/sensors/config to routes.py.

Run once after installing RepeaterWatch:
    sudo python3 /opt/RepeaterWatch/patch_sensors.py

The patch inserts two Flask routes that read/write sensor enable flags
(MESHCORE_SENSOR_*) in the .env file, and auto-sets MESHCORE_SENSOR_POLL.

Safe to re-run — it checks if the routes already exist before patching.
"""

import os
import sys

ROUTES_PATH = os.path.join(os.path.dirname(__file__), "api", "routes.py")

PATCH_MARKER = "sensors_config_get"

PATCH_CODE = '''

@api.route("/sensors/config", methods=["GET"])
def sensors_config_get():
    """Return enabled/disabled state of each sensor from .env"""
    import os as _os
    env_path = _os.path.join(_os.path.dirname(_os.path.dirname(__file__)), ".env")
    keys = {
        "ina3221":  "MESHCORE_SENSOR_INA3221",
        "bme280":   "MESHCORE_SENSOR_BME280",
        "lis2dw12": "MESHCORE_SENSOR_LIS2DW12",
        "as3935":   "MESHCORE_SENSOR_AS3935",
        "bq24074":  "MESHCORE_SENSOR_BQ24074",
    }
    env_vals = {}
    if _os.path.exists(env_path):
        for line in open(env_path):
            s = line.strip()
            if "=" in s and not s.startswith("#"):
                k, _, v = s.partition("=")
                env_vals[k.strip()] = v.strip()
    cfg = {}
    for name, key in keys.items():
        cfg[name] = env_vals.get(key, _os.environ.get(key, "0")) == "1"
    poll = env_vals.get("MESHCORE_SENSOR_POLL",
                        _os.environ.get("MESHCORE_SENSOR_POLL", "0")) == "1"
    return jsonify({"sensors": cfg, "polling_enabled": poll})


@api.route("/sensors/config", methods=["POST"])
def sensors_config_post():
    """Write sensor toggles to .env, auto-update MESHCORE_SENSOR_POLL"""
    import os as _os
    env_path = _os.path.join(_os.path.dirname(_os.path.dirname(__file__)), ".env")
    keys = {
        "ina3221":  "MESHCORE_SENSOR_INA3221",
        "bme280":   "MESHCORE_SENSOR_BME280",
        "lis2dw12": "MESHCORE_SENSOR_LIS2DW12",
        "as3935":   "MESHCORE_SENSOR_AS3935",
        "bq24074":  "MESHCORE_SENSOR_BQ24074",
    }
    if not _os.path.exists(env_path):
        return jsonify({"error": ".env not found"}), 500
    data = request.get_json(force=True, silent=True) or {}
    sensors = data.get("sensors", {})
    for name in sensors:
        if name not in keys:
            return jsonify({"error": f"Unknown sensor: {name}"}), 400
    lines = open(env_path).readlines()

    def upsert(lines, key, value):
        found = False
        out = []
        for l in lines:
            if l.startswith(key + "="):
                out.append(f"{key}={value}\\n")
                found = True
            else:
                out.append(l)
        if not found:
            out.append(f"{key}={value}\\n")
        return out

    for name, key in keys.items():
        if name in sensors:
            lines = upsert(lines, key, "1" if sensors[name] else "0")

    env_vals = {}
    for l in lines:
        s = l.strip()
        if "=" in s and not s.startswith("#"):
            k, _, v = s.partition("=")
            env_vals[k.strip()] = v.strip()
    any_enabled = any(env_vals.get(v, "0") == "1" for v in keys.values())
    lines = upsert(lines, "MESHCORE_SENSOR_POLL", "1" if any_enabled else "0")
    open(env_path, "w").writelines(lines)
    return jsonify({"ok": True, "polling_enabled": any_enabled, "restart_required": True})


@api.route("/sensors/status")
def sensors_status():
    sp = current_app.config.get("sensor_poller")
    if sp:
        return jsonify(sp.status)
    return jsonify({"running": False, "sensors": {}})
'''


def main():
    if not os.path.exists(ROUTES_PATH):
        print(f"ERROR: routes.py not found at {ROUTES_PATH}")
        sys.exit(1)

    with open(ROUTES_PATH) as f:
        content = f.read()

    if PATCH_MARKER in content:
        print("Sensor config routes already present — nothing to do.")
        sys.exit(0)

    # Append before the last route or at end of file
    with open(ROUTES_PATH, "a") as f:
        f.write(PATCH_CODE)

    print("Sensor config routes added to routes.py.")
    print("Restart RepeaterWatch to activate:")
    print("  sudo systemctl restart RepeaterWatch")


if __name__ == "__main__":
    main()

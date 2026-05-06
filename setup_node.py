#!/usr/bin/env python3
"""setup_node.py — Update hardware description and serial port for a node swap
Usage:
    sudo python3 /opt/RepeaterWatch/setup_node.py
"""
import os, sys, glob, subprocess

ENV_PATH = os.path.join(os.path.dirname(__file__), ".env")
SERIALMUX_PATH = "/opt/SerialMux/SerialMux.py"

def upsert_env(lines, key, value):
    found = False; out = []
    for l in lines:
        if l.startswith(f"{key}="):
            out.append(f"{key}={value}\n"); found = True
        else:
            out.append(l)
    if not found: out.append(f"{key}={value}\n")
    return out

def get_current_port():
    try:
        with open(SERIALMUX_PATH) as f:
            for line in f:
                if line.strip().startswith("REAL_PORT"):
                    return line.split("=",1)[1].strip().strip("'\"")
    except:
        pass
    return None

def list_serial_ports():
    ports = glob.glob("/dev/serial/by-id/*")
    return ports

def main():
    if os.geteuid() != 0:
        print("[ERROR] Run as root: sudo python3 setup_node.py")
        sys.exit(1)

    print("")
    print("═══════════════════════════════════════")
    print("  RepeaterWatch — Node Swap Setup")
    print("═══════════════════════════════════════")
    print("")

    # ── Serial port ──────────────────────────────
    current_port = get_current_port()
    print(f"Current serial port: {current_port or '(unknown)'}")
    print("")
    ports = list_serial_ports()
    if ports:
        print("Available ports:")
        for i, p in enumerate(ports, 1):
            marker = " ← current" if p == current_port else ""
            print(f"  {i}) {p}{marker}")
        print("")
        selection = input(f"Select port number or paste path (blank to keep current): ").strip()
        if selection:
            if selection.isdigit() and 1 <= int(selection) <= len(ports):
                new_port = ports[int(selection) - 1]
            else:
                new_port = selection
        else:
            new_port = current_port
    else:
        print("No ports found.")
        new_port = input("Enter serial port path (blank to keep current): ").strip() or current_port
    print("")

    # ── Hardware description ──────────────────────
    lines = open(ENV_PATH).readlines()
    kv = {l.split("=",1)[0].strip(): l.split("=",1)[1].strip() for l in lines if "=" in l and not l.startswith("#")}
    current_hw = kv.get("MESHCORE_HARDWARE", "")
    print(f"Current hardware: {current_hw or '(not set)'}")
    print("Examples: Ikoka Stick 30dBm, RAK4631, Heltec V3, Station G2, Wio Tracker L1")
    new_hw = input("New hardware description (blank to keep current): ").strip() or current_hw
    print("")

    # ── Confirm ───────────────────────────────────
    print("Summary:")
    print(f"  Serial port: {new_port}")
    print(f"  Hardware:    {new_hw}")
    print("")
    confirm = input("Apply changes? [Y/n]: ").strip()
    if confirm.lower() == "n":
        print("Cancelled.")
        return

    # ── Apply SerialMux port ──────────────────────
    if new_port and new_port != current_port:
        with open(SERIALMUX_PATH) as f:
            content = f.read()
        import re
        content = re.sub(r"REAL_PORT = '.*'", f"REAL_PORT = '{new_port}'", content)
        with open(SERIALMUX_PATH, "w") as f:
            f.write(content)
        print(f"[OK] SerialMux port updated to: {new_port}")

    # ── Apply hardware description ────────────────
    if new_hw != current_hw:
        lines = upsert_env(lines, "MESHCORE_HARDWARE", new_hw)
        open(ENV_PATH, "w").writelines(lines)
        print(f"[OK] Hardware updated to: {new_hw}")

    # ── Clear cached device info ──────────────────
    print("[INFO] Clearing cached device info...")
    try:
        import sqlite3
        db_path = kv.get("MESHCORE_DB_PATH", "/opt/RepeaterWatch/meshcore.db")
        conn = sqlite3.connect(db_path)
        conn.execute("DELETE FROM device_info")
        conn.commit()
        conn.close()
        print("[OK] Device info cleared")
    except Exception as e:
        print(f"[WARN] Could not clear device info: {e}")

    # ── Restart services ──────────────────────────
    print("[INFO] Restarting services...")
    subprocess.run(["systemctl", "restart", "SerialMux"])
    import time; time.sleep(3)
    subprocess.run(["systemctl", "restart", "RepeaterWatch"])
    print("[OK] Services restarted")
    print("")
    print("Done — new node should populate within 10 seconds.")
    print("")

if __name__ == "__main__":
    main()

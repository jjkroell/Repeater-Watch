# RepeaterWatch

## Sudoers Configuration

The firmware flash feature requires the `meshcoremon` service user to stop and start `SerialMux` and `mctomqtt` via `systemctl`. Add a sudoers drop-in file so these specific commands run without a password prompt:

```bash
sudo visudo -f /etc/sudoers.d/meshcoremon
```

Contents:

```
meshcoremon ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop SerialMux, /usr/bin/systemctl stop mctomqtt, /usr/bin/systemctl start SerialMux, /usr/bin/systemctl start mctomqtt, /usr/bin/systemctl restart RepeaterWatch, /usr/bin/systemctl reboot
```

---

## Node Swap

When swapping the physical MeshCore radio node, run the node swap script to update the serial port, hardware description, clear cached device info, and restart services automatically:

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

## Password Management

To set or change the dashboard password:

```bash
sudo -u meshcoremon /opt/RepeaterWatch/venv/bin/python3 /opt/RepeaterWatch/setup_auth.py
```

To disable password protection:

```bash
sudo -u meshcoremon /opt/RepeaterWatch/venv/bin/python3 /opt/RepeaterWatch/setup_auth.py --clear
```

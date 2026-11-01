#!/usr/bin/env python3
"""
414Unlock Android - nPhoneKIT 1.6.8 Integration Adapter
======================================================
Headless, real-time backend adapter for 414Unlock Android.
Provides structured JSON-lines IPC over stdout/stdin/stderr.

Safety Boundary:
- NO FRP bypass
- NO activation lock bypass
- NO credential/passcode extraction
- Strictly legitimate device detection, state assessment, diagnostics,
  reboot, recovery, fastboot, and authorized device recovery operations.
"""

import sys
import os
import json
import time
import re
import subprocess
import shutil
import argparse
import threading
from typing import Dict, Any, Optional, List

# Ensure unbuffered standard streams for immediate IPC responsiveness
sys.stdout.reconfigure(line_buffering=True)
sys.stderr.reconfigure(line_buffering=True)

# Attempt imports of optional dependencies
try:
    import serial
    import serial.tools.list_ports as list_ports
    HAS_PYSERIAL = True
except ImportError:
    HAS_PYSERIAL = False


def emit_event(event_type: str, message: str, **kwargs):
    """Emit a structured JSON event to stdout."""
    payload = {
        "event": event_type,
        "message": message,
        "timestamp": time.strftime("%H:%M:%S"),
        **kwargs
    }
    sys.stdout.write(json.dumps(payload) + "\n")
    sys.stdout.flush()


def emit_log(level: str, message: str, details: Optional[str] = None):
    emit_event("log", message, level=level, details=details)


def emit_error(error_type: str, message: str, details: Optional[str] = None):
    emit_event("error", message, errorType=error_type, details=details)


class WindowsSerialManager:
    """Safe headless COM port manager based on nPhoneKIT 1.6.8 logic."""
    def __init__(self, port: Optional[str] = None, baud: int = 115200):
        self.port = port or self.detect_port()
        self.baud = baud
        self.ser = None
        if self.port and HAS_PYSERIAL:
            try:
                self.ser = serial.Serial(self.port, self.baud, timeout=2)
                time.sleep(0.3)
            except Exception as e:
                self.ser = None

    def detect_port(self) -> Optional[str]:
        if not HAS_PYSERIAL:
            return None
        try:
            ports = list_ports.comports()
            # Sort ports to prioritize ones likely to be phones (SAMSUNG, MOBILE, MODEM, USB)
            sorted_ports = sorted(
                ports,
                key=lambda p: (
                    "SAMSUNG" in (p.description or "").upper() or
                    "MOBILE" in (p.description or "").upper() or
                    "MODEM" in (p.description or "").upper() or
                    "USB" in (p.description or "").upper()
                ),
                reverse=True
            )
            for p in sorted_ports:
                if p.device.upper().startswith("COM"):
                    try:
                        test_ser = serial.Serial(p.device, timeout=1)
                        test_ser.close()
                        return p.device
                    except Exception:
                        continue
        except Exception:
            pass
        return None

    def send(self, command: str, wait: float = 0.2) -> str:
        if not self.ser or not self.ser.is_open:
            raise RuntimeError("Serial COM port not open")
        self.ser.reset_input_buffer()
        self.ser.reset_output_buffer()
        self.ser.write((command.strip() + "\r\n").encode())
        time.sleep(wait)
        lines = []
        while True:
            line = self.ser.readline()
            if not line:
                break
            lines.append(line.decode(errors="ignore").strip())
        return "\n".join(lines)

    def close(self):
        if self.ser and self.ser.is_open:
            try:
                self.ser.close()
            except Exception:
                pass


def parse_devconinfo(raw_input: str) -> Dict[str, str]:
    """Parse AT+DEVCONINFO output into structured key-values."""
    parsed = {}
    for line in raw_input.strip().splitlines():
        if "+DEVCONINFO:" in line:
            content = line.split(":", 1)[1].strip()
            items = content.split(";")
            for item in items:
                match = re.match(r'(\w+)\((.*?)\)', item)
                if match:
                    k, v = match.groups()
                    key_map = {
                        "MN": "model",
                        "BASE": "baseband",
                        "VER": "softwareVersion",
                        "HIDVER": "hiddenVersion",
                        "PRD": "productCode",
                        "SN": "serialNumber",
                        "UN": "uniqueNumber",
                        "CON": "connectionTypes",
                        "LOCK": "simLock",
                    }
                    if k in key_map:
                        parsed[key_map[k]] = v
    return parsed


def query_adb_devices() -> List[Dict[str, str]]:
    """Query ADB attached devices and detailed attributes."""
    adb = shutil.which("adb") or "adb"
    devices = []
    try:
        proc = subprocess.run([adb, "devices", "-l"], capture_output=True, text=True, timeout=4)
        if proc.returncode == 0:
            lines = proc.stdout.splitlines()[1:]
            for line in lines:
                line = line.strip()
                if not line:
                    continue
                parts = line.split()
                if len(parts) >= 2:
                    serial_num = parts[0]
                    state = parts[1]
                    meta = {}
                    for p in parts[2:]:
                        if ":" in p:
                            k, v = p.split(":", 1)
                            meta[k] = v
                    devices.append({
                        "serial": serial_num,
                        "state": state,
                        "model": meta.get("model", "").replace("_", " "),
                        "product": meta.get("product", ""),
                        "device": meta.get("device", ""),
                        "transportId": meta.get("transport_id", "")
                    })
    except Exception:
        pass
    return devices


def query_fastboot_devices() -> List[Dict[str, str]]:
    """Query Fastboot connected devices."""
    fastboot = shutil.which("fastboot") or "fastboot"
    devices = []
    try:
        proc = subprocess.run([fastboot, "devices"], capture_output=True, text=True, timeout=4)
        if proc.returncode == 0:
            for line in proc.stdout.splitlines():
                line = line.strip()
                if not line:
                    continue
                parts = line.split()
                if len(parts) >= 1:
                    devices.append({
                        "serial": parts[0],
                        "state": "fastboot",
                        "mode": "bootloader"
                    })
    except Exception:
        pass
    return devices


def detect_device_state() -> Dict[str, Any]:
    """
    Evidence-based assessment of device connection and low-level mode.
    Returns structured assessment including classification, ADB state, and capabilities.
    """
    emit_event("device_searching", "Scanning USB, ADB, Fastboot, and COM endpoints...")

    # 1. Check Fastboot
    fastboot_devs = query_fastboot_devices()
    if fastboot_devs:
        dev = fastboot_devs[0]
        # Check bootloader unlock status if accessible
        unlocked = "unknown"
        try:
            fb = shutil.which("fastboot") or "fastboot"
            res = subprocess.run([fb, "-s", dev["serial"], "getvar", "unlocked"], capture_output=True, text=True, timeout=3)
            combined = (res.stdout + res.stderr).lower()
            if "unlocked: yes" in combined:
                unlocked = "unlocked"
            elif "unlocked: no" in combined:
                unlocked = "locked"
        except Exception:
            pass

        return {
            "state": "fastboot",
            "name": "Android Bootloader Device",
            "serial": dev["serial"],
            "connectionType": "USB (Fastboot)",
            "adbState": "unavailable",
            "bootloaderState": unlocked,
            "manufacturer": "Android OEM",
            "statusDescription": "Fastboot / Bootloader protocol ready",
            "actions": ["reboot", "reboot-recovery", "factory-reset"]
        }

    # 2. Check ADB
    adb_devs = query_adb_devices()
    if adb_devs:
        dev = adb_devs[0]
        serial_num = dev["serial"]
        adb_state = dev["state"]

        if adb_state == "recovery":
            return {
                "state": "recovery",
                "name": dev["model"] or "Android Recovery Device",
                "serial": serial_num,
                "connectionType": "USB (Recovery)",
                "adbState": "available",
                "statusDescription": "Recovery interface active",
                "actions": ["reboot", "reboot-bootloader", "factory-reset"]
            }
        elif adb_state == "sideload":
            return {
                "state": "recovery",
                "name": dev["model"] or "Android Device (Sideload)",
                "serial": serial_num,
                "connectionType": "USB (Sideload)",
                "adbState": "available",
                "statusDescription": "Sideload recovery protocol ready",
                "actions": ["reboot"]
            }
        elif adb_state == "unauthorized":
            return {
                "state": "normalAndroidLocked",
                "name": dev["model"] or "Android Device (Unauthorized)",
                "serial": serial_num,
                "connectionType": "USB",
                "adbState": "unauthorized",
                "statusDescription": "Device locked or unauthorized - tap Allow on phone",
                "actions": ["reboot"]
            }
        elif adb_state == "device":
            # Check setup wizard or lockscreen
            adb = shutil.which("adb") or "adb"
            is_setup = False
            android_ver = None
            try:
                setup_proc = subprocess.run([adb, "-s", serial_num, "shell", "getprop", "ro.setupwizard.mode"], capture_output=True, text=True, timeout=2)
                if "REQUIRED" in setup_proc.stdout.strip().upper():
                    is_setup = True
                ver_proc = subprocess.run([adb, "-s", serial_num, "shell", "getprop", "ro.build.version.release"], capture_output=True, text=True, timeout=2)
                android_ver = ver_proc.stdout.strip() or None
            except Exception:
                pass

            state = "setupWizard" if is_setup else "normalAndroid"
            return {
                "state": state,
                "name": dev["model"] or "Android Device",
                "model": dev["model"],
                "serial": serial_num,
                "osVersion": f"Android {android_ver}" if android_ver else None,
                "connectionType": "USB (ADB)",
                "adbState": "available",
                "statusDescription": "Normal Android system ready" if not is_setup else "Initial Android setup screen",
                "actions": ["reboot", "reboot-recovery", "reboot-bootloader"]
            }

    # 3. Check COM / Modem (Samsung AT mode)
    com_mgr = WindowsSerialManager()
    if com_mgr.ser:
        try:
            raw_info = com_mgr.send("AT+DEVCONINFO", wait=0.3)
            parsed = parse_devconinfo(raw_info)
            com_mgr.close()
            if parsed.get("model"):
                return {
                    "state": "normalAndroidLocked",
                    "name": f"Samsung Galaxy {parsed.get('model')}",
                    "model": parsed.get("model"),
                    "serial": parsed.get("serialNumber"),
                    "connectionType": f"USB Serial ({com_mgr.port})",
                    "adbState": "unavailable",
                    "statusDescription": "Modem communication active (AT interface)",
                    "actions": ["reboot", "reboot-download"]
                }
        except Exception:
            com_mgr.close()

    # 4. Check Windows PnP via PowerShell
    try:
        ps_cmd = r'''
$known = "VID_04E8", "VID_18D1", "VID_2717", "VID_12D1", "VID_2A70", "VID_22B8", "VID_1004"
$pnp = Get-PnpDevice -PresentOnly | Where-Object {
    $id = $_.InstanceId
    $f = $_.FriendlyName
    ($known | Where-Object { $id -like "*$_*" }) -or ($f -like "*Android*") -or ($f -like "*Galaxy*")
}
if ($pnp) {
    $pnp | ForEach-Object { [PSCustomObject]@{ FriendlyName = $_.FriendlyName; InstanceId = $_.InstanceId } } | ConvertTo-Json -Compress
} else { "" }
'''
        proc = subprocess.run(["powershell.exe", "-NoProfile", "-Command", ps_cmd], capture_output=True, text=True, timeout=4)
        out = proc.stdout.strip()
        if out:
            data = json.loads(out)
            item = data[0] if isinstance(data, list) else data
            inst_id = (item.get("InstanceId") or "").upper()
            friendly = item.get("FriendlyName") or "Android Device"

            # Check for Samsung Download / Odin Mode PID
            if "PID_685D" in inst_id or "PID_685E" in inst_id or "ODIN" in friendly.upper() or "DOWNLOAD" in friendly.upper():
                return {
                    "state": "downloadMode",
                    "name": "Samsung Mobile USB (Download Mode)",
                    "connectionType": "USB (Odin / Download)",
                    "adbState": "unavailable",
                    "statusDescription": "Samsung Download Mode active",
                    "actions": ["reboot"]
                }
            elif "RECOVERY" in friendly.upper():
                return {
                    "state": "recovery",
                    "name": friendly,
                    "connectionType": "USB",
                    "adbState": "unavailable",
                    "statusDescription": "Recovery interface detected",
                    "actions": ["reboot", "factory-reset"]
                }
            else:
                return {
                    "state": "normalAndroidLocked",
                    "name": friendly,
                    "connectionType": "USB",
                    "adbState": "unavailable",
                    "statusDescription": "USB device connected (Android user access locked)",
                    "actions": ["reboot"]
                }
    except Exception:
        pass

    return {
        "state": "disconnected",
        "name": None,
        "connectionType": None,
        "adbState": "unavailable",
        "statusDescription": "No Android device detected on USB",
        "actions": []
    }


def execute_action(action: str, target_serial: Optional[str] = None):
    """Execute supported non-security diagnostic / recovery operations."""
    emit_event("operation_started", f"Starting operation: {action}", action=action)
    adb = shutil.which("adb") or "adb"
    fastboot = shutil.which("fastboot") or "fastboot"

    try:
        if action == "reboot":
            emit_event("progress", "Initiating device reboot...", percent=None)
            # Try ADB reboot first
            res = subprocess.run([adb, "reboot"], capture_output=True, text=True, timeout=5)
            if res.returncode == 0:
                emit_event("operation_completed", "Reboot command dispatched successfully via ADB.", success=True)
                return

            # Try Fastboot reboot
            res = subprocess.run([fastboot, "reboot"], capture_output=True, text=True, timeout=5)
            if res.returncode == 0:
                emit_event("operation_completed", "Reboot command dispatched successfully via Fastboot.", success=True)
                return

            # Try Samsung AT+CFUN=1,1
            com_mgr = WindowsSerialManager()
            if com_mgr.ser:
                try:
                    com_mgr.send("AT+CFUN=1,1", wait=0.5)
                    com_mgr.close()
                    emit_event("operation_completed", "Reboot command dispatched via AT modem interface.", success=True)
                    return
                except Exception:
                    com_mgr.close()

            emit_event("operation_failed", "Unable to dispatch reboot command on available interfaces.", success=False)

        elif action == "reboot-download":
            emit_event("progress", "Switching to Download Mode...", percent=None)
            # Try Samsung AT+FUS?
            com_mgr = WindowsSerialManager()
            if com_mgr.ser:
                try:
                    com_mgr.send("AT+FUS?", wait=0.5)
                    com_mgr.close()
                    emit_event("operation_completed", "Dispatched Download Mode trigger via AT+FUS?.", success=True)
                    return
                except Exception:
                    com_mgr.close()

            # Try ADB reboot download
            res = subprocess.run([adb, "reboot", "download"], capture_output=True, text=True, timeout=5)
            if res.returncode == 0:
                emit_event("operation_completed", "Dispatched Download Mode reboot via ADB.", success=True)
                return

            emit_event("operation_failed", "Download Mode reboot not supported on this interface.", success=False)

        elif action == "reboot-recovery":
            emit_event("progress", "Rebooting into Recovery Mode...", percent=None)
            res = subprocess.run([adb, "reboot", "recovery"], capture_output=True, text=True, timeout=5)
            if res.returncode == 0:
                emit_event("operation_completed", "Dispatched recovery reboot command via ADB.", success=True)
                return

            res = subprocess.run([fastboot, "reboot-recovery"], capture_output=True, text=True, timeout=5)
            if res.returncode == 0:
                emit_event("operation_completed", "Dispatched recovery reboot via Fastboot.", success=True)
                return

            emit_event("operation_failed", "Unable to trigger recovery mode on current interface.", success=False)

        elif action == "reboot-bootloader":
            emit_event("progress", "Rebooting into Bootloader / Fastboot...", percent=None)
            res = subprocess.run([adb, "reboot", "bootloader"], capture_output=True, text=True, timeout=5)
            if res.returncode == 0:
                emit_event("operation_completed", "Device rebooting to bootloader.", success=True)
                return
            emit_event("operation_failed", "Unable to trigger bootloader mode via ADB.", success=False)

        elif action == "factory-reset":
            emit_event("progress", "Executing confirmed factory wipe via Fastboot...", percent=None)
            cmd = [fastboot]
            if target_serial:
                cmd += ["-s", target_serial]
            cmd += ["-w"]
            res = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
            if res.returncode == 0:
                emit_event("operation_completed", "Wipe data & cache completed. Waiting for device reboot...", success=True)
            else:
                emit_event("operation_failed", f"Fastboot format failed: {res.stderr.strip()}", success=False)

        else:
            emit_event("operation_failed", f"Unrecognized operation: {action}", success=False)

    except Exception as e:
        emit_event("operation_failed", f"Operation error: {e}", success=False)


def run_mock_harness():
    """Interactive mock harness for testing UI reactions without physical devices."""
    emit_event("startup", "Mock nPhoneKIT engine harness running")
    time.sleep(0.5)

    states = [
        {"state": "disconnected", "name": None, "connectionType": None, "adbState": "unavailable", "statusDescription": "No device connected", "actions": []},
        {"state": "normalAndroidLocked", "name": "Samsung Galaxy S22", "model": "SM-S901U", "serial": "R5CR123456", "connectionType": "USB", "adbState": "unavailable", "statusDescription": "USB device connected (Android user access locked)", "actions": ["reboot", "reboot-download"]},
        {"state": "recovery", "name": "Samsung Galaxy S22 (Recovery)", "model": "SM-S901U", "serial": "R5CR123456", "connectionType": "USB (Recovery)", "adbState": "available", "statusDescription": "Recovery interface active", "actions": ["reboot", "reboot-bootloader", "factory-reset"]},
        {"state": "fastboot", "name": "Google Pixel 7 (Fastboot)", "serial": "28191FDH2003", "connectionType": "USB (Fastboot)", "adbState": "unavailable", "bootloaderState": "unlocked", "statusDescription": "Fastboot / Bootloader protocol ready", "actions": ["reboot", "reboot-recovery", "factory-reset"]},
    ]

    for st in states:
        emit_event("device_detected" if st["state"] != "disconnected" else "device_disconnected",
                   f"State: {st['state']}", device=st)
        time.sleep(1.5)


def run_interactive_stream():
    """Standard bidirectional IPC stream listening on stdin."""
    emit_event("startup", "414Unlock nPhoneKIT engine adapter active")

    # Initial assessment
    state = detect_device_state()
    if state["state"] != "disconnected":
        emit_event("device_detected", f"Device detected: {state['name']}", device=state)
    else:
        emit_event("device_disconnected", "No device connected", device=state)

    while True:
        try:
            line = sys.stdin.readline()
            if not line:
                break
            line = line.strip()
            if not line:
                continue

            try:
                cmd_data = json.loads(line)
            except Exception:
                cmd_data = {"cmd": line}

            cmd = cmd_data.get("cmd", "")
            if cmd == "detect":
                st = detect_device_state()
                if st["state"] != "disconnected":
                    emit_event("device_detected", f"Device detected: {st['name']}", device=st)
                else:
                    emit_event("device_disconnected", "No device connected", device=st)
            elif cmd == "action":
                action_name = cmd_data.get("action", "")
                serial_target = cmd_data.get("serial", None)
                execute_action(action_name, serial_target)
            elif cmd == "cancel":
                emit_event("cancelled", "Current operation cancelled by user")
            elif cmd == "ping":
                emit_event("pong", "Alive")
            elif cmd == "exit":
                break

        except KeyboardInterrupt:
            break
        except Exception as e:
            emit_error("ProcessError", f"Error in stream loop: {e}")

    emit_event("process_exited", "Engine adapter exiting cleanly", exitCode=0)


def main():
    parser = argparse.ArgumentParser(description="414Unlock Android nPhoneKIT Adapter")
    parser.add_argument("--mode", choices=["stream", "detect", "action", "mock", "health"], default="stream")
    parser.add_argument("--action", help="Action name for --mode=action")
    parser.add_argument("--serial", help="Target serial number")
    args = parser.parse_args()

    if args.mode == "health":
        adb = shutil.which("adb") is not None
        fastboot = shutil.which("fastboot") is not None
        emit_event("health", "Health check completed",
                   pyserial=HAS_PYSERIAL,
                   adb=adb,
                   fastboot=fastboot,
                   pythonVersion=sys.version.split()[0])
        sys.exit(0)
    elif args.mode == "detect":
        st = detect_device_state()
        sys.stdout.write(json.dumps(st) + "\n")
        sys.exit(0)
    elif args.mode == "action":
        if not args.action:
            emit_error("ProcessError", "No action specified")
            sys.exit(1)
        execute_action(args.action, args.serial)
        sys.exit(0)
    elif args.mode == "mock":
        run_mock_harness()
        sys.exit(0)
    else:
        run_interactive_stream()


if __name__ == "__main__":
    main()

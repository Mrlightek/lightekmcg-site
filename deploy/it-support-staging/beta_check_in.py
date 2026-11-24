#!/usr/bin/env python3
"""One-shot opt-in check-in using the existing Batch B Gatekeeper agent."""
import getpass
import os
import re
import urllib.error

import lightek_device_agent as agent


def main():
    host = input("Enter the staging hostname shown in the Dashboard: ").strip()
    identifier = input("Device ID: ").strip()
    if not re.fullmatch(r"batch-d-[a-z0-9-]+\.staging\.(?:[a-z0-9-]+\.)+[a-z]{2,}", host):
        raise ValueError("Use the assigned Batch D staging hostname")
    if not re.fullmatch(r"msp-beta-[1-9][0-9]*", identifier):
        raise ValueError("Use the test device ID from the Dashboard")
    if input("Send CPU, memory and disk usage percentages from this test device? [y/N] ").strip().lower() != "y":
        return
    token = getpass.getpass("Enrollment token (hidden): ").strip()
    if not re.fullmatch(r"[a-f0-9]{64}", token):
        raise ValueError("Use the token from the Dashboard")
    os.environ.update(LIGHTEK_DEVICE_URL=f"https://{host}/gatekeeper/device", LIGHTEK_DEVICE_TOKEN=token)
    try:
        agent.post({"method_type": "device_enroll", "identifier": identifier})
        agent.post({"method_type": "device_heartbeat", "identifier": identifier, "health_telemetry": agent.collect()})
        print("Check-in complete. Refresh the MSP beta page to verify the receipt.")
    finally:
        os.environ.pop("LIGHTEK_DEVICE_TOKEN", None)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, urllib.error.URLError) as error:
        raise SystemExit(f"Check-in failed ({type(error).__name__}). Verify the device, token, and staging hostname.")

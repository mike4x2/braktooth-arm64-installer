# WDissector Library (C/C++ Wireshark Fuzzing API)

WDissector is a wireless fuzzing framework for testing the wireless implementation of black-box devices that utilize Bluetooth Classic, Wi-Fi, 4G, and 5G radio access networks for wireless communication...

---

## ARM64 Status (Community Port)

> **Work in Progress**

This repository has been tested on ARM64 hardware (Orange Pi Zero 2W / Armbian). The project currently builds and starts successfully, but is **not yet fully functional** on ARM64.

### Current Status

| Component | Status |
|-----------|--------|
| Build | ✅ Working |
| Application Startup | ✅ Working |
| Module Loading | ✅ Working |
| ESP32 Serial Initialization | ✅ Working |
| Runtime Stability | ❌ Segmentation Fault |
| Bluetooth Fuzzing | 🚧 Under Investigation |

### Tested Platform

- Orange Pi Zero 2W
- Armbian (Debian Trixie)
- ESP32-Ethernet-Kit-VE
- USB UART @ 4,000,000 baud

### Current Focus

The current blocker is a runtime segmentation fault after initialization. The project installs and launches successfully, but additional ARM64 debugging is required before the framework is considered operational.

---

* ##### Download Binary Release:
...

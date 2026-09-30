# Live MTN FlyX / ZLT X17U mapping notes

The app deliberately separates **proven read calls** from **firmware-specific writes**.

Implemented now:

- `GET /reqproc/proc_get` batching.
- Login using `get_random_login` + SHA-256 + Base64.
- CSRF token retrieval.
- Session-cookie capture where the firmware returns a `random` cookie.
- Safe status reads for network type, RSSI, RSRQ, PCI, PPP state and common authenticated LTE fields.
- `station_list` parsing for connected devices when the firmware exposes it.
- Read-only inspection of `/js/service.js`, `/js/config/ufi/config.js`, and `/js/util.js` to discover action names from the router itself.

Write controls are capability-gated. The live adapter only calls an action if that action name was observed in the router's own JavaScript. This is important because field names and goform IDs can vary by carrier firmware even within the same ZLT/ZTE family.

The first real-device test should therefore be:

1. Connect the phone/PC to FlyX Wi-Fi.
2. Run `python tool/discover_x17u.py --json > flyx-report.json` or use the in-app Connect screen.
3. Review the sanitized action list.
4. Map MTN's exact blocking/parental-control and per-client traffic calls before enabling quotas as unattended enforcement.

Do not publish reports containing IMEI, IMSI, serial number, Wi-Fi passwords, phone numbers or other device-specific identifiers.

# FlyX Control

FlyX Control is a local-first Flutter app for managing the MTN FlyX / Tozed ZLT X17U router without relying on the router's web interface.

It connects directly to the router over the local network and only exposes controls that have been verified against the tested MTN X17U firmware.

## Features

- Live network status, signal metrics, WAN throughput, usage and router health
- Connected, offline and blocked device views
- Friendly device names and observed connection history
- Instant device block / unblock
- Parent Control schedules
- 2.4 GHz and 5 GHz Wi-Fi controls
- SMS inbox, search/filtering, replies, sending and deletion
- Interactive USSD
- Mobile-network settings including Flight Mode, mobile data and roaming
- Router restart
- Local daily/weekly usage and reliability history
- Forget locally remembered offline devices

## Important limitations

- Per-device Internet usage and quotas are not exposed reliably by this MTN firmware, so FlyX Control does not simulate them.
- Wi-Fi link rates are treated as Wi-Fi association information, not Internet speed.
- The tested firmware exposes its active network mode as Automatic; unsupported 4G-only/5G-only modes are not invented.
- Local observation history only includes periods when FlyX Control was actually observing the router.

## Development

Requirements:

- Flutter stable
- Python 3
- Android SDK

On Windows:

```powershell
powershell -ExecutionPolicy Bypass -File tool/bootstrap_android.ps1
flutter analyze
flutter test
flutter build apk --debug
```

GitHub Actions runs the same analysis, tests and debug APK build on each push to `main`.

## Router discovery tools

Read-only basic discovery:

```powershell
py tool/discover_x17u.py
```

Authenticated read-only discovery:

```powershell
py tool/discover_x17u_auth.py --json > flyx-auth-report.json
```

Inspect the stock router UI without logging in or sending router commands:

```powershell
py tool/inspect_x17u_ui.py --json > flyx-ui-report.json
```

Do not publish unredacted router reports containing device identifiers or session information.


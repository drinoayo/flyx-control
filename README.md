# FlyX Control

A premium, local-first mobile controller for the MTN FlyX / ZLT X17U router.

This first build contains a complete high-fidelity Flutter UI, a demo data source so every screen is explorable immediately, a real ZLT `reqproc` client, encrypted credential storage, SQLite usage-history infrastructure, connected-device parsing, capability discovery, and guarded write actions.

## What is already built

- Premium dark UI with restrained MTN-yellow accents and Inter typography.
- Home dashboard with live signal, throughput, latency, device activity, weekly usage and uptime cards.
- All / Online / Blocked device views.
- Device detail pages with live traffic, daily/weekly/monthly usage, current-session uptime, total online time, friendly names, block/unblock UI and data-quota controls.
- Network dashboard with RSRP/RSRQ/SINR/PCI/bands, signal history, connection health and capability-gated advanced controls.
- Connect-to-router screen using the X17U local address and encrypted password storage.
- ZLT/ZTE `reqproc` login + read client.
- Read-only firmware capability scanner that inspects the router's own JavaScript before exposing writes.
- Local SQLite schema for long-term per-device traffic samples.
- Standalone `tool/discover_x17u.py` discovery utility with no third-party Python dependencies.

## Important distinction

The demo repository makes the full product experience visible now. The live repository does **not** fake firmware features. Signal reads and `station_list` are wired. Blocking, quotas, Wi-Fi changes and similar writes are only enabled when the exact action is discovered on the MTN X17U firmware.

This prevents a dangerous UX where an app shows a switch that silently does nothing or sends a carrier-specific command that was never verified against your router.

## Run it

Flutter is not bundled in this repository. Install a current stable Flutter SDK, then from this folder:

```bash
flutter create --project-name flyx_control --org com.etchpoint.flyxcontrol --platforms=android,ios .
flutter pub get
flutter run
```

If `flutter create` replaces `lib/main.dart` on your Flutter version, restore the repository's `lib/` folder after running the command.

### Android local HTTP

The FlyX admin interface uses local HTTP rather than HTTPS. Merge the files under `platform_patches/android/` into the generated Android project:

- add INTERNET/ACCESS_NETWORK_STATE permissions;
- set `android:usesCleartextTraffic="true"`;
- copy `network_security_config.xml` to `android/app/src/main/res/xml/` and reference it from the application element.

### iOS local network

Merge `platform_patches/ios/Info.plist.snippet.xml` into `ios/Runner/Info.plist` so iOS can access the router over the local network.

## Safe X17U discovery without Flutter

While your computer is connected to FlyX Wi-Fi:

```bash
python tool/discover_x17u.py
```

or save a machine-readable report:

```bash
python tool/discover_x17u.py --json > flyx-report.json
```

The script does not log in and does not change router settings. Do not share unredacted device identifiers publicly.

## Next live-device milestone

The next milestone is to run the discovery tool against your MTN X17U and map:

1. exact parental-control/block/unblock action;
2. blocked-device list source;
3. per-device cumulative RX/TX counters;
4. router uptime field;
5. MTN USSD/SMS behavior;
6. Wi-Fi settings write contract;
7. any QoS/speed-limit fields actually exposed by this firmware.

Once those are confirmed, the existing screens and policy engine can be wired to real data instead of demo values.

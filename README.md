# FlyX Control

A premium, local-first mobile controller for the MTN FlyX / Tozed ZLT X17U router.

FlyX Control is being built as a proper consumer network-control app rather than a wrapper around the router's web page. The UI is usable with demo data now, while the live adapter is being verified against the real MTN X17U firmware one capability at a time.

## What is already built

- Premium dark mobile UI with restrained MTN-yellow accents and Inter typography.
- Home dashboard with signal, throughput, latency, device activity, weekly usage and uptime cards.
- All / Online / Blocked device views.
- Device detail pages with live traffic, daily/weekly/monthly usage, current-session uptime, total online time, friendly names, block/unblock UI and data-quota controls.
- Network dashboard with RSRP/RSRQ/SINR/PCI/bands, signal history and connection-health UI.
- Connect-to-router flow with encrypted local credential storage.
- Native Tozed X17U API client using `POST /cgi-bin/http.cgi`.
- X17U challenge-response login flow and rotating write token support.
- Real WAN/status reads, router uptime, cellular signal values and cumulative traffic counters.
- Real connected-device parsing through the authenticated device-list command.
- Filter-rule discovery and guarded block/unblock implementation.
- SQLite infrastructure for long-term per-device usage history.
- Standalone read-only X17U discovery utility with no third-party Python dependencies.

## X17U API mapping

The MTN FlyX ZLT X17U is a Tozed device. Its web UI uses a JSON command endpoint:

```text
POST /cgi-bin/http.cgi
```

Read requests use a JSON body shaped like:

```json
{"cmd": 133, "method": "GET", "sessionId": ""}
```

The current safe mapping includes:

- `113` — liveness/basic status
- `133` — WAN state, router uptime, cumulative WAN byte counters and core RF values
- `205` — richer RF/operator/monthly-flow information
- `232` — login challenge
- `100` — login
- `233` — authenticated write token
- `223` — connected-device list
- `23` — filter rules

Filter-mode/write commands are implemented defensively and remain capability-gated.

## Important distinction

The demo layer makes the complete product experience visible before every firmware feature is mapped. The live adapter does **not** pretend unsupported controls work.

That matters for actions such as blocking, quotas, Wi-Fi changes, reboot, SMS, USSD, band controls and QoS. Potentially disruptive actions are enabled only after the required X17U commands are verified.

## Safe X17U discovery without Flutter

While your computer is connected to the FlyX Wi-Fi:

```bash
python tool/discover_x17u.py
```

or save a machine-readable report:

```bash
python tool/discover_x17u.py --json > flyx-report.json
```

The discovery tool is read-only. It does not log in and does not change router settings. It currently probes only known safe status commands.

Do not publish unredacted reports containing device identifiers.

## Run the Flutter app

Flutter is not bundled in this repository. Install a current stable Flutter SDK, then from this folder:

```bash
flutter create --project-name flyx_control --org com.etchpoint.flyxcontrol --platforms=android,ios .
flutter pub get
flutter run
```

If `flutter create` replaces `lib/main.dart` on your Flutter version, restore the repository's `lib/` folder after running the command.

### Android local HTTP

The FlyX admin interface is local HTTP rather than HTTPS. Merge the files under `platform_patches/android/` into the generated Android project:

- add INTERNET/ACCESS_NETWORK_STATE permissions;
- set `android:usesCleartextTraffic="true"`;
- copy `network_security_config.xml` to `android/app/src/main/res/xml/` and reference it from the application element.

### iOS local network

Merge `platform_patches/ios/Info.plist.snippet.xml` into `ios/Runner/Info.plist` so iOS can access the router over the local network.

## Next live-device milestone

Run the discovery utility against the real MTN X17U and use the returned field set to finish:

1. exact RF field behavior on the MTN firmware;
2. per-device cumulative RX/TX counters, if exposed;
3. device uptime/session fields;
4. quota/QoS controls;
5. Wi-Fi settings;
6. SMS and USSD;
7. reboot, network-mode and advanced radio controls.

Historical daily/weekly/monthly usage can then be built locally from cumulative counters even where the router does not retain that history itself.

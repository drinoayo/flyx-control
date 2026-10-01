# FlyX Control

A premium, local-first mobile controller for the MTN FlyX / Tozed ZLT X17U router.

FlyX Control is being built as a proper consumer network-control app rather than a wrapper around the router's web page. The live adapter is being verified against a real MTN X17U firmware one capability at a time, and unsupported controls stay hidden instead of being simulated.

## What is already built

- Premium dark mobile UI with restrained MTN-yellow accents and Inter typography.
- Home dashboard with cellular signal, live total WAN throughput, data usage, device activity and router uptime.
- All / Online / Offline / Blocked device views with capability-aware states.
- Real connected-device discovery from the authenticated X17U client list.
- Real 5 GHz association detail, including per-client RSSI where exposed.
- Device detail pages that distinguish Wi-Fi association information from unverified per-device internet traffic.
- Network dashboard with RSRP/RSRQ/SINR/PCI/bands, signal history, cumulative usage and router-health information.
- Connect-to-router flow with encrypted local credential storage and automatic reconnection on later launches.
- Native Tozed X17U API client using POST /cgi-bin/http.cgi.
- X17U challenge-response login flow and rotating write token support.
- Real WAN byte counters, router uptime, monthly download/upload totals, CPU usage, temperature, memory and firmware version.
- SQLite-backed local daily/weekly usage history derived from verified cumulative WAN counters.
- Safe read-only X17U discovery utilities and a stock-web-UI inspector.
- Verified Parent Control schedules for connected devices: create, edit, enable/disable and delete, with minute-level enforcement, readback verification and rollback.
- Persistent local friendly names plus first-seen/last-seen device history keyed by MAC address.
- Verified Instant Block / Unblock through the X17U Wi-Fi deny list on both bands, with readback verification and rollback.
- Persistent app-observed device sessions plus tracked online time today.
- Locally observed internet uptime and outage counts that ignore periods when FlyX Control was not observing the router.
- Live Wi-Fi settings view for both 2.4 GHz and 5 GHz, with guarded SSID, password and broadcast controls.

## Confirmed X17U API mapping

The current tested mapping includes:

- 113 — basic status/liveness
- 133 — WAN state and core radio information
- 205 — richer radio/operator information
- 232 — login challenge
- 100 — login
- 233 — authenticated write token
- 223 — connected-device list
- 224 — 2.4 GHz association information; empty on the tested setup
- 225 — 5 GHz association information, including client RSSI
- 18 — cumulative WAN RX/TX bytes and router uptime
- 337 — monthly traffic totals and traffic-limit configuration fields
- 401 — dashboard/network summary plus connected-device data
- 207 — CPU, temperature, memory, firmware and hardware status
- 2 / 211 — 2.4 GHz / 5 GHz primary Wi-Fi settings
- 230 / 231 — 2.4 GHz / 5 GHz radio/channel settings
- 132 — WPS state
- 410 — advanced Wi-Fi settings endpoint; empty on the tested MTN X17U response
- 463 — Wi-Fi band-selection endpoint; no extra readable fields on the tested response
- 23, 28, 30 — accepted as reads, but no readable filter-rule state is returned

Command 25 returns LIMITED_ACCESS on the tested MTN account.

## Parent Control schedules

The tested MTN X17U firmware exposes Kids Management through command 385 and applies changes through command 20. FlyX Control now supports repeating blocked-time schedules for connected devices.

Schedule writes are guarded: the app resolves the device's current LAN IP, preserves the full rule list, writes the change, applies it, reads the state back, and attempts to restore the previous rules if verification fails.

## Blocking and per-device limits

Instant Block / Unblock is verified on the tested MTN X17U firmware through command 278, the stock Wi-Fi deny-list path. FlyX Control writes both Wi-Fi bands, preserves existing rules, refuses whitelist mode, verifies readback, and attempts an exact rollback if either band does not match.

The connected-device list still exposes no trustworthy per-device byte counter. In an idle-vs-active traffic test, the DHCP `flow` field remained 0 and command 355 returned no usable client accounting. Wi-Fi `txrate` did react to traffic, but it is an association/link-rate field and is not treated as real Internet throughput or data usage.

The stock MTN frontend contains generic Speed Limit/LAN Speed Limit/WAN Speed Limit translation strings, but its actual route table and API wrappers expose no usable per-device speed-limit/QoS implementation on this firmware. Per-device quotas therefore remain disabled rather than being simulated.

Daily and weekly whole-router usage is still available: FlyX Control records deltas from the verified cumulative WAN byte counters locally. Monthly total/download/upload values come directly from the router.

## Safe discovery

While connected to the FlyX Wi-Fi:

    python tool/discover_x17u.py

Authenticated read-only discovery:

    python tool/discover_x17u_auth.py --json > flyx-auth-report.json

Inspect the stock router web UI JavaScript without logging in or sending router commands:

    python tool/inspect_x17u_ui.py --json > flyx-ui-report.json

Do not publish unredacted router reports containing device identifiers.

## Next live-device milestones

Completed:
- Router-clock alignment for Parent Control status.
- Recent observed device-session and internet-outage history.

Remaining major feature groups:
1. Complete Wi-Fi live-write verification, then add safe radio/channel controls.
2. Map SMS and USSD.
3. Verify reboot, network-mode and advanced radio controls.
4. Add cleanup/forget controls for remembered devices and finish Android release packaging.



## Android development setup

The repository keeps the Flutter source plus small platform-specific patches rather than committing generated Android template files. On Windows, run:

    powershell -ExecutionPolicy Bypass -File tool/bootstrap_android.ps1

That generates the Android scaffold, applies the local-router cleartext/network-security configuration, removes Flutter's placeholder sample test if generated, and installs dependencies.

Then run:

    flutter analyze
    flutter build apk --debug

GitHub Actions performs the same bootstrap before analysis and APK builds.

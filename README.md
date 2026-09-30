# FlyX Control

A premium, local-first mobile controller for the MTN FlyX / Tozed ZLT X17U router.

FlyX Control is being built as a proper consumer network-control app rather than a wrapper around the router's web page. The live adapter is being verified against a real MTN X17U firmware one capability at a time, and unsupported controls stay hidden instead of being simulated.

## What is already built

- Premium dark mobile UI with restrained MTN-yellow accents and Inter typography.
- Home dashboard with cellular signal, live total WAN throughput, data usage, device activity and router uptime.
- All / Online / Blocked device views with capability-aware states.
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
- 23, 28, 30 — accepted as reads, but no readable filter-rule state is returned

Command 25 returns LIMITED_ACCESS on the tested MTN account.

## Blocking and per-device limits

The tested firmware accepts filter-related commands but does not expose the current filter list or mode in readable form. FlyX Control therefore keeps router-side Block/Unblock disabled for now. Writing a guessed deny-list configuration could lock legitimate devices out of the router.

The connected-device list includes a flow field, but it currently reports 0 for active clients. The 5 GHz association command also reports txrate and rxrate as 0 on the tested setup. Those fields are not treated as real per-device internet usage or speed.

Daily and weekly whole-router usage is still possible: FlyX Control records deltas from the verified cumulative WAN byte counters locally. Monthly total/download/upload values come directly from the router.

## Safe discovery

While connected to the FlyX Wi-Fi:

    python tool/discover_x17u.py

Authenticated read-only discovery:

    python tool/discover_x17u_auth.py --json > flyx-auth-report.json

Inspect the stock router web UI JavaScript without logging in or sending router commands:

    python tool/inspect_x17u_ui.py --json > flyx-ui-report.json

Do not publish unredacted router reports containing device identifiers.

## Next live-device milestones

1. Identify the stock UI's exact MAC-filter/block payload before enabling device blocking.
2. Determine whether this MTN firmware exposes any usable per-device byte accounting through another command.
3. Map Wi-Fi settings.
4. Map SMS and USSD.
5. Verify reboot, network-mode and advanced radio controls.
6. Add persistent friendly device names and richer local device history.

# Live MTN FlyX / ZLT X17U mapping notes

## Confirmed API family

The X17U is a Tozed device, not a ZTE reqproc router. Its web UI communicates through POST /cgi-bin/http.cgi.

## Authentication

The tested MTN firmware uses this login sequence:

1. Read command 232 for the challenge token.
2. Calculate SHA-256 of token + password.
3. Submit command 100 with username, digest and a generated session identifier.
4. Retain the returned session identifier.
5. Read command 233 before a write to obtain a fresh token.

## Confirmed reads on the tested MTN firmware

Unauthenticated monitoring:

- 113 — basic status/liveness
- 133 — WAN state and core RF information
- 205 — richer RF/operator information

Authenticated read-only probes:

- 223 — connected clients via dhcp_list_info
- 224 — 2.4 GHz association data; empty on the tested setup
- 225 — 5 GHz association data; returned two clients, RSSI, SSID and IP information
- 18 — cumulative WAN byte/packet counters plus router uptime
- 337 — monthly traffic total, monthly down/up totals and traffic-limit settings
- 401 — dashboard/network summary plus connected clients
- 207 — CPU, temperature, memory, firmware/hardware detail
- 23/28/30 — accepted, but only success/cmd/message were returned, with no readable rule/mode structure

Command 25 returned LIMITED_ACCESS on the tested MTN account.

Command 402 returned malformed JSON containing an invalid control character on the tested firmware. It is not required because commands 223 and 401 already provide the client list.

## Connected devices

Command 223 is currently the canonical device-list source. The tested device entries expose MAC address, LAN IP, hostname, interface, DHCP expiry, flow and IPv6 address.

The flow value was 0 for both active clients during discovery, so it is not treated as verified per-device traffic accounting.

Command 225 adds 5 GHz association information. It returned client RSSI successfully, while txrate and rxrate were both zero on the tested setup. FlyX Control therefore displays the RSSI/band association but does not present zero link-rate fields as real internet speed.

## Usage and live speed

Command 18 exposes verified cumulative WAN RX/TX byte counters and uptime. FlyX Control differences consecutive counter samples to calculate whole-router live throughput. Counter rewinds or uptime rewinds re-baseline the calculation rather than creating a false spike.

A local SQLite history stores safe WAN deltas. That enables daily and weekly total usage even though the router itself primarily exposes cumulative values. If the app was closed across midnight, an unknown interval is distributed proportionally across the local calendar days it crossed.

Command 337 provides the router's current monthly traffic totals, including separate download and upload values.

## Router health

Command 207 exposes CPU usage, device temperature, free memory, firmware version, board/hardware identifiers and router uptime. These are surfaced in the Network screen.

## Blocking

The stock MTN web UI JavaScript confirms the MAC-filter API family:

- getMACData uses command 23 with method GET and **getfun=true**;
- setMACData uses command 23 with method POST;
- setIPFilterMode uses command 28 with method POST;
- setMACMode uses command 30 with method POST;
- getWirelessFilter / setWirelessFilter use command 278;
- the UI includes MAC Filter, whitelist/blacklist and Access Control surfaces.

The earlier read-only probe of command 23 omitted getfun=true, which likely explains why that probe returned only an empty message. The discovery utility and Flutter capability scan now match the stock UI read contract.

Block/Unblock still remains capability-gated until a new read-only probe confirms the actual rule-list and mode payload returned by this MTN firmware. A write must preserve the router's existing mode and rules rather than assuming their structure.

## Per-device limits

The stock web UI bundle contains Speed Limit, downlink-speed-limit and uplink-speed-limit interfaces, so the firmware family clearly contains speed-control functionality. That does not yet prove the MTN account exposes the corresponding control payload.

Per-device quotas still require both trustworthy per-device byte accounting and a verified enforcement mechanism. Command 25 is access-restricted and the known client-list flow fields remain zero.

The app must not substitute Wi-Fi RSSI or association link rate for internet data usage.

## Other stock UI mappings

The web bundle also confirms:

- command 350 is used for USSD GET/POST;
- command 337 is used for traffic-flow GET/POST;
- command 355 is an alternate traffic-flow GET/POST endpoint;
- command 278 is the wireless-filter GET/POST endpoint.

These are now included only as read probes until their exact field semantics are verified.

## Safety rule

Never guess a write command. Read and verify first, preserve existing configuration, and keep high-impact controls disabled until the exact command semantics are confirmed against the real MTN firmware.

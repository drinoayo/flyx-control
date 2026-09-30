# Live MTN FlyX / ZLT X17U mapping notes

## Confirmed API family

The X17U should be treated as a Tozed device, not as a ZTE `reqproc` router.

Its web UI communicates through:

```text
POST /cgi-bin/http.cgi
Content-Type: application/json;charset=UTF-8
```

A read request is shaped like:

```json
{"cmd": 133, "method": "GET", "sessionId": ""}
```

The first repository build incorrectly assumed `/reqproc/proc_get`. A real MTN X17U returned HTTP 404 for that path, which led to this correction.

## Safe unauthenticated reads

The read-only discovery utility currently checks:

- command 113: liveness/basic status;
- command 133: WAN state, uptime, cumulative WAN byte counters and core RF metrics;
- command 205: richer RF/operator/monthly-flow information.

These calls do not log in and do not change settings.

## Authentication

The live Flutter client supports the X17U challenge flow:

1. read command 232 for the challenge token;
2. calculate SHA-256 of `token + password`;
3. submit command 100 with the username, digest and a client-generated session identifier;
4. retain the session identifier returned by the router;
5. read command 233 before each write to obtain a fresh write token.

The app avoids retry loops around login so an incorrect password cannot be hammered repeatedly.

## Connected devices and blocking

After login, the adapter can safely read:

- command 223 for `dhcp_list_info`;
- command 23 for filter rules;
- commands 28 and 30 as capability checks for filter modes.

A blocked device can disappear from the active DHCP/association list, so FlyX Control also constructs the Blocked view from filter rules. That lets a blocked client remain visible even while offline.

The current block implementation preserves existing rules, switches the router to deny-list semantics, writes IPv4 and IPv6 deny rules for the selected MAC, then applies the change. It is still capability-gated and should be tested on the user's exact firmware before being treated as production-stable.

## Usage and live speed

Command 133 exposes cumulative WAN RX/TX byte counters and router uptime on known X17U firmware. FlyX Control differences consecutive counter samples to calculate live throughput and re-baselines after a reboot or counter rewind.

Per-device daily/weekly/monthly usage still requires either:

- per-device cumulative counters exposed by another X17U command; or
- another reliable router-side accounting source.

The app's SQLite layer is already prepared to retain history once those counters are identified.

## Safety rule

Never guess a write command. Read and verify first, preserve existing configuration, and keep high-impact controls disabled until the required fields and command semantics are confirmed against the real MTN firmware.

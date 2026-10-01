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

A follow-up authenticated read-only probe used the stock UI's exact getMACData shape, including getfun=true. On this MTN firmware, command 23 still returned only success/cmd/message with no rule list. Commands 28 and 30 behaved the same way. Command 278 (the stock UI's wireless-filter endpoint) also returned only success/cmd/message.

This means the missing filter state is not simply caused by the earlier probe shape. Block/Unblock remains capability-gated.

The next safe path is to inspect the lazy-loaded firewall/access-control route chunks from the stock web UI. Those chunks should reveal the actual form payloads, mode fields and any alternate blocking workflow used by this branded firmware.

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

On the tested MTN firmware, command 350 timed out as a read, command 355 returned an empty object, and command 278 returned no fields beyond success/cmd/message. These are not enabled as app controls yet.

## Safety rule

Never guess a write command. Read and verify first, preserve existing configuration, and keep high-impact controls disabled until the exact command semantics are confirmed against the real MTN firmware.


## Stock UI v0.4 findings

The lazy-loaded frontend chunks reveal a second, cleaner device-blocking path through the Wi-Fi blacklist/whitelist UI.

The connected-device route is /connect/info and loads chunk-647cc786. Its Wi-Fi filter component:

- reads command 278 using subcmd equal to the selected Wi-Fi band;
- expects datas.macfilter and datas.maclist;
- uses macfilter values close, deny and allow;
- writes command 278 with payload shaped as datas: { maclist, macfilter }, plus subcmd;
- maps Wi-Fi type "0" to the 5 GHz client list (cmd 225) and "1" to the 2.4 GHz client list (cmd 224);
- warns that Wi-Fi blacklist/whitelist filtering is disabled when WPS or MESH is enabled.

This is a better candidate for Block/Unblock than the generic firewall MAC-filter page because it is directly wired to the attached-device screen.

The next authenticated read-only probe therefore requests command 278 separately with subcmd "0" and "1". If both responses expose datas, FlyX Control can preserve each band's existing close/deny/allow mode and MAC list instead of inventing filter state.

The firewall Filtering Rules chunk also confirms generic MAC-rule writes use datas arrays with enableRule, enableLink, ippro and mac fields, while the default mode payload uses acceptAll for IPV4 and IPV6. That remains a fallback path rather than the preferred device-blocking implementation.


## Fourth authenticated discovery

The band-specific wireless-filter reads were tested using the stock UI's exact subcmd mapping:

- command 278 + subcmd "0" for 5 GHz;
- command 278 + subcmd "1" for 2.4 GHz.

Both requests authenticated successfully, but this MTN firmware still returned only success/cmd/message with no datas object. The generic command 278 read behaved the same way.

Therefore the Wi-Fi blacklist/whitelist UI code exists in the frontend bundle, but its readable state is not exposed by this firmware/account in the tested configuration. FlyX Control must keep Block/Unblock disabled rather than assuming an empty list or default deny mode.

The next promising route is the stock Parent Control module, because it may expose device-specific access scheduling or pause controls without relying on the hidden generic MAC-filter state.


## Parent Control frontend contract

The stock /menu/parentControl chunk exposes a separate, device-oriented control path that is more promising than the hidden Wi-Fi MAC-filter state.

Confirmed frontend API wrappers:

- cmd 397 GET/POST: parent-control summary/state;
- cmd 385 GET with getfun=true: per-device parental-control rule list;
- cmd 385 POST: save the full parental-control rule list;
- cmd 391 POST with enable="1": enable parental-control mode.

The Kids Management UI builds rules with:

- enableRule
- ip
- startTime
- endTime
- scheduleDays

scheduleDays is stored as a comma-separated set of weekday numbers (Monday=1 through Saturday=6, Sunday=0). The UI displays rule value "1" as Forbidden and other values as Available.

The UI saves the entire rule array through cmd 385, then applies the filter. Because cmd 391 is a write that enables the feature, discovery must not call it automatically.

The authenticated read-only discovery utility now probes only cmd 397 GET and cmd 385 GET/getfun=true. If cmd 385 returns datas on the tested MTN firmware, FlyX Control can consider scheduling/pause controls after preserving existing rules and verifying exact enforcement semantics.


## Fifth authenticated discovery

The exact read-only Parent Control probes were tested on the MTN firmware:

- cmd 397 GET authenticated successfully but returned only success/cmd/message;
- cmd 385 GET with getfun=true authenticated successfully but returned only success/cmd/message;
- no datas rule array was exposed.

Therefore Parent Control scheduling is not readable while the feature is in its current state, and FlyX Control must not write or replace any rule list yet.

The stock Parent Control manager itself calls cmd 391 POST with enable="1" when that manager mounts, before it starts reading devices/rules. This strongly suggests the MTN firmware may only expose cmd 385 rule data after Parent Control has first been enabled. That is now the boundary between read-only discovery and a configuration-changing test.

No automatic discovery script should cross that boundary. A future test of cmd 391 must require explicit user consent, preserve any returned/current rules, and use the stock UI behavior as the reference.


## Sixth authenticated discovery

After opening the stock Parent Control page in the MTN web UI, the same read-only probes were repeated.

Result:

- cmd 397 GET still returned only success/cmd/message;
- cmd 385 GET with getfun=true still returned only success/cmd/message;
- no datas array became readable.

So merely opening the stock Parent Control page is not enough to expose the rule list on this firmware/account. Either cmd 391 is being refused/ignored, or the firmware only materializes Parent Control state after at least one device rule has been created.

Do not infer successful enablement from the frontend code alone. The next useful test should be performed through the stock UI on a non-critical test device, then followed by read-only discovery to see whether cmd 385 begins returning the rule array.


## Seventh authenticated discovery

After creating one Kids Manage rule through the stock MTN Parent Control UI, cmd 385 became readable.

The read-only probe returned exactly one rule with:

- enableRule=true
- the managed device LAN IP
- startTime=22:00
- endTime=23:00
- scheduleDays=3 (Wednesday)

This confirms that Parent Control state is materialized only after at least one device rule is created on this firmware/account. The rule list is IP-based, not MAC-based.

The cmd 385 response also included write/session metadata. Discovery reports must redact session IDs and write tokens; the sanitizer has been updated accordingly.

Do not enable app-side writes yet. First verify the enforcement meaning of the schedule window on the test device (whether the listed period is blocked or allowed), then test a harmless edit/remove through the stock UI and confirm cmd 385 readback. Once semantics are verified, the app can preserve and edit the full datas array safely.


## Parent Control enforcement semantics

A controlled stock-UI test was performed with one Pixel device scheduled for Wednesday 22:00-23:00.

Observed behavior at 22:00: the router disconnected the managed phone from the router/Wi-Fi rather than merely leaving it associated with no internet access.

This establishes that, on the tested MTN X17U firmware, an enabled Kids Manage schedule represents a forbidden/block period and enforcement can remove the client association during that window.

Still verify recovery behavior at the end of the window: whether the client reconnects automatically at 23:00 or requires a manual reconnect. FlyX Control should not describe the feature as a simple bandwidth pause until that recovery behavior is confirmed.


## Eighth authenticated discovery: active scheduled block

A read-only report was captured while the Pixel test rule was actively inside its Wednesday 22:00-23:00 forbidden window.

Findings:

- cmd 385 remained readable and continued to expose the same enabled rule;
- the router's DHCP/client source (cmd 223) still listed the Pixel;
- the 5 GHz association source (cmd 225) also still listed the Pixel and reported RSSI;
- therefore the device-list and Wi-Fi-association APIs can remain populated while Parent Control is actively preventing the client from using the router.

Do not infer Parent Control enforcement from a device disappearing from cmd 223/225. The canonical blocked/scheduled state must come from cmd 385 plus the current local time/day, while actual reconnect/disconnect behavior should be treated as an observed client effect.

Recovery at the schedule end still needs verification. In particular, confirm whether the client reconnects automatically after 23:00 or requires manual reconnection.


## Parent Control recovery behavior

The Pixel test rule remained configured for Wednesday 22:00-23:00. The phone was observed disconnected during the forbidden window and, by 03:00 after the window had ended, it had reconnected to the router automatically without manual intervention.

This confirms automatic recovery after a scheduled Parent Control block on the tested MTN X17U firmware. The exact reconnect minute was not observed, so do not claim that recovery occurs precisely at the configured end time without a tighter test.

The remaining write-semantics checks are:

1. disable an existing rule and confirm cmd 385 returns enableRule=false while the device remains usable;
2. edit the time/day and confirm cmd 385 readback exactly matches the change;
3. delete the rule and confirm it disappears from cmd 385 without affecting unrelated devices.

After those checks, app-side Parent Control schedule editing can be implemented while preserving the full existing datas array.


## Tenth authenticated discovery: disabled rule semantics and firmware change

With the existing Pixel Parent Control rule switched from Enable to Disable in the stock MTN UI, cmd 385 continued to return the same stored rule but with enableRule=false. The IP, 22:00-23:00 window and Wednesday schedule value remained unchanged.

This confirms that disabling a Parent Control rule is non-destructive: the schedule persists and can be re-enabled later. FlyX Control can therefore model schedule enable/disable separately from rule deletion.

The same report also identified router firmware 4.2.3 with a newer 2026-07-18 build and a short router uptime, whereas earlier discovery reports identified firmware 4.1.34. Treat 4.2.3 as the current tested baseline, but do not infer the cause of the firmware/reboot change from discovery alone.


## Eleventh authenticated discovery: rule edit semantics

With the existing Pixel Parent Control rule left disabled, the stock MTN UI was used to edit only the schedule from Wednesday 22:00-23:00 to Thursday 04:00-05:00.

The subsequent cmd 385 readback preserved enableRule=false and returned startTime=04:00, endTime=05:00 and scheduleDays=4.

This confirms that Parent Control rule edits are persisted independently from the enable/disable state. Thursday is represented as weekday value 4 on this firmware.

The final stock-UI lifecycle test is deletion: remove the disabled Pixel rule, then confirm cmd 385 no longer returns that rule and that no unrelated device state is changed.


## Twelfth authenticated discovery: deletion test not yet performed

The report still showed the disabled Pixel rule because the rule had not actually been deleted in the stock MTN UI before the discovery run.

No deletion behavior should be inferred from this report.

The next step is to delete the Pixel rule in the stock UI and rerun the read-only discovery to observe how cmd 385 represents an empty Parent Control rule set.


## Thirteenth authenticated discovery: deletion semantics confirmed

After deleting the final Pixel Parent Control rule through the stock MTN UI, cmd 385 returned an explicit empty rule list:

- datas=[]
- success=true

The discovery utility reported parent_control_rules_readable=true and parent_control_rule_count=0.

This confirms the complete stock-UI rule lifecycle on the tested firmware:

- create: a rule appears in cmd 385;
- disable: the same rule remains stored with enableRule=false;
- edit: time/day values update in place while enable state is preserved;
- delete: the final rule is represented as an explicit empty datas array.

App-side deletion can therefore model "remove the selected rule from the full datas array"; when deleting the final rule, the expected saved/read-back state is datas=[].

The remaining prerequisite before FlyX Control performs Parent Control writes itself is to identify and mirror the stock UI's post-save applyFileter request exactly, including its command ID and transport encoding. Until that is verified, writes remain disabled.


## Stock UI v0.6: Parent Control apply command and transport

The refreshed stock frontend scan resolved the remaining Parent Control apply step.

Exact wrappers in the stock UI:

- getParentControlRight: cmd 385, method GET, getfun=true;
- setParentControlRight: cmd 385, method POST;
- setParentControlMode: cmd 391, method POST, enable="1";
- applyFileter: cmd 20, method POST.

The Kids Management save flow writes the complete datas array through cmd 385 and, on success, immediately calls applyFileter(). Deletion uses the same sequence and includes success=true in the payload before saving the shortened/full-empty datas array.

The bundled Axios request transform serializes object payloads as JSON and sets application/json;charset=utf-8. This is consistent with the JSON transport already used successfully by the discovery tooling.

Parent Control's stock-UI lifecycle and apply command are therefore mapped. App-side writes should still pass one reversible test using FlyX Control's own request code before the production UI enables schedule editing. The test must use a disabled rule, preserve the original datas array, apply cmd 20 after cmd 385, verify readback, and restore the original rules even if verification fails.


## Reversible app-side Parent Control write test

The dedicated FlyX Control write-path test completed successfully against the real router with no pre-existing Parent Control rules.

Observed result:

- the temporary rule was created as disabled;
- cmd 385 save succeeded;
- cmd 20 apply succeeded;
- cmd 385 readback matched the temporary rule;
- cleanup restored the original empty rule list;
- cmd 20 apply after cleanup succeeded;
- final readback matched the original state exactly.

This verifies FlyX Control's own JSON write transport, cmd 233 write-token flow, cmd 385 Parent Control save, cmd 20 apply, readback verification, and exact rollback path on the tested firmware.

Production schedule controls can now use the same pattern: preserve the full rule list, resolve the device's current LAN IP, save cmd 385, apply cmd 20, verify cmd 385 readback, and roll back on mismatch.


## Android beta: Parent Control verified in the real app

The first Android beta was installed on a real phone and connected successfully to the MTN FlyX router.

Verified through FlyX Control itself:

- create a Parent Control schedule;
- read the created schedule back in the app;
- disable the schedule;
- delete the schedule.

An initial follow-up action exposed an expired router session: cmd 223 returned NO_AUTH before the schedule write. FlyX Control was updated to detect NO_AUTH, reauthenticate once with the stored router credentials, and retry the failed authenticated command. After that change, disable and delete both succeeded from the app.

This confirms the Android app's end-to-end Parent Control path for create, disable and delete on the tested firmware, including automatic session recovery during later actions.

Remaining app-side Parent Control checks:

- edit an existing schedule and verify readback;
- enable a disabled schedule for a short future window;
- confirm router enforcement and automatic recovery after the window;
- verify the app's displayed "currently blocked" state against router time before relying on phone-local time.


## Minute-level Parent Control schedules

The stock MTN Parent Control interface exposes whole-hour choices, but cmd 385 stores schedule times as HH:MM strings. FlyX Control's schedule model and router write path already preserve minute values exactly.

The Android beta editor now allows exact-minute start and end times, for example 06:00-06:10. The app still performs exact cmd 385 readback verification after saving, so a firmware that rejects or normalizes minute-level values will cause the change to fail verification rather than silently being accepted.

Minute-level storage on the tested firmware should be considered beta until one disabled rule with a non-zero minute value is saved and read back successfully from the real router.


## Android beta: minute-level enforcement confirmed

A minute-level Parent Control schedule created from FlyX Control was accepted by the router and entered its active blocked window successfully. This confirms that the tested firmware does not merely store non-zero minute values: it enforces them.

The managed phone then regained access automatically when the minute-level end time was reached. This confirms end-to-end minute-level schedule behavior on the tested firmware: exact-minute start, exact-minute enforcement window, and automatic recovery at the configured end time.


## Stock UI MAC filter mapping

The stock MTN frontend exposes a separate Filtering Rules / MAC Filter path that is distinct from Parent Control.

Confirmed frontend wrappers and behavior:

- getMACData: cmd 23 GET with getfun=true;
- setMACData: cmd 23 POST with the complete datas array;
- getIPFilterMode: cmd 28 GET;
- setIPFilterMode: cmd 28 POST;
- setMACMode: cmd 30 POST;
- applyFilter: cmd 20 POST after a successful rule save.

The global UI mode labels are Whitelist=0 and Blacklist=1. When Blacklist is selected, the frontend writes mode rows with acceptAll=true for both IPV4 and IPV6. When Whitelist is selected, acceptAll=false.

MAC rule objects include at least:

- enableRule;
- enableLink;
- ippro;
- mac;
- remark.

The stock UI sets enableLink=false for newly added MAC rules while in Blacklist mode, and enableLink=true while in Whitelist mode.

The current router reports still return no readable datas array for cmd 23/28/30 while no MAC-filter rules have been configured. This may be another materialized-state behavior similar to Parent Control, but that is not yet verified.

Do not enable FlyX Control's generic Block/Unblock path from this mapping alone. The safe next test is through the stock MTN Filtering Rules UI using a deliberately nonexistent MAC address in confirmed Blacklist mode, followed by read-only cmd 23/28/30 discovery. This avoids disconnecting a real client while determining whether the firmware begins exposing readable filter state after the first rule is created.


## Wi-Fi MAC blacklist path (cmd 278)

The stock MTN Wi-Fi device page exposes a more direct per-band MAC filter than the generic Filtering Rules page.

Confirmed stock-UI behavior:

- cmd 278 GET/POST;
- subcmd "0" = 5 GHz;
- subcmd "1" = 2.4 GHz;
- datas.macfilter is one of "close", "deny" or "allow";
- datas.maclist is the MAC list;
- "deny" is the stock UI's Black List mode;
- "allow" is the stock UI's White List mode;
- the Wi-Fi UI saves cmd 278 directly and then reads cmd 278 back; it does not call cmd 20 for this path.

This is a better candidate for instant Block/Unblock than the generic cmd 23/28/30 path, because it is the exact blacklist used from the connected-device Wi-Fi page.

A reversible verification tool tested both bands using only a dummy locally administered MAC, confirmed readback, and restored the original state. That live test has now passed, so production Block/Unblock can use this path with readback verification and rollback safeguards.


## Reversible Wi-Fi MAC blacklist test passed

The dummy-MAC verification completed successfully on the real router for both Wi-Fi bands.

Observed result:

- 5 GHz subcmd "0": original state was closed/empty, temporary deny rule was confirmed by readback, and cleanup restored the original semantic state;
- 2.4 GHz subcmd "1": original state was closed/empty, temporary deny rule was confirmed by readback, and cleanup restored the original semantic state;
- overall verification: true;
- overall restoration: true.

This confirms the stock cmd 278 deny-list path is writable, readable after materialization, reversible, and suitable for FlyX Control's instant Block/Unblock feature on the tested firmware.

Production blocking therefore uses cmd 278 on both bands, preserves existing entries, refuses whitelist mode, verifies readback after every write, and attempts rollback if either band does not match the intended state.


## Android beta: Instant Block / Unblock verified end to end

The production FlyX Control Android beta has now been tested successfully against a real connected Wi-Fi device.

Confirmed through the app:

- friendly-name dialog Cancel works without a Flutter assertion;
- friendly-name Save works without a Flutter assertion;
- Instant Block successfully denies the selected device's network access;
- the blocked device remains represented in FlyX Control's Blocked view;
- Instant Unblock successfully restores access.

This confirms the complete app-side cmd 278 lifecycle on the tested firmware: device selection, both-band deny-list write, readback verification, blocked-state persistence in the app, and unblock restoration.

Instant Block / Unblock is therefore considered complete for the v0.1 beta on the tested MTN X17U firmware.


## Per-device traffic probe: no byte counters exposed

A read-only idle-vs-active traffic probe was run against a real connected 5 GHz client.

Observed:

- cmd 223 continued to report flow=0 during both idle and active traffic;
- cmd 355 returned no usable per-device data;
- cmd 402 mirrored the DHCP-style row when parseable and still reported flow=0;
- cmd 225 changed txrate from 0/2 to 31 during active traffic while rxrate remained 0, and RSSI also moved.

Conclusion:

- no verified per-device byte counter was exposed by cmds 223, 225, 355 or 402 in this test;
- cmd 225 txrate is useful only as a Wi-Fi association/link-rate activity signal and must not be presented as Internet throughput or data usage;
- per-device daily/weekly/monthly usage cannot be derived honestly from these fields.

The next discovery step is to identify the stock firmware's Speed Limit/QoS command path and any hidden per-client accounting table before implementing quotas or true live Internet speed.


## Stock UI traffic/speed-limit search: no per-device control path found

UI inspector v0.7 scanned the stock MTN frontend, its routed chunks, and API wrapper names for speed, traffic, quota, usage and QoS paths.

Findings:

- the firewall route table contains filter rules, port forwarding, URL filtering, DMZ, UPnP, IP/MAC binding, DDOS and access control, but no Speed Limit route;
- app.js still contains generic vendor translation strings such as Speed Limit, LAN Speed Limit, WAN Speed Limit, downlinkSpeedLimit and uplinkSpeedLimit;
- no fetched routed chunk ties those strings to a usable per-device speed-limit implementation;
- the only traffic-like API wrappers discovered are getFlow/setFlow on cmd 337 and getFlowN/setFlowN on cmd 355;
- cmd 337 is already confirmed as whole-router monthly flow/quota state;
- cmd 355 has returned no usable per-device data on the tested firmware.

Conclusion: the stock UI bundle carries dormant/generic speed-limit labels, but this MTN firmware does not expose a routed per-device Speed Limit/QoS control path or a verified per-device byte-accounting API. FlyX Control must not present Wi-Fi txrate/rxrate as Internet throughput or fabricate per-device data usage from them.

The same inspection also identified getDeviceTime on cmd 11. That is a separate useful read path for aligning Parent Control status with the router's own clock once its response shape is verified.

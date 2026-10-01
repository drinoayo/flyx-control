# Android beta test checklist

Use this checklist for the first real-device FlyX Control beta.

## Install and launch

- Install the latest debug APK on an Android phone.
- Confirm the app launches without crashing.
- Confirm dark theme, navigation and device screens render correctly.
- Confirm the router connection screen accepts the local router address, username and password.
- Confirm credentials are restored after closing and reopening the app.

## Read-only router checks

- Connect while the phone is on the FlyX Wi-Fi.
- Confirm carrier/network type and signal values populate.
- Confirm WAN download/upload activity updates.
- Confirm router uptime and monthly usage populate.
- Confirm CPU, temperature, memory and firmware appear when exposed.
- Confirm connected devices match the router's active device list.
- Confirm Wi-Fi RSSI/link-rate values are labelled as link information, not internet speed.

## Parent Control smoke test

Use a non-critical connected device.

1. Add a disabled schedule.
2. Refresh and confirm it is still present.
3. Edit the time/day while it remains disabled.
4. Enable it only for a short future blocked window.
5. Confirm the target device is denied access during the window.
6. Confirm the device can recover after the window.
7. Disable the rule from FlyX Control.
8. Delete the rule from FlyX Control.
9. Open the stock MTN UI and confirm the final Parent Control state matches.

If any save fails, stop additional writes until the app's error message and stock MTN Parent Control state are compared.

## Safety checks

- Do not test on the only device being used to manage the router.
- Do not interpret cmd 223/225 presence as proof that a scheduled block is inactive.
- Do not test generic Block/Unblock yet; that path remains capability-gated.
- Do not enable per-device quota enforcement; per-device byte accounting remains unverified.

## Report back

For any issue, note:

- screen/action;
- what was expected;
- what actually happened;
- whether the stock MTN UI agrees with FlyX Control;
- screenshot if it is a visual issue.

Do not include router passwords, session IDs, write tokens, IMEI/IMSI, serial numbers or private identifiers in screenshots or reports.

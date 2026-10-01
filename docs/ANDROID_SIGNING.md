# FlyX Control Android signing

FlyX Control uses one permanent owner-held Android signing key for release APKs.

The keystore and its passwords are intentionally **not stored in this public repository**. CI produces an unsigned release APK. The final release is signed outside the repository with the permanent FlyX Control key.

## Rules

- Never commit a `.jks`, `.keystore`, `key.properties`, or signing password.
- Keep at least two secure backups of the permanent FlyX Control keystore and credentials.
- Every future public/release APK must use the same signing key.
- Increase the Android version code for each future release.
- Debug/test APKs may use temporary debug signing, but they cannot update an installed permanent release if the signatures differ.

## CI

The Flutter workflow:

1. Generates the Android scaffold.
2. Applies FlyX router networking and widget patches.
3. Runs analyze and tests.
4. Builds the debug APK.
5. Builds an **unsigned release APK** for owner signing.

The unsigned release artifact must not be distributed as the final app.

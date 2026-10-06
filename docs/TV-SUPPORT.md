# WAVEBREAK TV

Status (2026-10-06): Android TV source and a local preview build workflow are
implemented. The owner's build log confirms TV analysis passed with no issues;
The corrected fixture passed: all 144 tests are green in the owner's second log.
An APK compiled, but final validation correctly rejected its phone package ID:
the environment-based native TV flag had not applied. The workflow now passes
`--dart-define=WAVEBREAK_TV=true`, decodes Flutter's explicit `dart-defines` Gradle
property and checks it agrees with `main_tv.dart` before configuring the build.
Compilation with the corrected native TV configuration and real-device VPN
traffic are **not yet verified**.
No TV APK has been delivered or published. These changes are not yet
committed/pushed: this Codex environment cannot write the repository Git index.

## Android TV / Google TV / Android-based Fire TV

The TV entry point is `wavebreak-mobile/lib/main_tv.dart`. It shares the phone's
Core API, secure session storage, installation identity, subscription checks,
personal server catalogue, connection manager and native Xray/Hysteria2 engines.
There is no separate backend or shared subscription credential.

The preview uses package `com.wavebreak.wavebreak.tv`, independently of the phone
package. It has a landscape activity, Leanback launcher, 320x180 banner, optional
touch/camera features, large focusable controls, directional navigation and OK/
Select handling. Signing out stops the VPN using the existing session service.
Reopening/resuming reconciles state with the native VPN service. Back returns to
the main page; leaving the app does not disconnect the VPN.

Supported UI paths: password login, emailed login code, email verification,
personal servers including protocol variants, VPN connect/cancel/disconnect,
refresh, account identity, subscription name, language, confirmed sign-out.
Create an account/manage the subscription in the existing mobile or PC client.
TV QR/device-code pairing, custom subscriptions, billing, advanced routing and
a TV update channel are not implemented. The phone's background update channel
is disabled for TV to avoid offering a phone package.

The current minimum Android version remains API 25. The universal preview
includes ARM32, ARM64 and x86-64; manufacturer-specific hardware/OS behaviour is
not guaranteed by including those architectures. Android-based Fire TV needs
separate testing; Vega OS is not Android and cannot use this APK.

## Local preview build

Read `CLAUDE.md`, `docs/BUILD-MACHINE-SETUP.md` and the release skill first.
Synchronize `app-main-sync`. Preserve unrelated work. The TV workflow is for
local previews, permits uncommitted source changes and records their status; it
does not modify mobile version numbers, stage files on servers or publish.

From Git Bash:

```bash
tools/release/release.sh build-tv -BuildNumber 1
```

The same implementation can be invoked from PowerShell:

```powershell
& C:\wavebreak\tools\release\tv.ps1 -BuildNumber 1
```

Flutter defaults to `C:\src\flutter\bin\flutter.bat`; pass `-Flutter` to override.
Use the machine's configured JDK 17 (`JAVA_HOME`) and Android SDK. The script
checks source branch/reference, signing files, native bridge ABIs, runs analysis
and the full Flutter test suite, builds with real Core and VPN definitions, then
verifies the release certificate, TV package, Leanback entry, runtime libraries
and production Core address. Any failure prevents delivery. TV native packaging
is selected only by the explicit TV build definition paired with the TV entry
point; ordinary phone builds keep their existing package/manifest.

Output: `.artifacts/tv/wavebreak-tv-<version>-<build>-preview.apk` and a JSON
manifest with the base commit, source status, checksum and `deviceVerified:false`.
An existing output is never overwritten: increment `-BuildNumber`.
The preview version name follows the mobile source version so Core's existing
minimum-client-version check remains meaningful. The separate TV package has
its own build codes; establish a TV release registry/update channel before
public distribution. A first TV release cannot have a previous TV rollback.

## Verification on a television

1. Install the preview with `adb install <apk>`, open it from the TV launcher.
2. With the remote only: enter email/password or email code, navigate all pages,
   choose a country/protocol, confirm/cancel VPN permission, connect/disconnect.
3. Confirm traffic through the VPN from an actual streaming app and verify the
   egress address; a running VPN service alone does not prove working traffic.
4. Test Direct, REALITY, XHTTP and Hysteria2 on the applicable personal servers,
   including a blocked transport and expired subscription. No demo endpoints.
5. Switch Wi-Fi/Ethernet, sleep/wake, leave/reopen the UI, stop/restart the process,
   switch server while connected, and sign out. Check permission refusal too.
6. Run on a physical ARM32 TV, an ARM64 TV and an Android-based Fire TV. Test
   directional/Select/Back keys and on-screen keyboard for each manufacturer.

## Coverage beyond Android

| Platform | Required implementation | Current status |
| --- | --- | --- |
| Android TV / Google TV | Dedicated UI + existing VpnService | Source implemented, unverified preview workflow |
| Android-based Fire TV | Same APK + Amazon device validation | Not tested |
| LG webOS | Confirm manufacturer system-tunnel access, or use network gateway | No app/tunnel implemented |
| Samsung Tizen | Confirm manufacturer system-tunnel access, or use network gateway | No app/tunnel implemented |
| Apple TV tvOS | Native Network Extension and Apple build/signing toolchain | Not implemented |
| Amazon Vega OS | Separate Amazon SDK and VPN integration | Not implemented |
| Roku, VIDAA, Saphi, older proprietary TV systems | Model-specific SDK investigation; gateway fallback | Not implemented |

Smart TV is a category, not one OS. A webOS/Tizen UI cannot be represented as
a working system VPN merely because it reaches Core. The public TV APIs reviewed
do not establish an available third-party system-tunnel mechanism. This is a
feasibility conclusion, not proof that no privileged manufacturer partnership
is possible. A home VPN router/gateway can carry a closed TV's traffic; a TV
controller would still require a real gateway implementation and authentication.
Do not treat Smart DNS or an in-app HTTP proxy as a full-TV VPN.

Relevant primary documentation:

- Android TV: https://developer.android.com/training/tv/get-started/create
- Android VPN: https://developer.android.com/develop/connectivity/vpn
- LG services: https://webostv.developer.lge.com/develop/guides/js-service-basics
- Samsung TV APIs: https://developer.samsung.com/smarttv/develop/api-references/tizen-web-device-api-references.html
- Apple Network Extension: https://developer.apple.com/documentation/networkextension
- Amazon Vega: https://www.developer.amazon.com/docs/vega/0.24/vega-get-started

The owner has been asked which closed-OS approach to pursue. That choice remains
open. Backend/server deployments and store publication are not part of this
preview and have not been performed.

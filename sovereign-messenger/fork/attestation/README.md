# Contact-scoped local attestation alpha

This directory embeds a narrowly modified copy of GrapheneOS Auditor as a non-exported Android
library activity. It is a **local, two-device QR experiment**, not a production identity proof and
not a replacement for SimpleX end-to-end security-code verification.

## Reproducible source preparation

The input is pinned in [`SOURCE.lock`](SOURCE.lock): GrapheneOS Auditor commit
`252f6a11e0cc25c70264f223fab95044c001fef3`, tree
`ffd1d53243d5950fea75882920829691094bb3a4`, MIT license. The preparation script verifies both Git
objects, the upstream Gradle wrapper JAR SHA-256, and the wrapper's Gradle distribution SHA-256
before applying the reviewed patch and library overlay.

```sh
bash prepare-auditor.sh
./gradlew :smoke:assembleDebug
```

Prerequisites are Git, Java 17, Android SDK 36 with Build Tools 36.1.0, and network access for the
pinned clone and first dependency resolution. No APK is committed here. A successful local smoke
build produces `smoke/build/outputs/apk/debug/smoke-debug.apk`; verify that path rather than assuming
it exists. The preparation step is idempotent and refuses an unknown or locally altered vendor
checkout.

The wrapper and dependency verification metadata come from the same pinned Auditor commit. The
wrapper pins Gradle 9.6.1 and its distribution SHA-256. A release must be built from a reviewed,
clean checkout and signed offline; never put signing keys or passwords in this directory, Git, CI
variables exposed to untrusted jobs, or chat.

## Scope and API

`SovereignAuditorAlpha` exposes:

- `generateScopeToken()` — 32 cryptographically random bytes;
- `createIntent(context, scopeToken)` — launches the non-exported QR activity;
- `readStatus(context, scopeToken)` — returns `NONE`, `VERIFIED_BASIC`, `VERIFIED_STRONG`, or
  `REJECTED`, plus a wall-clock timestamp;
- `clearStatus(context, scopeToken)` and `Status.isFresh(maximumAgeMillis)`.

The caller must generate one opaque 32-byte token per contact and persist it in the authoritative
SimpleX core database. It must not pass a raw contact ID, phone number, username, address, or an
unsalted hash of any identifier. The new Android cache stores only `SHA-256(scopeToken)`, the enum
verdict, and its timestamp in app-private preferences. It stores no raw token, SimpleX identifier,
QR evidence, or certificate chain.

The smoke app persists one random demo token only to exercise this API. It is not a contact model.

On the **auditor** device, a successful initial/stateless verification records `VERIFIED_BASIC`; a
successful paired subsequent verification records `VERIFIED_STRONG`; a parser or cryptographic
verification failure records `REJECTED`. The auditee device does not receive that result. Mutual
device attestation therefore requires a separate run in the opposite direction.

## SimpleX integration contract

The Android KMP actual should launch the intent only from the selected contact's view and map the
cached status through the existing `SovereignAttestationProvider` abstraction. `scopeToken` belongs
in a new encrypted/core database field, not Compose state or plain contact preferences. Clear it
and the cached result on contact deletion, security-code reset, database restore, policy change, or
app signing identity change. Treat timestamps older than the product's short policy window (for
example 24 hours in an alpha) as stale.

Do not show these results as `Contact.verified`. Until the SimpleX security code is independently
verified, render even a fresh `VERIFIED_STRONG` result as a separate yellow/local-device signal.
This alpha has no protocol message, no remote attestation service, no key-transparency binding, and
no binding to the SimpleX ratchet transcript, contact security-code digest, or a challenge delivered
inside that verified E2EE channel.

The supplied integration overlay implements that limited Android path for the existing Sovereign UI
alpha. Apply the UI overlay first, prepare Auditor, then install this provider:

```sh
bash ../apply.sh /path/to/simplex-chat-v7.0.0
bash prepare-auditor.sh
bash integrate-simplex.sh /path/to/simplex-chat-v7.0.0
cd /path/to/simplex-chat-v7.0.0/apps/multiplatform
./gradlew \
  -PsovereignAuditorModuleDir=/absolute/path/to/fork/attestation/vendor/Auditor/app \
  :android:assembleDebug
```

The build patch adds `:auditor-alpha`, the Android-source-set dependency, compile SDK 36, AGP 8.9.1
and a consistent JVM 17 target for the host and Auditor. This Pixel/GrapheneOS alpha deliberately
sets min SDK 34: Java records are native from Android 14, and older platform releases are outside
its supported security profile.

Until the core database owns a random token, the Android actual derives a stable 32-byte scope token
as `HMAC-SHA-256(domain || contactId)` using a non-exportable Android Keystore key. The key must be
StrongBox-backed: the provider checks `KeyInfo.securityLevel == SECURITY_LEVEL_STRONGBOX` and has no
TEE/software fallback. Missing StrongBox, key creation failure, an existing wrong-security-level
alias, or any HMAC error fail closed as `NOT_CONFIGURED / KEY_UNAVAILABLE`, without logging the
contact ID or error text. `setUnlockedDeviceRequired(true)` is enforced.

The provider refreshes its in-memory Compose states when the main activity resumes. Results older
than 24 hours, future-dated results after wall-clock rollback, and corrupt/missing cache entries do
not verify. `VERIFIED_LOCAL_BASIC` and `VERIFIED_LOCAL_STRONG` are separate yellow/local states and
both retain the blocker `ATTESTATION_NOT_BOUND_TO_CONTACT`; only a future ratchet-bound provider may
emit the existing green `VERIFIED` state.

## Security properties and limits

The patch keeps Auditor's fresh challenge/response QR protocol and GrapheneOS/Android Key
Attestation validation, while additionally requiring GrapheneOS verified boot, a StrongBox
attestation security level, and the peer attestation to name the exact same host APK package, single
signing certificate, and version code as the local host APK. Stock Pixel OS, a TEE/software
attestation, two debug APKs signed by different debug keys, or two otherwise valid releases at
different version codes intentionally fail.

Important limits:

- A scope token selects where the local result is cached; it does **not** cryptographically prove
  that the scanned phone belongs to that SimpleX contact. Scanning the wrong valid phone can write a
  valid result into the selected scope.
- Android Key Attestation measures a device/key state at verification time. It proves neither human
  identity nor absence of compromise before or after that instant.
- The policy, supported-device list, trust roots, patch and dependencies are frozen at the pinned
  commit. There is no automatic revocation/policy update path in this embedded local-only alpha.
- The embedded activity is non-exported and remote verification/sample submission are hidden, but
  this is not an audit of every upstream code path or dependency.
- The new per-contact cache stores no certificates. Auditor's existing paired-verification engine,
  however, persists its own pinned pairing certificate chain in app-private preferences. If the
  requirement is literally “no certificate persistence anywhere,” disable paired/strong mode and
  expose only stateless `VERIFIED_BASIC`; strong continuity cannot be claimed without remembered
  peer trust state.
- The host is part of the trusted computing base. A compromised verifier app/process can forge its
  own local cache and UI.
- The integrated alpha requires Android 14 (API 34) or newer and both Auditor activities are
  non-exported. It must still be tested on every supported Pixel/GrapheneOS release; raising the
  installation floor does not prove runtime safety.

Before any production use, bind a fresh challenge to the already verified SimpleX security-code
digest and transcript, persist authoritative state transactionally in the core database, add
capability/version negotiation, pin and update GrapheneOS policy through a reviewed process, add
anti-rollback and restore handling, fuzz every decoder, and obtain independent Android,
cryptographic, privacy, and supply-chain audits.

## Upstream references and license

- [GrapheneOS Auditor source](https://github.com/GrapheneOS/Auditor)
- [GrapheneOS attestation documentation](https://grapheneos.org/articles/attestation-compatibility-guide)
- [Android Key Attestation](https://developer.android.com/privacy-and-security/security-key-attestation)

The vendored Auditor source remains MIT-licensed under its upstream `LICENSE`. Preserve its license
and copyright notices in source distributions and binary notices. This integration patch does not
change that upstream license.

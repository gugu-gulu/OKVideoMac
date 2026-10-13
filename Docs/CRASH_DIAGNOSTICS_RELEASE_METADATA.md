# Crash diagnostics release metadata

This inventory describes static SDKs linked into the App executable. They are logical SBOM components and do not add independent Mach-O paths. The existing exact Mach-O inventory and main-executable signature/hash boundary remain in force.

| Component | Version | Upstream commit | License |
| --- | --- | --- | --- |
| PLCrashReporter | 1.12.2 | `0254f941c646b1ed17b243654723d0f071e990d0` | `MIT AND Apache-2.0` |
| Sentry | 9.30.1 | `4f135c52afeeb1d6937eb93824c7ec1cddcaa372` | `MIT` |

Both bundled SDK license resources were byte-compared with the license from the exact upstream source archive. PLCrashReporter includes MIT and Apache-2.0 portions; the aggregate legal payload retains its complete notice and the existing full Apache-2.0 text. Sentry uses the official binary distribution whose SHA-256 is locked in Package.swift and the dependency lock. No upstream SDK source was modified.

The corresponding archives are included in the checksum-bound third-party source release. The source release lock fixes the archives by SHA-256 and the dependency lock records the exact source commits. This does not claim a bit-for-bit rebuild of the official Sentry binary.

SPDX and CycloneDX contain both static SDK components with versions, license expressions, package URLs and source revisions. The verifier rejects omitted/duplicate components, conflicting versions, mismatched license metadata and missing/changed shipped notices. Static SDK records do not carry the outer-signed main executable checksum.

External Sentry evidence from Stage 7 belongs to its recorded acceptance UUIDs. Final Release dSYMs and their source state must be verified against the exact final bundle separately; no new upload or source upload is authorized by this metadata change.

## Xcode static framework resource stubs

Xcode retains each static SDK's privacy manifest in a framework resource container and emits a resource-only Mach-O stub. Both stubs have a zero-byte __text section and no defined global symbols; the App executable contains the actual SDK classes and has no dynamic load reference to these frameworks. Preserve the containers and their PrivacyInfo.xcprivacy files.

The two exact approved paths are Contents/Frameworks/CrashReporter.framework/Versions/A/CrashReporter and Contents/Frameworks/Sentry.framework/Versions/A/Sentry. Their physical SBOM entries are explicitly marked resource-only; the logical static SDK records remain separate. Before signing, normalize their generated temporary LC_ID_DYLIB paths to the corresponding @rpath identity. The normalizer rejects actual code, unexpected dependencies, a dynamic App load reference or a missing privacy file, and verifies privacy bytes remain unchanged.

Apple's privacy manifest placement guidance: https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk

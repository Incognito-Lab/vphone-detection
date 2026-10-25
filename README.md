# vphone-detection

**App-visible vPhone detection indicators**

An educational reference for developers studying how an ordinary iOS device-binary app can recognize vPhone through exact system markers and compare supporting device capabilities. It covers the Standard and Experimental vPhone presets as distinct from Xcode Simulator, and includes measured results from a physical iPhone reference.

> **Tested with [vPhone Core Bundle 2.12.0](https://github.com/Lakr233/vphone-cli/releases/tag/2.12.0)** on 2026-10-25. Both tested VMs are bound to this bundle. Later releases and other guest configurations need retesting. A result with no exact markers is provisional; it does not prove that a device is physical.

The tested guests exposed exact vPhone files, an injected hook, a paravirtual Metal device name, and preset-specific hypervisor sysctl OIDs. The Experimental preset masked the Standard preset's obvious model and board strings while leaving the other exact markers visible. CPU, memory, sensors, cameras, and GPU families are supporting checks that need context for the claimed model and OS.

**🧭 Navigation:** [🔎 Measured markers](#strong-positive-markers-measured-comparison) · [📊 Supporting measurements](#supporting-consistency-checks-measured-comparison) · [⚖️ Interpretation](#how-to-interpret-the-groups) · [🧭 Provisional conclusion rule](#app-conclusion-rule) · [🧪 Collection method and limitations](#collection-method-and-limitations) · [💻 Swift examples](#swift-examples-for-each-retained-indicator) · [🧩 Sample app](#optional-sample-app) · [📄 Example reports](#example-reports) · [📁 Project files](#project-files) · [📚 References](#references)

<a id="strong-positive-markers-measured-comparison"></a>

## 🔎 Strong positive markers: measured comparison

| App-visible indicator | Standard preset | Experimental preset | Physical reference | Interpretation |
| --- | --- | --- | --- | --- |
| `kern.hv_vmm_present` | `1` | `ENOENT` | `0` | The positive Standard preset result is specific to this preset. |
| `kern.Xv_vmm_present` | `ENOENT` | `1` | `ENOENT` | Experimental preset moved the positive result to a renamed OID. Check both; absence of one is inconclusive. **Review risk:** undocumented OIDs. |
| `/usr/bin/vphoned` | Path entry exists | Path entry exists | `ENOENT` | Exact guest daemon path entry. |
| `/System/Library/LaunchDaemons/vphoned.plist` | Path entry exists | Path entry exists | `ENOENT` | Exact guest launch daemon path entry. |
| `/System/Library/Extensions/AppleParavirtGPUMetalIOGPUFamily.bundle` | Path entry exists | Path entry exists | `ENOENT` | Exact paravirtual GPU bundle path entry. |
| `/usr/lib/SystemHook-vphone.dylib` | Path entry exists | Path entry exists | `ENOENT` | Exact guest hook library path entry. |
| `DYLD_INSERT_LIBRARIES` contains vPhone hook | `/usr/lib/SystemHook-vphone.dylib` | Same | No vPhone path | A precise value in the app's own environment is stronger than the generic key. Launcher-controlled and hideable. |
| Metal default device name | `Apple Paravirtual device GPU` | Same | `Apple A11 GPU` | The exact paravirtual name is a strong positive for this build. A virtualizer can change the exposed name. |

<details>
<summary>📂 Path checks, symbolic links, and related research</summary>

The four path checks implement OWASP's [specific virtualization-engine file presence](https://mas.owasp.org/MASTG/knowledge/ios/MASVS-RESILIENCE/MASTG-KNOW-0135/#presence-of-specific-virtualization-engine-files) technique using **vPhone-specific** paths confirmed by the sandboxed app. OWASP's Corellium example paths describe a different product and are not evidence for these guests. `lstat` reports the final directory entry even if it is a dangling symbolic link; if an entry is a link, the app additionally uses `stat` to report whether its target resolves. Neither call opens file contents. An `ENOENT` result differs from an access denial, and a hidden or removed path defeats this local check. Metal also differs from OWASP's Corellium-specific “no Metal device” example: both vPhone guests exposed a Metal device.

</details>

The Standard preset's `iPhone99,11` and `VPHONE600AP` strings are additional exact positives for this snapshot. The tested Experimental VM reported plausible-looking `iPhone17,3` and `D47AP`; those strings alone did not reveal its virtual origin. They are measured values for this VM, not a model requirement for every Experimental guest. The installed 2.12.0 Experimental patch catalogue explicitly names `iPhone17,3` / `D47AP` identity rewrites, and this VM's creation log records `iPhone99,11` → `iPhone17,3`. VM creation accepts a `--device` option, but these observations do not show that the Experimental identity rewrite automatically follows an arbitrary selected model. The app places identity under supporting consistency, while counting an exact `iPhone99,11` or `VPHONE600AP` match as a Standard preset marker.

<a id="supporting-consistency-checks-measured-comparison"></a>

## 📊 Supporting consistency checks: measured comparison

| App-visible observation | Standard preset | Experimental preset | Physical reference | Use and limit |
| --- | --- | --- | --- | --- |
| `hw.machine` / `hw.model` | `iPhone99,11` / `VPHONE600AP` | `iPhone17,3` / `D47AP` in this VM | `iPhone10,6` / `D221AP` | Establish the identity claim and reveal Standard preset's synthetic names. A guest can rewrite both. |
| `hw.ncpu` | `6` | `6` | `6` | Supporting consistency. All three match, so it does not separate this sample. Compare to published core count for the claimed model. |
| `hw.cputype` | `16777228` | Same | Same | ARM64 Mach CPU type; broad ABI class, not a device whitelist. |
| `hw.cpusubtype` | `2` | `2` | `1` | ABI subtype differs here, but the devices and OS generations differ. Do not infer CPU features or virtualization from a raw subtype. |
| `hw.memsize` | `8565800960` bytes | Same | `2961539072` bytes | Different physical model and configurable guest memory. Compare exact bytes only with measured same-model/same-OS distributions. |
| Metal GPU families | Apple7 `false`, Common3 `true` | Same | Apple7 `false`, Common3 `false` | Family mismatch can support a claimed-model check. The older physical GPU is not a matched control. |
| CoreMotion availability | Accelerometer, gyro, magnetometer, device motion all `false` | Same | All `true` | Both guests lacked these capabilities in the tested configuration. Virtual sensors and OS behavior can change. |
| Two-second motion sample | **Unavailable**: gyro `0`, accelerometer `0` samples | Same | Observed: gyro `20`, accelerometer `20` samples | Preserve the report status: zero guest samples are not a negative hardware finding. A stationary phone's near-constant values are not suspicious by themselves. |
| Camera discovery | One wide camera, 1280×720 active format, two formats | Same | Two wide cameras plus TrueDepth; 1920×1080 active format; 46/26/26 formats | Compare against the *claimed* model and OS; camera access and virtual-camera configuration matter. No frames were captured. |

<details>
<summary>🧮 Model baselines, CPU subtypes, memory, and the excluded perflevels check</summary>

Apple's [XNU `sysctl.h`](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/sysctl.h) describes `hw.ncpu` as the maximum processors available to this boot and `hw.memsize` as physical memory bytes. [XNU `machine.h`](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/mach/machine.h) defines ARM64 subtype values, including V8 (`1`) and ARM64E (`2`). A subtype is not a reliable feature checklist. Public [ProcessInfo.processorCount](https://developer.apple.com/documentation/foundation/processinfo/processorcount) and `physicalMemory` can also supply CPU count and memory observations.

The [iPhone 16 specs](https://www.apple.com/iphone-16/specs/) provide a published six-core count for that model. This study did not find a complete Apple table of exact `hw.memsize` bytes or `hw.cpusubtype` values for every model and OS. Those references do not justify a global exact-value whitelist. Use a versioned, measured baseline for the claimed model, with public specifications used only where they directly state a property.

`hw.perflevels` returned `ENOENT` on **all three** devices, so it supplies no separation in this sample and was removed from the app. No reliable published device-wide value set was found to justify a classifier for it.

</details>

<a id="how-to-interpret-the-groups"></a>

## ⚖️ How to interpret the groups

An indicator is a value an app can observe and compare with a known artifact or a measured baseline. There is **no verified untamperable app-local indicator** in this data. vPhone controls the guest OS and can change files, device identity, system responses, virtual drivers, or the app's process environment. A positive exact marker can still be persuasive for the **tested snapshot**. A negative, `ENOENT`, or unavailable reading cannot establish physical hardware. `ENOENT` means the requested name or entry was not found through that call; access denial and other failures must remain separate results. These groups express evidence strength **when a result is observed**, not resistance to an active virtualizer.

| Group | Interpretation | App Review posture |
| --- | --- | --- |
| Strong positive markers | Exact vPhone or virtual-hardware artifacts can identify this tested build when present; each is guest-tamperable. | Metal, process environment, and path-existence checks use public app surfaces. The undocumented hypervisor OID names retain an **App Review risk** label. |
| Supporting consistency checks | Compare the claim (`hw.machine` / `hw.model`) with CPU, memory, GPU family, motion, and camera behavior, ideally against real devices of the same model and OS. CPU count belongs here. | Public framework and documented `hw.*` sysctl observations; no fixed virtualization verdict from one value. |
| Context / excluded | OS/build explains comparisons. Earlier private, restricted, unentitled, or inconclusive checks do not support the current app verdict. | Private IOKit/MobileGestalt probes and unentitled NFC were removed; App Attest remains research background only. |

<details>
<summary>⚠️ Public APIs and App Review considerations</summary>

A public API does not make every use App Review-safe. The path probes use public `lstat` to check directory-entry metadata without opening file contents. Related file checks appear in [IOSSecuritySuite](https://github.com/securing/IOSSecuritySuite/blob/master/IOSSecuritySuite/FileChecker.swift) and [DTTJailbreakDetection](https://github.com/thii/DTTJailbreakDetection/blob/master/Sources/DTTJailbreakDetection/DTTJailbreakDetection.m). Their source does not guarantee App Store approval. Review Apple's [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) for the intended distribution and use. The app gives the **undocumented hypervisor OID names** a visible review-risk label; `sysctlbyname` itself is documented.

</details>

<a id="app-conclusion-rule"></a>

## 🧭 App conclusion rule

The app displays one of three **provisional** conclusions above the full per-indicator report:

1. **vPhone detected:** at least one exact marker matches. This includes the model/board strings specific to the Standard preset, either nonzero hypervisor OID, any of the four exact path entries, the paravirtual Metal name, or the exact injected hook.
2. **Likely real device:** no exact marker matches, all eight direct checks complete with ordinary nonmatching results, and `hw.machine` / `hw.model` are readable. This is a heuristic for the two tested vPhone presets, not proof of physical hardware.
3. **Inconclusive:** no exact marker matches and a required check is unavailable, errors, or is missing. An inaccessible path is never treated as absent.

A modified vPhone can suppress every local marker, and another virtualizer may expose different artifacts. Supporting CPU, memory, sensor, camera, and GPU-family rows remain visible but do not silently change the conclusion without a measured same-model baseline.

The app reported **vPhone detected** on Standard preset (nine exact matches) and Experimental preset (seven exact matches), and **Likely real device** on the physical reference (zero exact matches). These are sandboxed-app results from all three targets. The example reports preserve every observed value and check status.

<a id="collection-method-and-limitations"></a>

## 🧪 Collection method and limitations

| Target | App-reported OS | Claimed model / board | App conclusion |
| --- | --- | --- | --- |
| Standard preset | iOS 27.0.1, build `24A446` | `iPhone99,11` / `VPHONE600AP` | vPhone detected; nine exact matches |
| Experimental preset, tested VM | iOS 27.0.1, build `24A446` | `iPhone17,3` / `D47AP` | vPhone detected; seven exact matches |
| Physical reference | iOS 16.7.7, build `20H330` | `iPhone10,6` / `D221AP` | Likely real device; zero exact matches, provisional |

Both vPhone guests lacked a jailbreak toolset. The physical reference was jailbroken. Its jailbreak files, processes, injections, and security behavior are excluded from the virtualization comparison. The physical reference also used a different model and OS from the guests. Exact vPhone component matches are useful controls; sensor, GPU, camera, CPU, and memory differences need model and OS context.

Keep the collection channel attached to each claim:

| Evidence channel | What it establishes in this study | Boundary |
| --- | --- | --- |
| Sandboxed app | Values the installed probe observed at runtime; the comparison tables and complete reports use this channel. | A guest controls the OS responses and process environment. An unavailable reading is not a negative hardware result. |
| USB lockdown | Installation and report-transfer context for the development-signed physical IPA. | Lockdown identity fields are not ordinary app readings and must not replace app evidence. |
| Privileged device access | Launch or extraction support where used on the physical reference. | Privileged observations and jailbreak artifacts do not enter the app-visible classifier. |
| Source-based expectation | Linked API definitions, implementation notes, and upstream technique descriptions. | A source expectation is not a measured app result. |

The guests received the app through vPhone's `apps.install` RPC, which re-signed the IPA and bypassed `installd`. The physical reference received a development-signed IPA through USB lockdown, then ran the app on the phone. Installation and extraction transports are separate from the origin of an observation: every result in the comparison tables came from the sandboxed app. These procedures establish runtime visibility for this app. They do not establish App Store acceptance or acceptance through a normal guest installation flow.

The external links provide API definitions and technique references. They do not establish how an untested vPhone release behaves.

<a id="swift-examples-for-each-retained-indicator"></a>

## 💻 Swift examples for each retained indicator

The full implementation is in [ProbeEngine.swift](vphone-indicator-probe/VPhoneIndicatorProbe/ProbeEngine.swift) and [AsyncProbes.swift](vphone-indicator-probe/VPhoneIndicatorProbe/AsyncProbes.swift). The examples below show the data collection; an app should display `ENOENT` and access errors distinctly, as the full implementation does. These short examples omit report formatting and error handling details; use the source when building a probe.

<details>
<summary>🪪 Identity, CPU count/type/subtype, memory, and OS build</summary>

```swift
import Darwin
import Foundation
import UIKit

func sysctlString(_ key: String) -> String? {
    var size = 0
    guard sysctlbyname(key, nil, &size, nil, 0) == 0, size > 0 else { return nil }
    var bytes = [CChar](repeating: 0, count: size)
    guard sysctlbyname(key, &bytes, &size, nil, 0) == 0 else { return nil }
    return String(cString: bytes)
}

func sysctlInt32(_ key: String) -> Int32? {
    var value: Int32 = 0
    var size = MemoryLayout<Int32>.size
    return sysctlbyname(key, &value, &size, nil, 0) == 0 ? value : nil
}

func sysctlUInt64(_ key: String) -> UInt64? {
    var value: UInt64 = 0
    var size = MemoryLayout<UInt64>.size
    return sysctlbyname(key, &value, &size, nil, 0) == 0 ? value : nil
}

let machine = sysctlString("hw.machine")
let board = sysctlString("hw.model")
let cpuCount = sysctlInt32("hw.ncpu")       // supporting consistency
let cpuType = sysctlInt32("hw.cputype")     // ARM64 type was 16777228 here
let cpuSubtype = sysctlInt32("hw.cpusubtype")
let memoryBytes = sysctlUInt64("hw.memsize")
let osVersion = UIDevice.current.systemVersion
let osBuild = sysctlString("kern.osversion")
```

</details>

<details>
<summary>⚠️ Preset-specific hypervisor OIDs: App Review risk</summary>

```swift
// Uses sysctlInt32 above. The function is documented; these names are not.
let standardOID = sysctlInt32("kern.hv_vmm_present")
let experimentalOID = sysctlInt32("kern.Xv_vmm_present")
let positiveForTestedBuild =
    (standardOID.map { $0 != 0 } ?? false) ||
    (experimentalOID.map { $0 != 0 } ?? false)
```

Preserve `errno` when the call fails. `ENOENT` on the Standard preset name is expected in the Experimental preset guest and does not mean the phone is physical.

</details>

<details>
<summary>📂 Exact vPhone path entries</summary>

```swift
import Darwin

let exactVPhonePaths = [
    "/usr/bin/vphoned",
    "/System/Library/LaunchDaemons/vphoned.plist",
    "/System/Library/Extensions/AppleParavirtGPUMetalIOGPUFamily.bundle",
    "/usr/lib/SystemHook-vphone.dylib"
]

func pathStatus(_ path: String) -> String {
    var entry = stat()
    guard path.withCString({ lstat($0, &entry) }) == 0 else {
        return "lstat errno \(errno)" // ENOENT differs from EACCES/EPERM.
    }
    if (entry.st_mode & S_IFMT) == S_IFLNK {
        var target = stat()
        if path.withCString({ stat($0, &target) }) == 0 {
            return "symbolic-link entry exists; target resolves"
        }
        return "symbolic-link entry exists; target stat errno \(errno)"
    }
    return "path entry exists"
}

let fileObservations = exactVPhonePaths.map { ($0, pathStatus($0)) }
```

</details>

<details>
<summary>🎮 Injected vPhone library and Metal device/families</summary>

```swift
import Foundation
import Metal

let libraries = (ProcessInfo.processInfo.environment["DYLD_INSERT_LIBRARIES"] ?? "")
    .split(separator: ":").map(String.init)
let hasExactHook = libraries.contains("/usr/lib/SystemHook-vphone.dylib")

let metal = MTLCreateSystemDefaultDevice()
let hasExactParavirtualName = metal?.name == "Apple Paravirtual device GPU"
let apple7 = metal?.supportsFamily(.apple7)
let common3 = metal?.supportsFamily(.common3)
```

The exact hook value and exact Metal name are strong positives for these builds. The GPU family booleans support a claimed-model check. The generic `DYLD_INSERT_LIBRARIES` key alone is not a vPhone marker.

</details>

<details>
<summary>📷 Motion availability/samples and camera configuration</summary>

```swift
import AVFoundation
import CoreMotion

let motion = CMMotionManager()
let availability = (
    motion.isAccelerometerAvailable,
    motion.isGyroAvailable,
    motion.isMagnetometerAvailable,
    motion.isDeviceMotionAvailable
)
if motion.isGyroAvailable {
    motion.gyroUpdateInterval = 0.1
    motion.startGyroUpdates(to: .main) { sample, error in
        // Count samples for a bounded interval, then stopGyroUpdates().
    }
}
if motion.isAccelerometerAvailable {
    motion.accelerometerUpdateInterval = 0.1
    motion.startAccelerometerUpdates(to: .main) { sample, error in
        // Count samples for the same interval, then stopAccelerometerUpdates().
    }
}

let devices = AVCaptureDevice.DiscoverySession(
    deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera,
                  .builtInTrueDepthCamera],
    mediaType: .video,
    position: .unspecified
).devices
let cameraSummary = devices.map { device in
    let size = CMVideoFormatDescriptionGetDimensions(
        device.activeFormat.formatDescription)
    return (device.deviceType, device.position,
            size.width, size.height, device.formats.count)
}
```

The app's [two-second sampler](vphone-indicator-probe/VPhoneIndicatorProbe/AsyncProbes.swift) counts and ranges gyro/accelerometer values, then stops both streams. Discovery lists devices and formats without capturing camera frames. The relevant public API references are [Core Motion](https://developer.apple.com/documentation/coremotion/cmmotionmanager), [AVCaptureDevice.DiscoverySession](https://developer.apple.com/documentation/avfoundation/avcapturedevice/discoverysession), and [Metal devices](https://developer.apple.com/documentation/metal/mtldevice).

</details>

<details>
<summary>🚧 Additional techniques considered and excluded</summary>

<a id="additional-techniques-considered-and-excluded-from-this-app"></a>

## 🚧 Additional techniques considered and excluded from this app

- **Private IOKit and MobileGestalt:** Their API and access patterns are unsuitable for this public-app-oriented probe and were removed from both the app and the active indicator set. Lockdown identity fields are not ordinary app readings and must not be substituted for app-visible evidence.
- **NFC:** The earlier app lacked the NFC reader entitlement. `readingAvailable=false` therefore could not establish absent NFC hardware. The row was removed. See [Apple Core NFC](https://developer.apple.com/documentation/corenfc/nfcreadersession-swift.class/readingavailable).
- **Bluetooth:** Standard preset reported powered on and Experimental preset timed out without a state callback. A timeout is not `.unsupported`; these observations did not separate the guests reliably. The row was removed.
- **Generic environment, arguments, and unrelated virtualizer paths:** Generic process strings can include this probe's own name, and another vendor's paths do not identify vPhone. Only the exact vPhone hook value remains.
- **App Attest background:** OWASP includes attestation among resilience methods, and Apple documents a [server-validated App Attest flow](https://developer.apple.com/documentation/devicecheck/establishing-your-app-s-integrity). Earlier local tests found Standard preset `isSupported=false`; Experimental preset `isSupported=true`, but its local `attestKey` attempt failed. The physical device reported support. These local results were influenced by guest signing/entitlement context and are **not server-validated**. App Attest is outside this study's probe scope and has been removed from the app.

OWASP's broader [virtual-device chapter](https://mas.owasp.org/MASTG/knowledge/ios/MASVS-RESILIENCE/MASTG-KNOW-0135/) lists techniques considered for this study. Its product-specific examples need validation on vPhone. In this snapshot, exact vPhone files, hook injection, the paravirtual Metal name, and the preset-specific hypervisor OIDs identified both installed guests. The Experimental preset masked the Standard preset's model/board markers while leaving those other positives visible. CPU count was equal across all three targets and remains a supporting consistency check.

</details>

<details>
<summary>🔁 Repeating the comparison</summary>

<a id="repeating-the-comparison"></a>

## 🔁 Repeating the comparison

Build and deploy the probe using the [app instructions](vphone-indicator-probe/README.md). Keep the exported text report, all per-indicator statuses, the OS build, claimed model and board, collection channel, and test date for every run. Record the vPhone upstream version or revision when available so that later observations can be tied to a reproducible build.

For a claimed-model consistency check, collect physical baselines for that same model and OS. Keep permission, entitlement, signing, and virtual-sensor or camera configuration with the results. A failed API call, missing entitlement, or timeout must remain distinguishable from absent hardware. Use screenshots to diagnose UI presentation; use the text reports for indicator comparisons.

The exact-marker rule is intentionally scoped to the measured artifacts. If a future build changes a path, OID, model string, or GPU name, update the measurements before changing the rule. A modified guest can suppress every listed marker, and another virtualizer can expose a different set.

</details>

<a id="optional-sample-app"></a>

## 🧩 Optional sample app

The optional SwiftUI probe demonstrates these checks, displays every indicator status and observed value, and exports a text report. It runs on iOS 16 or later and has no third-party dependencies. [🧩 Build and run the sample app](vphone-indicator-probe/README.md); screenshots and app-specific instructions are in its README.

[📦 Download the unsigned sample IPA](https://github.com/Incognito-Lab/vphone-detection/releases/latest) from Releases, or use a successful [🛠️ workflow run](https://github.com/Incognito-Lab/vphone-detection/actions/workflows/build-sample.yml) for a development artifact. Each download includes a SHA-256 checksum and build information. Physical-device installation requires your own signing and provisioning. The workflow checks compilation and packaging; it does not retest the detection findings.

<a id="example-reports"></a>

## 📄 Example reports

The optional public example reports retain the technical readings, per-indicator statuses, and error details. They exclude unique device IDs, personal names, host paths, credentials, and signing details. Their provenance document describes the collection channels and sanitization. Use text reports for comparison; screenshots are for diagnosing app presentation.

- [📱 Standard preset](vphone-indicator-probe/Examples/Reports/standard-2026-10-25.txt)
- [🧪 Experimental preset](vphone-indicator-probe/Examples/Reports/experimental-2026-10-25.txt)
- [📲 Physical reference](vphone-indicator-probe/Examples/Reports/physical-2026-10-25.txt)
- [🗂️ Report provenance](vphone-indicator-probe/Examples/Reports/README.md)

<a id="project-files"></a>

## 📁 Project files

- [🧩 Sample app source and Xcode project](vphone-indicator-probe/)
- [🤝 Contributing reproducible measurements](CONTRIBUTING.md)
- [📜 MIT license](LICENSE)

<a id="references"></a>

## 📚 References

### 📱 Upstream vPhone

- [📦 vphone-cli repository](https://github.com/Lakr233/vphone-cli) — upstream source, documentation, and releases.
- [🏷️ vPhone Core Bundle 2.12.0 release](https://github.com/Lakr233/vphone-cli/releases/tag/2.12.0) — the bundle used by the tested guests.

### 🛡️ OWASP mobile security guidance

- [🔎 MASTG: Virtual Devices Detection](https://mas.owasp.org/MASTG/knowledge/ios/MASVS-RESILIENCE/MASTG-KNOW-0135/) — the related techniques and their limitations.
- [📂 Specific virtualization-engine files](https://mas.owasp.org/MASTG/knowledge/ios/MASVS-RESILIENCE/MASTG-KNOW-0135/#presence-of-specific-virtualization-engine-files) — file-presence checks and bypass limitations.
- [📊 Hardware capability probes](https://mas.owasp.org/MASTG/knowledge/ios/MASVS-RESILIENCE/MASTG-KNOW-0135/#hardware-capability-probes) and [🪪 device properties](https://mas.owasp.org/MASTG/knowledge/ios/MASVS-RESILIENCE/MASTG-KNOW-0135/#device-properties) — supporting capability and identity comparisons.
- [🔐 App Attest validation](https://mas.owasp.org/MASTG/knowledge/ios/MASVS-RESILIENCE/MASTG-KNOW-0135/#app-attest-validation) — background research; excluded from this probe's classifier.

### 🍎 Apple APIs, system definitions, and specifications

- [🎮 Metal devices](https://developer.apple.com/documentation/metal/mtldevice), [🧭 Core Motion](https://developer.apple.com/documentation/coremotion/cmmotionmanager), and [📷 camera discovery](https://developer.apple.com/documentation/avfoundation/avcapturedevice/discoverysession) — public API references for the retained capability checks.
- [🧮 ProcessInfo.processorCount](https://developer.apple.com/documentation/foundation/processinfo/processorcount) — processor-count API reference.
- [⚙️ XNU sysctl definitions](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/sysctl.h) and [🧬 Mach CPU types and subtypes](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/mach/machine.h) — definitions behind the system-information readings.
- [📱 iPhone 16 specifications](https://www.apple.com/iphone-16/specs/) — an example of published model specifications for comparison.
- [📋 App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) — distribution policy context; public API use alone does not guarantee approval.
- [🔐 Server-validated App Attest](https://developer.apple.com/documentation/devicecheck/establishing-your-app-s-integrity) and [📡 Core NFC reading availability](https://developer.apple.com/documentation/corenfc/nfcreadersession-swift.class/readingavailable) — background for the excluded techniques and their interpretation limits.

### 🧩 Related implementation examples

- [📂 IOSSecuritySuite file checks](https://github.com/securing/IOSSecuritySuite/blob/master/IOSSecuritySuite/FileChecker.swift)
- [📂 DTTJailbreakDetection file checks](https://github.com/thii/DTTJailbreakDetection/blob/master/Sources/DTTJailbreakDetection/DTTJailbreakDetection.m)

These projects provide related filesystem-check examples. Their generic jailbreak indicators are outside this study's vPhone comparison.

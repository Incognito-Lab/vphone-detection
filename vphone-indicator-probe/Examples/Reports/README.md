# Example reports

These optional example reports record Standard and Experimental guests bound to **[vPhone Core Bundle 2.12.0](https://github.com/Lakr233/vphone-cli/releases/tag/2.12.0)** and a physical reference. Measurements are dated **2026-10-25 in Asia/Bangkok (UTC+07:00)**. The `Run:` timestamps inside the reports are UTC and therefore fall on 2026-10-24. The filenames follow the local research date.

| Report | Tested configuration | App conclusion | Exact marker matches |
| --- | --- | --- | --- |
| [Standard preset](standard-2026-10-25.txt) | iOS 27.0.1 (`24A446`), `iPhone99,11` / `VPHONE600AP` | vPhone detected | 9 |
| [Experimental preset](experimental-2026-10-25.txt) | iOS 27.0.1 (`24A446`), `iPhone17,3` / `D47AP` | vPhone detected | 7 |
| [Physical reference](physical-2026-10-25.txt) | iOS 16.7.7 (`20H330`), `iPhone10,6` / `D221AP` | Likely real device (provisional) | 0 |

Standard and Experimental describe presets, not device instance names. The VM metadata records both guests' boot-chain, runtime, and guest-environment bundles as 2.12.0; those bindings were written before the report timestamps. Bundle binary hashes were not captured with the app reports. The release link identifies the upstream release; it is separate from the guest iOS version. The `iPhone17,3` / `D47AP` pair is this Experimental VM's measured identity, not a universal model requirement. These reports cannot establish coverage of later releases; vPhone is under active development and its visible markers can change quickly.

The reports are not required to build or run the app. They preserve the evidence behind the published comparison and provide examples for interpreting your own results.

The report bodies retain the app's original observations, statuses, UTC timestamps, and explanations. They contain no device IDs or personal device names. Only trailing whitespace and final newlines were normalized for text-file formatting. Hardware model identifiers, OS builds, and exact detection strings are preserved because they are technical evidence.

| Kept for technical comparison | Excluded from public reports |
| --- | --- |
| Model and board identifiers, OS/build, CPU and memory readings, GPU name/families, sensor and camera results, exact marker paths, statuses, and errors | Unique device IDs and serials, personal device/account names, host paths, network addresses, credentials, and signing details |

All indicator rows are **sandboxed app** observations. The guests were installed through `apps.install`, which re-signs and bypasses installd. The physical app was development-signed and installed over **USB lockdown**. That transport is installation context; it is not the source of the indicator readings. Runtime results do not establish normal guest installation or App Store acceptance.

The physical reference was jailbroken. Its jailbreak files, processes, injections, and security behavior are excluded from the comparison; no privileged readings are used as indicator evidence here. Its model and OS differ from the guests, which limits hardware capability comparisons.

The physical report records **20 gyro samples and 20 accelerometer samples**. The accompanying guide uses these recorded counts. Zero guest samples retain the app's `Unavailable` status; they are not a negative hardware finding.

Original lab captures and reports from older probe logic remain local and are excluded from Git. See the [main research guide](../../../README.md) for complete marker interpretation and the [sample README](../../README.md) for reproduction instructions.

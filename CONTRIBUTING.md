# Contributing to vphone-detection

Use this project for education and testing on devices and environments you are authorized to inspect. The findings cover the tested vPhone 2.12.1 presets. New results need enough context for another developer to reproduce them.

## Reporting a measurement

Include:

- The vPhone release and commit, preset, guest OS version and build, and any configuration changes. If a field is unknown, say so.
- The probe revision, Xcode/SDK version, signing method, and installation method. Guest installation that re-signs or bypasses installd establishes runtime visibility only.
- A complete text report with each indicator's status and observed value, including errors and unavailable results. Wait for the two-second motion sample to finish before exporting.
- The evidence source: sandboxed app, USB lockdown, privileged device access, or source-based expectation. State the source for each additional observation; do not substitute privileged readings for app results.
- The claimed model and OS for physical controls. Explain model or OS differences before comparing sensors, cameras, CPU, memory, or GPU capabilities.

Remove device IDs, serial numbers, personal names, account information, host paths, network addresses, signing profiles, and credentials before sharing. Keep exact technical marker strings and useful model/OS context. A screenshot can help explain a UI issue; a text report is preferable for indicator comparisons.

## Changing the probe

Keep the full per-indicator report and its distinction between `ENOENT`, access denial, other errors, and unavailable APIs. Keep the high-level conclusion provisional: no marker found does not prove physical hardware.

Use exact vPhone markers. Generic jailbreak files, processes, injections, and security behavior are outside this comparison. CPU count, memory, motion, camera, and GPU family remain supporting checks unless a measured baseline for the claimed model and OS justifies a stronger inference.

Build the device target using the [sample instructions](vphone-indicator-probe/README.md). Compare the same probe logic across tested presets and physical controls before changing a conclusion. Record the tested vPhone revision for new measurements. Update the [main research guide](README.md), sample README, and public report examples when measured findings change.

Commit source and sanitized evidence only. Raw `Results/` captures, build products, signing material, and workspace instructions are excluded by `.gitignore`. Do not force-add them. The tested upstream code is [vphone-cli 2.12.0](https://github.com/Lakr233/vphone-cli/releases/tag/2.12.0). Reviewed screenshots for documentation belong in `vphone-indicator-probe/Examples/Screenshots/` and must contain no personal identifiers.

Contributions to this repository are provided under its [MIT license](LICENSE).

## Building release packages

The [🛠️ sample workflow](.github/workflows/build-sample.yml) builds and verifies an unsigned device IPA for sample-code, project, and packaging-script changes. Run `bash vphone-indicator-probe/scripts/build-unsigned-ipa.sh` for the same local packaging checks. Version tags in the form `vMAJOR.MINOR.PATCH` publish the IPA, checksum, and build information to Releases after a successful tagged build. Keep build success separate from measured detection results.

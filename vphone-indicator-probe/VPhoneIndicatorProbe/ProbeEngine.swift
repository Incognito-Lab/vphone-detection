import AVFoundation
import CoreMotion
import Darwin
import Foundation
import Metal
import UIKit

enum ProbeEngine {
    static func runSynchronous() -> [ProbeResult] {
        var results: [ProbeResult] = []
        results += identityResults()
        results += virtualHardwareResults()
        results += fileResults()
        results += capabilityResults()
        results += processResults()
        return results
    }

    private static func identityResults() -> [ProbeResult] {
        var output: [ProbeResult] = []
        let machine = sysctlString("hw.machine")
        output.append(ProbeResult("hw.machine", .consistency, "hw.machine",
                                  machine.value == "iPhone99,11" ? .marker : machine.status,
                                  machine.value ?? machine.message,
                                  "Live app reading. Compare the claimed model with the VM configuration and enabled identity patches; this row does not assume a fixed Experimental model."))

        let model = sysctlString("hw.model")
        output.append(ProbeResult("hw.model", .consistency, "hw.model",
                                  model.value == "VPHONE600AP" ? .marker : model.status,
                                  model.value ?? model.message,
                                  "Live app reading. Compare the claimed board with the VM configuration and enabled identity patches; only the exact VPHONE600AP value is counted as a tested Standard marker."))

        return output
    }

    private static func virtualHardwareResults() -> [ProbeResult] {
        var output: [ProbeResult] = []
        for (name, label) in [("kern.hv_vmm_present", "Hypervisor sysctl"),
                              ("kern.Xv_vmm_present", "Experimental renamed sysctl")] {
            let reading = sysctlInt32(name)
            let status: ProbeStatus = reading.value.map { $0 != 0 ? .marker : .observed } ?? reading.status
            output.append(ProbeResult(name, .direct, label, status,
                                      reading.value.map(String.init) ?? reading.message,
                                      "App Review risk: this sysctl name is undocumented. A positive value is useful for this build; zero or ENOENT is inconclusive."))
        }

        return output
    }

    private static func fileResults() -> [ProbeResult] {
        let paths: [(String, String)] = [
            ("/usr/bin/vphoned", "vPhone guest daemon"),
            ("/System/Library/LaunchDaemons/vphoned.plist", "vPhone launch daemon"),
            ("/System/Library/Extensions/AppleParavirtGPUMetalIOGPUFamily.bundle", "Paravirtual GPU bundle"),
            ("/usr/lib/SystemHook-vphone.dylib", "vPhone system hook"),
        ]
        return paths.map { path, title in
            var info = stat()
            let code = path.withCString { lstat($0, &info) }
            let resultErrno = errno
            if code == 0 {
                let kind = info.st_mode & S_IFMT
                let entryType: String
                let targetDetail: String
                switch kind {
                case S_IFLNK:
                    entryType = "symbolic link"
                    var targetInfo = stat()
                    if path.withCString({ stat($0, &targetInfo) }) == 0 {
                        targetDetail = "Its target resolves."
                    } else {
                        let targetErrno = errno
                        targetDetail = targetErrno == ENOENT
                            ? "Its target does not resolve (ENOENT)."
                            : "Target check returned errno \(targetErrno)."
                    }
                case S_IFDIR:
                    entryType = "directory"
                    targetDetail = ""
                case S_IFREG:
                    entryType = "regular file"
                    targetDetail = ""
                default:
                    entryType = "other entry"
                    targetDetail = ""
                }
                return ProbeResult("file.\(path)", .direct, title, .marker,
                                   "Path entry exists (\(entryType)): \(path)",
                                   "Exact vPhone path observed with lstat; no file contents opened. \(targetDetail)")
            }
            if resultErrno == ENOENT {
                return ProbeResult("file.\(path)", .direct, title, .absent,
                                   "Path entry absent (ENOENT): \(path)",
                                   "Absence cannot rule out a virtual device.")
            }
            return ProbeResult("file.\(path)", .direct, title, .unavailable,
                               "lstat errno \(resultErrno): \(String(cString: strerror(resultErrno)))",
                               "A blocked path is not an absent path.")
        }
    }

    private static func capabilityResults() -> [ProbeResult] {
        var output: [ProbeResult] = []
        if let gpu = MTLCreateSystemDefaultDevice() {
            let name = gpu.name
            output.append(ProbeResult("metal", .direct, "Metal default device",
                                      name == "Apple Paravirtual device GPU" ? .marker : .observed,
                                      name,
                                      "Exact vPhone GPU name is a strong positive for this build; the guest can change it."))
            output.append(ProbeResult("metalFamilies", .consistency, "Metal GPU families",
                                      .observed,
                                      "Apple7=\(gpu.supportsFamily(.apple7)); Common3=\(gpu.supportsFamily(.common3))",
                                      "Compare against the claimed model; family support is not a standalone verdict."))
        } else {
            output.append(ProbeResult("metal", .direct, "Metal default device", .unavailable,
                                      "No Metal device", "Could reflect sandbox or driver failure, not only virtualization."))
        }

        let motion = CMMotionManager()
        output.append(ProbeResult("motionAvailability", .consistency, "Motion hardware availability", .observed,
                                  "accelerometer=\(motion.isAccelerometerAvailable), gyro=\(motion.isGyroAvailable), magnetometer=\(motion.isMagnetometerAvailable), deviceMotion=\(motion.isDeviceMotionAvailable)",
                                  "vPhone can expose virtual sensors; availability alone is weak."))

        let cameraAuthorization = AVCaptureDevice.authorizationStatus(for: .video)
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTrueDepthCamera],
            mediaType: .video, position: .unspecified
        )
        let cameras = discovery.devices.map { device -> String in
            let dimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
            return "\(device.deviceType.rawValue):position=\(device.position.rawValue):\(dimensions.width)x\(dimensions.height):formats=\(device.formats.count)"
        }
        output.append(ProbeResult("camera", .consistency, "Camera discovery",
                                  cameras.isEmpty ? .unavailable : .observed,
                                  cameras.isEmpty ? "No listed cameras" : cameras.joined(separator: ", "),
                                  "Authorization=\(cameraAuthorization.rawValue). Discovery does not capture frames."))

        return output
    }

    private static func processResults() -> [ProbeResult] {
        var output: [ProbeResult] = []
        let build = sysctlString("kern.osversion")
        output.append(ProbeResult("osVersion", .context, "iOS version and build", .observed,
                                  "iOS \(UIDevice.current.systemVersion), build \(build.value ?? build.message)",
                                  "Context for comparing devices and preset capabilities."))
        let environment = ProcessInfo.processInfo.environment
        let injectedLibraries = (environment["DYLD_INSERT_LIBRARIES"] ?? "")
            .split(separator: ":").map(String.init)
        let vPhoneLibraries = injectedLibraries.filter {
            $0 == "/usr/lib/SystemHook-vphone.dylib"
        }
        output.append(ProbeResult("dyldVPhone", .direct, "Injected vPhone libraries",
                                  vPhoneLibraries.isEmpty ? .absent : .marker,
                                  vPhoneLibraries.isEmpty ? "No exact vPhone hook in DYLD_INSERT_LIBRARIES" : vPhoneLibraries.joined(separator: ", "),
                                  "Only the exact tested hook path is counted; the generic key is not a marker."))
        for key in ["hw.ncpu", "hw.cputype", "hw.cpusubtype"] {
            let reading = sysctlInt32(key)
            output.append(ProbeResult(key, .consistency, key, reading.status,
                                      reading.value.map(String.init) ?? reading.message,
                                      key == "hw.ncpu" ? "Compare with a published CPU-core count for the claimed model; not a standalone verdict." :
                                      key == "hw.cpusubtype" ? "Compare with a measured model/OS baseline; this value does not establish CPU features." :
                                      "ARM64 ABI class is broad context; an unexpected value needs verification."))
        }
        let memory = sysctlUInt64("hw.memsize")
        output.append(ProbeResult("hw.memsize", .consistency, "hw.memsize", memory.status,
                                  memory.value.map { "\($0) bytes" } ?? memory.message,
                                  "Compare exact bytes with a measured model/OS baseline. Published nominal RAM is not an exact sysctl value."))
        return output
    }

    private static func sysctlString(_ name: String) -> (value: String?, status: ProbeStatus, message: String) {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else {
            return (nil, errno == ENOENT ? .absent : .unavailable, "sysctl errno \(errno)")
        }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else {
            return (nil, .error, "sysctl errno \(errno)")
        }
        return (String(cString: bytes), .observed, "")
    }

    private static func sysctlInt32(_ name: String) -> (value: Int32?, status: ProbeStatus, message: String) {
        var number: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &number, &size, nil, 0) == 0 else {
            return (nil, errno == ENOENT ? .absent : .unavailable, "sysctl errno \(errno)")
        }
        return (number, .observed, "")
    }

    private static func sysctlUInt64(_ name: String) -> (value: UInt64?, status: ProbeStatus, message: String) {
        var number: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        guard sysctlbyname(name, &number, &size, nil, 0) == 0 else {
            return (nil, errno == ENOENT ? .absent : .unavailable, "sysctl errno \(errno)")
        }
        return (number, .observed, "")
    }
}

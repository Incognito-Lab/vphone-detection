import Foundation
import SwiftUI

enum ProbeCategory: String, CaseIterable, Identifiable {
    case direct = "Strong positive markers"
    case consistency = "Supporting consistency checks"
    case context = "Context"

    var id: String { rawValue }

    var screenTitle: String {
        switch self {
        case .direct: return "Exact markers"
        case .consistency: return "Consistency"
        case .context: return "Context"
        }
    }
}

enum ProbeStatus: String {
    case marker = "Virtual marker"
    case mismatch = "Possible mismatch"
    case absent = "Not found"
    case observed = "Observed"
    case unavailable = "Unavailable"
    case pending = "Pending"
    case error = "Error"

    var color: Color {
        switch self {
        case .marker: return .red
        case .mismatch: return .orange
        case .absent: return .secondary
        case .observed: return .blue
        case .unavailable, .pending: return .secondary
        case .error: return .orange
        }
    }
}

struct ProbeResult: Identifiable {
    let id: String
    let category: ProbeCategory
    let title: String
    let status: ProbeStatus
    let value: String
    let detail: String

    var hasAppReviewRisk: Bool {
        id == "kern.hv_vmm_present" || id == "kern.Xv_vmm_present"
    }

    init(_ id: String, _ category: ProbeCategory, _ title: String,
         _ status: ProbeStatus, _ value: String, _ detail: String = "") {
        self.id = id
        self.category = category
        self.title = title
        self.status = status
        self.value = value
        self.detail = detail
    }

    var summary: String {
        if id.hasPrefix("file.") {
            switch status {
            case .marker:
                return value.contains("symbolic link") ? "Path entry found · symbolic link" : "Path entry found"
            case .absent: return "Path entry absent"
            default: return "Could not check path"
            }
        }
        switch id {
        case "kern.hv_vmm_present", "kern.Xv_vmm_present":
            return status == .absent ? "ENOENT" : value
        case "dyldVPhone":
            return status == .absent ? "Exact hook not present" : "SystemHook-vphone.dylib"
        case "camera":
            guard status == .observed else { return value }
            let count = value.split(separator: ",").count
            return "\(count) camera \(count == 1 ? "device" : "devices") discovered"
        case "motionAvailability":
            let count = value.components(separatedBy: "=true").count - 1
            return "\(count) of 4 motion capabilities available"
        default:
            return value
        }
    }
}

struct ProbeConclusion {
    let title: String
    let detail: String
    let color: Color

    static func evaluate(_ results: [ProbeResult]) -> ProbeConclusion {
        let identityIDs: Set<String> = ["hw.machine", "hw.model"]
        let directIDs: Set<String> = [
            "kern.hv_vmm_present", "kern.Xv_vmm_present",
            "file./usr/bin/vphoned",
            "file./System/Library/LaunchDaemons/vphoned.plist",
            "file./System/Library/Extensions/AppleParavirtGPUMetalIOGPUFamily.bundle",
            "file./usr/lib/SystemHook-vphone.dylib",
            "metal", "dyldVPhone"
        ]
        let exactIDs = identityIDs.union(directIDs)
        let matches = results.filter { exactIDs.contains($0.id) && $0.status == .marker }
        if !matches.isEmpty {
            return ProbeConclusion(
                title: "vPhone detected",
                detail: "Exact markers found: \(matches.count). A modified guest could hide them.",
                color: .red)
        }

        let byID = Dictionary(uniqueKeysWithValues: results.map { ($0.id, $0) })
        let directChecksComplete = directIDs.allSatisfy { id in
            guard let result = byID[id] else { return false }
            return result.status == .observed || result.status == .absent
        }
        let identityReadable = identityIDs.allSatisfy { byID[$0]?.status == .observed }
        if directChecksComplete && identityReadable {
            return ProbeConclusion(
                title: "Likely real device",
                detail: "No marker matched across the completed exact checks. This is provisional for the tested vPhone builds; a modified guest can evade these checks.",
                color: .green)
        }

        return ProbeConclusion(
            title: "Inconclusive",
            detail: "No exact marker matched, but one or more required checks could not be completed. This does not establish a real device.",
            color: .orange)
    }
}

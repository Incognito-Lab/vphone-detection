import SwiftUI
import UIKit

final class ProbeStore: ObservableObject {
    @Published var results: [ProbeResult] = []
    @Published var lastRun: Date?
    private var motionProbe: MotionSampleProbe?

    var conclusion: ProbeConclusion { ProbeConclusion.evaluate(results) }

    func run() {
        motionProbe?.stop()
        results = ProbeEngine.runSynchronous()
        lastRun = Date()

        upsert(ProbeResult("motionSample", .consistency, "Motion samples",
                           .pending, "Sampling for two seconds"))
        motionProbe = MotionSampleProbe { [weak self] result in
            self?.upsert(result)
            self?.motionProbe = nil
        }
        motionProbe?.start()
    }

    func upsert(_ result: ProbeResult) {
        if let index = results.firstIndex(where: { $0.id == result.id }) {
            results[index] = result
        } else {
            results.append(result)
        }
        saveReport()
    }

    private func saveReport() {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        try? report.write(to: documents.appendingPathComponent("probe-report.txt"),
                          atomically: true, encoding: .utf8)
    }

    var report: String {
        let stamp = lastRun.map { ISO8601DateFormatter().string(from: $0) } ?? "never"
        let verdict = conclusion
        var lines = ["vPhone Indicator Probe", "Run: \(stamp)",
                     "Conclusion: \(verdict.title)", "Reason: \(verdict.detail)",
                     "Scope: Heuristic for the tested vPhone builds; a local conclusion is not proof."]
        for category in ProbeCategory.allCases {
            lines.append("\n[\(category.rawValue)]")
            for result in results.filter({ $0.category == category }) {
                lines.append("\(result.title) | \(result.status.rawValue) | \(result.value)")
                if !result.detail.isEmpty { lines.append("  \(result.detail)") }
            }
        }
        return lines.joined(separator: "\n")
    }
}

struct ContentView: View {
    @StateObject private var store = ProbeStore()
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline, spacing: 9) {
                            Circle()
                                .fill(store.conclusion.color)
                                .frame(width: 9, height: 9)
                                .accessibilityHidden(true)
                            Text(store.conclusion.title)
                                .font(.title2.weight(.semibold))
                        }
                        Text(store.conclusion.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let lastRun = store.lastRun {
                            Text("Checked \(lastRun.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 20))

                    ForEach(ProbeCategory.allCases) { category in
                        let items = store.results.filter { $0.category == category }
                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(category.screenTitle.uppercased())
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 20)
                                VStack(spacing: 0) {
                                    ForEach(items) { result in
                                        IndicatorRow(result: result)
                                            .padding(.horizontal, 20)
                                            .padding(.vertical, 12)
                                        if result.id != items.last?.id {
                                            Divider()
                                                .padding(.leading, 20)
                                        }
                                    }
                                }
                                .background(Color(uiColor: .secondarySystemGroupedBackground),
                                            in: RoundedRectangle(cornerRadius: 20))
                            }
                            .padding(.top, 28)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Device check")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        copied = false
                        store.run()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Run checks again")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(copied ? "Copied" : "Copy") {
                        UIPasteboard.general.string = store.report
                        copied = true
                    }
                    .accessibilityLabel("Copy report")
                    .disabled(store.results.isEmpty)
                }
            }
            .onAppear { if store.results.isEmpty { store.run() } }
        }
    }
}

private struct IndicatorRow: View {
    let result: ProbeResult
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.28)) {
                    isExpanded.toggle()
                }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(result.title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 4)
                        Text(result.status.rawValue)
                            .font(.subheadline)
                            .foregroundStyle(result.status.color)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                    Text(result.value)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if result.hasAppReviewRisk {
                        Text("App Review risk")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(result.title), \(result.status.rawValue)\(result.hasAppReviewRisk ? ", App Review risk" : "")")
            .accessibilityValue(result.value)
            .accessibilityHint(isExpanded ? "Collapse details" : "Expand details")

            if isExpanded && !result.detail.isEmpty {
                Text(result.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.top, 5)
                    .transition(.opacity)
            }
        }
        .padding(.vertical, 3)
        .clipped()
    }
}

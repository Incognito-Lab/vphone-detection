import CoreMotion
import Foundation

final class MotionSampleProbe {
    private let manager = CMMotionManager()
    private var completion: ((ProbeResult) -> Void)?
    private var gyroMagnitudes: [Double] = []
    private var accelerationMagnitudes: [Double] = []
    private var stopped = false

    init(completion: @escaping (ProbeResult) -> Void) {
        self.completion = completion
    }

    func start() {
        manager.gyroUpdateInterval = 0.1
        manager.accelerometerUpdateInterval = 0.1
        if manager.isGyroAvailable {
            manager.startGyroUpdates(to: .main) { [weak self] data, _ in
                guard let self, let data, !self.stopped else { return }
                let r = data.rotationRate
                self.gyroMagnitudes.append(sqrt(r.x * r.x + r.y * r.y + r.z * r.z))
            }
        }
        if manager.isAccelerometerAvailable {
            manager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
                guard let self, let data, !self.stopped else { return }
                let a = data.acceleration
                self.accelerationMagnitudes.append(sqrt(a.x * a.x + a.y * a.y + a.z * a.z))
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.finish()
        }
    }

    func stop() {
        stopped = true
        manager.stopGyroUpdates()
        manager.stopAccelerometerUpdates()
        completion = nil
    }

    private func finish() {
        guard !stopped else { return }
        manager.stopGyroUpdates()
        manager.stopAccelerometerUpdates()
        stopped = true
        let gyroRange = range(gyroMagnitudes)
        let accelerationRange = range(accelerationMagnitudes)
        let value = "gyro samples=\(gyroMagnitudes.count), range=\(gyroRange); accelerometer samples=\(accelerationMagnitudes.count), range=\(accelerationRange)"
        let status: ProbeStatus = gyroMagnitudes.isEmpty && accelerationMagnitudes.isEmpty ? .unavailable : .observed
        completion?(ProbeResult("motionSample", .consistency, "Motion samples", status, value,
                                "A stationary real phone can produce nearly constant data. No motion-based verdict is made."))
        completion = nil
    }

    private func range(_ values: [Double]) -> String {
        guard let lowest = values.min(), let highest = values.max() else { return "none" }
        return String(format: "%.4f–%.4f", lowest, highest)
    }
}

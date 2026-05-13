import Foundation
import os

@MainActor
final class SchedulerService {
    private var timers: [UUID: DispatchSourceTimer] = [:]
    private let logger = Logger(subsystem: "com.arcmark.app", category: "scheduler")

    var onFire: ((ScheduledLinkRef) -> Void)?

    func sync(with schedules: [ScheduledLinkRef]) {
        for (_, timer) in timers { timer.cancel() }
        timers.removeAll()

        let now = Date()
        for ref in schedules {
            if ref.fireAt <= now {
                logger.debug("Firing overdue \(ref.linkId.uuidString, privacy: .public)")
                onFire?(ref)
            } else {
                arm(ref)
            }
        }
    }

    private func arm(_ ref: ScheduledLinkRef) {
        let delay = max(0, ref.fireAt.timeIntervalSinceNow)
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + delay)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.timers[ref.linkId]?.cancel()
            self.timers.removeValue(forKey: ref.linkId)
            self.logger.debug("Firing scheduled \(ref.linkId.uuidString, privacy: .public)")
            self.onFire?(ref)
        }
        timers[ref.linkId] = timer
        timer.resume()
    }
}

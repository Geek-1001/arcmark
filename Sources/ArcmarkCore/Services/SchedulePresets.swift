import Foundation

enum SchedulePresets {
    struct Preset {
        let label: String
        let component: Calendar.Component
        let value: Int
    }

    static let all: [Preset] = [
        Preset(label: "In 1 hour", component: .hour, value: 1),
        Preset(label: "In 1 day", component: .day, value: 1),
        Preset(label: "In 2 days", component: .day, value: 2),
        Preset(label: "In 3 days", component: .day, value: 3),
        Preset(label: "In 1 week", component: .day, value: 7),
        Preset(label: "In 2 weeks", component: .day, value: 14)
    ]

    static func date(component: Calendar.Component, value: Int, from base: Date = Date()) -> Date? {
        Calendar.current.date(byAdding: component, value: value, to: base)
    }
}

final class ScheduleMenuPayload {
    let linkId: UUID
    let component: Calendar.Component
    let value: Int
    init(linkId: UUID, component: Calendar.Component, value: Int) {
        self.linkId = linkId
        self.component = component
        self.value = value
    }
}

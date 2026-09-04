import Foundation

enum ChargeAction: Equatable, Sendable {
    case charge
    case inhibit
    case discharge

    /// Wire format for `GranipaBatteryHelping.applyAction`.
    var helperRaw: Int {
        switch self {
        case .charge: 0
        case .inhibit: 1
        case .discharge: 2
        }
    }
}

enum ChargePolicy {
    static let minLimit = 50
    static let maxLimit = 100
    static let hysteresis = 2

    static func clampedLimit(_ limit: Int) -> Int {
        min(maxLimit, max(minLimit, limit))
    }

    static func action(
        percent: Int,
        limit: Int,
        topUp: Bool,
        discharging: Bool,
        chargingAllowed: Bool,
        heatPaused: Bool = false
    ) -> ChargeAction {
        if heatPaused { return .inhibit }
        let limit = clampedLimit(limit)
        if topUp { return percent >= 100 ? .inhibit : .charge }
        if discharging { return .discharge }
        if percent >= limit { return .inhibit }
        if percent <= limit - hysteresis { return .charge }
        return chargingAllowed ? .charge : .inhibit
    }
}

enum CalibrationStep: Int, CaseIterable, Identifiable, Sendable {
    case chargeTo100
    case dischargeTo10
    case chargeTo100Again
    case hold1h
    case dischargeTo75

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .chargeTo100, .chargeTo100Again: "Charge to 100%"
        case .dischargeTo10: "Discharge to 10%"
        case .hold1h: "Hold for 1h"
        case .dischargeTo75: "Discharge to 75%"
        }
    }
}

enum CalibrationAdvance: Equatable, Sendable {
    case stay
    case go(CalibrationStep)
    case finished
}

enum CalibrationPolicy {
    static let holdDuration: TimeInterval = 3600

    static func action(step: CalibrationStep, percent: Int) -> ChargeAction {
        switch step {
        case .chargeTo100, .chargeTo100Again: percent >= 100 ? .inhibit : .charge
        case .hold1h: .charge
        case .dischargeTo10, .dischargeTo75: .discharge
        }
    }

    static func advance(
        step: CalibrationStep, percent: Int, holdElapsed: TimeInterval
    ) -> CalibrationAdvance {
        switch step {
        case .chargeTo100:
            percent >= 100 ? .go(.dischargeTo10) : .stay
        case .dischargeTo10:
            percent <= 10 ? .go(.chargeTo100Again) : .stay
        case .chargeTo100Again:
            percent >= 100 ? .go(.hold1h) : .stay
        case .hold1h:
            holdElapsed >= holdDuration ? .go(.dischargeTo75) : .stay
        case .dischargeTo75:
            percent <= 75 ? .finished : .stay
        }
    }
}

enum MagSafeLEDMode: String, CaseIterable, Identifiable, Sendable {
    case system
    case off
    case alwaysOn

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .off: "Off"
        case .alwaysOn: "Always On"
        }
    }

    /// SMC `ACLC`: 0 system, 1 off, 3 green, 4 orange.
    func smcByte(isCharging: Bool) -> UInt8 {
        switch self {
        case .system: 0
        case .off: 1
        case .alwaysOn: isCharging ? 4 : 3
        }
    }
}

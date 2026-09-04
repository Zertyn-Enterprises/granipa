import AppKit
import Foundation
import Observation
import os

@MainActor
@Observable
final class BatteryService {
    static let shared = BatteryService()
    private static let log = Logger(subsystem: "com.zertyn.granipa", category: "battery")

    private(set) var snapshot = BatterySnapshot.missing
    private(set) var canControl = false
    private(set) var hasMagSafeLED = false
    private(set) var controlMessage: String?
    private(set) var temperatureC: Double?
    private(set) var calibrationStep: CalibrationStep?
    private(set) var lastCalibrationAt: Date?
    var topUp = false
    var discharging = false
    var limiterEnabled: Bool {
        didSet {
            UserDefaults.standard.set(limiterEnabled, forKey: "batteryLimiterEnabled")
            if !limiterEnabled {
                topUp = false
                discharging = false
                restoreCharging()
            } else {
                tick()
            }
        }
    }
    var limit: Int {
        didSet {
            UserDefaults.standard.set(
                ChargePolicy.clampedLimit(limit), forKey: "batteryChargeLimit")
        }
    }
    var heatProtection: Bool {
        didSet { UserDefaults.standard.set(heatProtection, forKey: "batteryHeatProtection") }
    }
    var heatThresholdC: Int {
        didSet {
            UserDefaults.standard.set(min(45, max(30, heatThresholdC)), forKey: "batteryHeatThreshold")
        }
    }
    var magSafeLED: MagSafeLEDMode {
        didSet { UserDefaults.standard.set(magSafeLED.rawValue, forKey: "batteryMagSafeLED") }
    }

    var isCalibrating: Bool { calibrationStep != nil }

    private var chargingAllowed = true
    private var lastAction: ChargeAction?
    private var lastActionUsedHelper: Bool?
    private var lastMagSafeLEDByte: UInt8?
    private var lastMagSafeLEDUsedHelper: Bool?
    private var holdStartedAt: Date?
    private var didOfferHelperInstall = false

    private init() {
        limiterEnabled =
            UserDefaults.standard.object(forKey: "batteryLimiterEnabled") as? Bool ?? false
        let stored = UserDefaults.standard.object(forKey: "batteryChargeLimit") as? Int
        limit = ChargePolicy.clampedLimit(stored ?? 80)
        heatProtection =
            UserDefaults.standard.object(forKey: "batteryHeatProtection") as? Bool ?? false
        heatThresholdC = UserDefaults.standard.object(forKey: "batteryHeatThreshold") as? Int ?? 35
        magSafeLED =
            MagSafeLEDMode(rawValue: UserDefaults.standard.string(forKey: "batteryMagSafeLED") ?? "")
            ?? .system
        lastCalibrationAt = UserDefaults.standard.object(forKey: "batteryLastCalibration") as? Date
    }
    private var loop: Task<Void, Never>?
    private let smc = SMCClient()
    private var usingCHTE = false
    private let tempKeys = ["TB0T", "TB1T", "TW0P", "B0Te"]

    func start() {
        snapshot = BatteryIO.snapshot()
        probeControl()
        tick()
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(5))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await MainActor.run { self?.tick() }
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        discharging = false
        topUp = false
        calibrationStep = nil
        holdStartedAt = nil
        if canControl, helperEnabled {
            if !BatteryHelperClient.shared.applySynchronously(
                action: .charge,
                usingCHTE: usingCHTE)
            {
                Self.log.error("Timed out while restoring charging during termination")
            }
            lastAction = nil
            lastActionUsedHelper = nil
        } else {
            restoreCharging()
        }
    }

    func tick() {
        snapshot = BatteryIO.snapshot()
        temperatureC = readTemperature()
        applyMagSafeLED()
        guard snapshot.isPresent, canControl else { return }

        if let step = calibrationStep {
            runCalibration(step)
            return
        }

        let hot =
            heatProtection
            && (temperatureC ?? 0) >= Double(heatThresholdC)
        let wantsControl = limiterEnabled || hot
        if !wantsControl {
            if lastAction != nil {
                apply(.charge)
                lastAction = nil
                lastActionUsedHelper = nil
            }
            return
        }

        let action = ChargePolicy.action(
            percent: snapshot.percent,
            limit: limit,
            topUp: topUp,
            discharging: discharging,
            chargingAllowed: chargingAllowed,
            heatPaused: hot)
        applyIfChanged(action)
        if topUp, snapshot.percent >= 100 { topUp = false }
        if discharging, snapshot.percent <= max(ChargePolicy.minLimit, limit - 15) {
            discharging = false
        }
    }

    func beginTopUp() {
        discharging = false
        topUp = true
        tick()
    }

    func beginDischarge() {
        topUp = false
        discharging = true
        tick()
    }

    var helperEnabled: Bool { BatteryHelperClient.shared.isEnabled }

    private func offerHelperInstallIfNeeded() {
        guard !didOfferHelperInstall, !helperEnabled else { return }
        didOfferHelperInstall = true
        let alert = NSAlert()
        alert.messageText = "Install battery helper?"
        alert.informativeText =
            "macOS blocks charge-limit writes from the app. A one-time admin password installs a root helper so the \(limit)% limit actually applies."
        alert.addButton(withTitle: "Install…")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            installHelper()
        }
    }

    func installHelper() {
        do {
            switch try BatteryHelperClient.shared.install() {
            case .enabled:
                controlMessage = nil
                Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    tick()
                }
            case .needsApproval:
                controlMessage =
                    "Turn on Grañipa Battery in System Settings → General → Login Items, then toggle Limit charging again."
            }
        } catch {
            controlMessage = error.localizedDescription
        }
    }

    func restoreCharging() {
        discharging = false
        topUp = false
        calibrationStep = nil
        holdStartedAt = nil
        if canControl {
            apply(.charge)
            if hasMagSafeLED {
                applyMagSafeLED(forceSystem: true)
            }
        }
        lastAction = nil
        lastActionUsedHelper = nil
    }

    func startCalibration() {
        guard canControl, snapshot.isPresent else { return }
        topUp = false
        discharging = false
        holdStartedAt = nil
        calibrationStep = .chargeTo100
        tick()
    }

    func stopCalibration() {
        calibrationStep = nil
        holdStartedAt = nil
        tick()
    }

    private func probeControl() {
        guard smc.open() else {
            canControl = false
            controlMessage = "No AppleSMC on this Mac."
            return
        }
        usingCHTE = smc.keyExists("CHTE")
        let classic = smc.keyExists("CH0B")
        canControl = usingCHTE || classic
        hasMagSafeLED = smc.keyExists("ACLC")
        if !canControl {
            controlMessage = "This Mac has no charging-control SMC keys (desktop, or unsupported firmware)."
            return
        }
        controlMessage = nil
        Self.log.info("battery control keys CHTE=\(self.usingCHTE) CH0B=\(classic) ACLC=\(self.hasMagSafeLED)")
    }

    private func runCalibration(_ step: CalibrationStep) {
        if step == .hold1h, holdStartedAt == nil { holdStartedAt = .now }
        let elapsed = holdStartedAt.map { Date.now.timeIntervalSince($0) } ?? 0
        applyIfChanged(CalibrationPolicy.action(step: step, percent: snapshot.percent))
        switch CalibrationPolicy.advance(
            step: step, percent: snapshot.percent, holdElapsed: elapsed)
        {
        case .stay:
            break
        case .go(let next):
            if next == .hold1h { holdStartedAt = .now }
            calibrationStep = next
        case .finished:
            calibrationStep = nil
            holdStartedAt = nil
            lastCalibrationAt = .now
            UserDefaults.standard.set(lastCalibrationAt, forKey: "batteryLastCalibration")
        }
    }

    private func readTemperature() -> Double? {
        guard smc.open() else { return nil }
        for key in tempKeys {
            if let value = try? smc.readSP78(key), value > 0, value < 90 {
                return value
            }
        }
        return nil
    }

    private func applyMagSafeLED(forceSystem: Bool = false) {
        guard hasMagSafeLED else { return }
        let byte =
            forceSystem
            ? MagSafeLEDMode.system.smcByte(isCharging: false)
            : magSafeLED.smcByte(isCharging: snapshot.isCharging)
        let usesHelper = BatteryHelperClient.shared.isEnabled
        guard byte != lastMagSafeLEDByte || usesHelper != lastMagSafeLEDUsedHelper else { return }
        if usesHelper {
            lastMagSafeLEDByte = byte
            lastMagSafeLEDUsedHelper = true
            BatteryHelperClient.shared.applyLED(byte) { [weak self] ok, _ in
                guard !ok else { return }
                Task { @MainActor in
                    guard self?.lastMagSafeLEDByte == byte,
                        self?.lastMagSafeLEDUsedHelper == true
                    else { return }
                    self?.lastMagSafeLEDByte = nil
                    self?.lastMagSafeLEDUsedHelper = nil
                }
            }
            return
        }
        do {
            try smc.writeU8("ACLC", byte)
            lastMagSafeLEDByte = byte
            lastMagSafeLEDUsedHelper = false
        } catch {
            Self.log.error("MagSafe LED write failed")
        }
    }

    private func applyIfChanged(_ action: ChargeAction) {
        let usesHelper = BatteryHelperClient.shared.isEnabled
        guard action != lastAction || usesHelper != lastActionUsedHelper else { return }
        if apply(action, usesHelper: usesHelper) {
            lastAction = action
            lastActionUsedHelper = usesHelper
        }
    }

    @discardableResult
    private func apply(_ action: ChargeAction, usesHelper: Bool? = nil) -> Bool {
        let usesHelper = usesHelper ?? BatteryHelperClient.shared.isEnabled
        chargingAllowed = action == .charge
        if usesHelper {
            BatteryHelperClient.shared.apply(action: action, usingCHTE: usingCHTE) {
                [weak self] ok, err in
                Task { @MainActor in
                    guard let self else { return }
                    self.controlMessage = ok ? nil : (err ?? "Helper write failed")
                    if !ok, self.lastAction == action, self.lastActionUsedHelper == true {
                        self.lastAction = nil
                        self.lastActionUsedHelper = nil
                    }
                }
            }
            return true
        }
        do {
            switch action {
            case .charge:
                try setCharging(true)
                try setDischarge(false)
            case .inhibit:
                try setCharging(false)
                try setDischarge(false)
            case .discharge:
                try setCharging(false)
                try setDischarge(true)
            }
            controlMessage = nil
            return true
        } catch SMCClientError.notPrivileged {
            Self.log.error("SMC write not privileged action=\(String(describing: action))")
            if action != .charge {
                controlMessage =
                    "macOS blocked the charge-limit write. Install the battery helper (admin password once) so the \(limit)% limit can apply."
                offerHelperInstallIfNeeded()
            }
            return false
        } catch {
            controlMessage = "Could not talk to the SMC (\(error))."
            Self.log.error("SMC apply failed")
            return false
        }
    }

    private func setCharging(_ on: Bool) throws {
        if usingCHTE {
            try smc.writeU32LE("CHTE", on ? 0 : 1)
        } else {
            let byte: UInt8 = on ? 0x00 : 0x02
            try smc.writeU8("CH0B", byte)
            if smc.keyExists("CH0C") { try smc.writeU8("CH0C", byte) }
        }
    }

    private func setDischarge(_ on: Bool) throws {
        if smc.keyExists("CH0I") {
            try smc.writeU8("CH0I", on ? 1 : 0)
        } else if smc.keyExists("CHIE") {
            try smc.writeU8("CHIE", on ? 8 : 0)
        } else if on {
            throw SMCClientError.keyNotFound
        }
    }
}

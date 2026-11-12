import AppKit
import Foundation
import Observation
import os
import ServiceManagement

@MainActor
@Observable
final class BatteryService {
    static let shared = BatteryService()
    private static let log = Logger(subsystem: "com.zertyn.granipa", category: "battery")

    private var currentSnapshot = BatterySnapshot.missing
    private(set) var canControl = false
    private(set) var hasMagSafeLED = false
    private(set) var controlMessage: String?
    private var currentTemperatureC: Double?
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
        didSet {
            UserDefaults.standard.set(heatProtection, forKey: "batteryHeatProtection")
            tick()
        }
    }
    var heatThresholdC: Int {
        didSet {
            UserDefaults.standard.set(min(45, max(30, heatThresholdC)), forKey: "batteryHeatThreshold")
        }
    }
    var magSafeLED: MagSafeLEDMode {
        didSet {
            UserDefaults.standard.set(magSafeLED.rawValue, forKey: "batteryMagSafeLED")
            tick()
        }
    }

    var isCalibrating: Bool { calibrationStep != nil }

    /// Read by the menu and Settings. While nothing polls, a stale read
    /// schedules one refresh instead of keeping a timer alive.
    var snapshot: BatterySnapshot {
        scheduleIdleReadoutIfStale()
        return currentSnapshot
    }

    var temperatureC: Double? {
        scheduleIdleReadoutIfStale()
        return currentTemperatureC
    }

    private var chargingAllowed = true
    private var applied = AppliedBatteryState()
    private var holdStartedAt: Date?
    private var didOfferHelperInstall = false

    /// Internal so focused tests can build isolated instances instead of
    /// mutating `shared` from parallel suites.
    init() {
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
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var readoutAt = Date.distantPast
    @ObservationIgnored private var readoutScheduled = false
    private static let tickSeconds: TimeInterval = 5
    private let smc = SMCClient()
    private var usingCHTE = false
    private let tempKeys = ["TB0T", "TB1T", "TW0P", "B0Te"]
    private var temperatureKey: String?

    func start() {
        BatteryHelperClient.shared.onConnectionLost = { [weak self] in
            self?.applied.helperConnectionLost()
        }
        probeControl()
        isStarted = true
        tick()
    }

    func stop() {
        isStarted = false
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
            applied.clearAction()
        } else {
            restoreCharging()
        }
    }

    func tick() {
        defer { syncLoop() }
        refreshReadout()
        // Idle: no feature on and nothing to undo, so no SMC/helper/LED writes
        // (an LED write here would launch the root helper at every app start).
        guard needsPolling else { return }
        applyMagSafeLED()
        guard currentSnapshot.isPresent, canControl else { return }

        if let step = calibrationStep {
            runCalibration(step)
            return
        }

        let hot =
            heatProtection
            && (currentTemperatureC ?? 0) >= Double(heatThresholdC)
        let wantsControl = limiterEnabled || hot
        if !wantsControl {
            if applied.action != nil {
                apply(.charge)
                applied.clearAction()
            }
            return
        }

        let action = ChargePolicy.action(
            percent: currentSnapshot.percent,
            limit: limit,
            topUp: topUp,
            discharging: discharging,
            chargingAllowed: chargingAllowed,
            heatPaused: hot)
        applyIfChanged(action)
        if topUp, currentSnapshot.percent >= 100 { topUp = false }
        if discharging, currentSnapshot.percent <= max(ChargePolicy.minLimit, limit - 15) {
            discharging = false
        }
    }

    private var needsPolling: Bool {
        BatteryPollingPolicy.needsPolling(
            featureOn: limiterEnabled || heatProtection || calibrationStep != nil || topUp
                || discharging || (hasMagSafeLED && magSafeLED != .system),
            applied: applied)
    }

    private func syncLoop() {
        guard isStarted, needsPolling else {
            loop?.cancel()
            loop = nil
            return
        }
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(Self.tickSeconds))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await MainActor.run { self?.tick() }
            }
        }
    }

    private func refreshReadout() {
        readoutAt = .now
        let nextSnapshot = BatteryIO.snapshot()
        if nextSnapshot != currentSnapshot {
            currentSnapshot = nextSnapshot
        }
        let nextTemperature = nextSnapshot.isPresent ? readTemperature() : nil
        if nextTemperature != currentTemperatureC {
            currentTemperatureC = nextTemperature
        }
    }

    private func scheduleIdleReadoutIfStale() {
        guard isStarted, loop == nil, !readoutScheduled,
            Date.now.timeIntervalSince(readoutAt) >= Self.tickSeconds
        else { return }
        // Deferred: this runs inside a view's body, which must not mutate state.
        readoutScheduled = true
        Task { [weak self] in
            guard let self else { return }
            self.readoutScheduled = false
            if self.isStarted, self.loop == nil { self.refreshReadout() }
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

    /// Registration alone does not prove writes work; a failed install,
    /// repair or helper write leaves helperSetupMessage set.
    var helperHealthy: Bool { canControl && helperEnabled && helperSetupMessage == nil }

    private func offerHelperInstallIfNeeded() {
        guard !didOfferHelperInstall, !helperEnabled else { return }
        didOfferHelperInstall = true
        let alert = NSAlert()
        alert.messageText = "Install battery helper?"
        alert.informativeText =
            "macOS blocks charge-limit writes from the app. Install registers a root helper that you approve in System Settings → General → Login Items, so the \(limit)% limit actually applies."
        alert.addButton(withTitle: "Install…")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            installHelper()
        }
    }

    func installHelper() {
        guard !helperBusy else { return }
        helperSetupMessage = nil
        do {
            switch try BatteryHelperClient.shared.install() {
            case .enabled:
                controlMessage = nil
                Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    tick()
                }
            case .needsApproval:
                helperSetupMessage = BatteryHelperError.needsApproval.errorDescription
            }
        } catch {
            helperSetupMessage = error.localizedDescription
        }
    }

    private(set) var helperBusy = false

    /// Outcome of the last helper install/repair, kept apart from
    /// controlMessage so the 5-second charge tick cannot erase it.
    private(set) var helperSetupMessage: String?

    var performHelperRepair: @MainActor @Sendable () async throws -> Void = {
        try await BatteryHelperClient.shared.repair()
    }

    func repairHelper() async {
        guard !helperBusy else { return }
        helperBusy = true
        helperSetupMessage = "Repairing the battery helper…"
        controlMessage = "Repairing the battery helper…"
        defer { helperBusy = false }
        do {
            try await performHelperRepair()
            controlMessage = "Battery helper registered."
            helperSetupMessage = nil
        } catch {
            controlMessage = error.localizedDescription
            helperSetupMessage = error.localizedDescription
        }
    }

    func openHelperApproval() {
        SMAppService.openSystemSettingsLoginItems()
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
        applied.clearAction()
        syncLoop()
    }

    func startCalibration() {
        guard canControl, currentSnapshot.isPresent else { return }
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
        applyIfChanged(CalibrationPolicy.action(step: step, percent: currentSnapshot.percent))
        switch CalibrationPolicy.advance(
            step: step, percent: currentSnapshot.percent, holdElapsed: elapsed)
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
        let preferredKey = temperatureKey
        if let preferredKey,
            let value = try? smc.readTemperature(preferredKey),
            value > 0, value < 90
        {
            return value
        }
        temperatureKey = nil
        for key in tempKeys where key != preferredKey {
            if let value = try? smc.readTemperature(key), value > 0, value < 90 {
                temperatureKey = key
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
            : magSafeLED.smcByte(isCharging: currentSnapshot.isCharging)
        let usesHelper = BatteryHelperClient.shared.isEnabled
        guard applied.needsLED(byte, viaHelper: usesHelper) else { return }
        if usesHelper {
            applied.ledByte = byte
            applied.ledViaHelper = true
            BatteryHelperClient.shared.applyLED(byte) { [weak self] ok, _ in
                guard !ok else { return }
                Task { @MainActor in
                    guard let self, self.applied.ledByte == byte,
                        self.applied.ledViaHelper == true
                    else { return }
                    self.applied.clearLED()
                }
            }
            return
        }
        do {
            try smc.writeU8("ACLC", byte)
            applied.ledByte = byte
            applied.ledViaHelper = false
        } catch SMCClientError.notPrivileged {
            // Retrying every tick cannot succeed without the helper; a helper
            // that becomes enabled changes `viaHelper` and triggers a resend.
            Self.log.error("MagSafe LED write not privileged")
            applied.ledByte = byte
            applied.ledViaHelper = false
        } catch {
            Self.log.error("MagSafe LED write failed")
        }
    }

    private func applyIfChanged(_ action: ChargeAction) {
        let usesHelper = BatteryHelperClient.shared.isEnabled
        guard applied.needsAction(action, viaHelper: usesHelper) else { return }
        if apply(action, usesHelper: usesHelper) {
            applied.action = action
            applied.actionViaHelper = usesHelper
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
                    // A helper reply is a real result, so unlike the generic
                    // direct-SMC path it may replace the setup message; an
                    // in-flight install/repair still owns it.
                    if !self.helperBusy {
                        self.helperSetupMessage = ok ? nil : (err ?? "Helper write failed")
                    }
                    if !ok, self.applied.action == action, self.applied.actionViaHelper == true {
                        self.applied.clearAction()
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
                    "macOS blocked the charge-limit write. Install the battery helper and approve it in System Settings → General → Login Items so the \(limit)% limit can apply."
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

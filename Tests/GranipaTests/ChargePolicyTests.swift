import Testing

@testable import Granipa

@Suite struct ChargePolicyTests {
    @Test func clampsLimit() {
        #expect(ChargePolicy.clampedLimit(10) == 50)
        #expect(ChargePolicy.clampedLimit(80) == 80)
        #expect(ChargePolicy.clampedLimit(150) == 100)
    }

    @Test func inhibitsAtOrAboveLimit() {
        #expect(
            ChargePolicy.action(
                percent: 80, limit: 80, topUp: false, discharging: false, chargingAllowed: true)
                == .inhibit)
        #expect(
            ChargePolicy.action(
                percent: 92, limit: 80, topUp: false, discharging: false, chargingAllowed: true)
                == .inhibit)
    }

    @Test func chargesBelowHysteresis() {
        #expect(
            ChargePolicy.action(
                percent: 78, limit: 80, topUp: false, discharging: false, chargingAllowed: false)
                == .charge)
    }

    @Test func deadbandKeepsCurrentGate() {
        #expect(
            ChargePolicy.action(
                percent: 79, limit: 80, topUp: false, discharging: false, chargingAllowed: false)
                == .inhibit)
        #expect(
            ChargePolicy.action(
                percent: 79, limit: 80, topUp: false, discharging: false, chargingAllowed: true)
                == .charge)
    }

    @Test func topUpChargesUntilFull() {
        #expect(
            ChargePolicy.action(
                percent: 90, limit: 80, topUp: true, discharging: false, chargingAllowed: false)
                == .charge)
        #expect(
            ChargePolicy.action(
                percent: 100, limit: 80, topUp: true, discharging: false, chargingAllowed: true)
                == .inhibit)
    }

    @Test func dischargeOverridesLimit() {
        #expect(
            ChargePolicy.action(
                percent: 90, limit: 80, topUp: false, discharging: true, chargingAllowed: true)
                == .discharge)
    }

    @Test func heatPausedInhibits() {
        #expect(
            ChargePolicy.action(
                percent: 50, limit: 80, topUp: true, discharging: false, chargingAllowed: true,
                heatPaused: true) == .inhibit)
    }

    @Test func calibrationSequence() {
        #expect(CalibrationPolicy.action(step: .chargeTo100, percent: 40) == .charge)
        #expect(CalibrationPolicy.advance(step: .chargeTo100, percent: 100, holdElapsed: 0) == .go(.dischargeTo10))
        #expect(CalibrationPolicy.advance(step: .dischargeTo10, percent: 10, holdElapsed: 0) == .go(.chargeTo100Again))
        #expect(CalibrationPolicy.advance(step: .chargeTo100Again, percent: 100, holdElapsed: 0) == .go(.hold1h))
        #expect(CalibrationPolicy.advance(step: .hold1h, percent: 100, holdElapsed: 10) == .stay)
        #expect(
            CalibrationPolicy.advance(step: .hold1h, percent: 100, holdElapsed: 3600)
                == .go(.dischargeTo75))
        #expect(CalibrationPolicy.advance(step: .dischargeTo75, percent: 75, holdElapsed: 0) == .finished)
        #expect(CalibrationPolicy.action(step: .hold1h, percent: 100) == .charge)
    }

    @Test func magSafeAlwaysOnUsesOrangeWhenCharging() {
        #expect(MagSafeLEDMode.alwaysOn.smcByte(isCharging: true) == 4)
        #expect(MagSafeLEDMode.alwaysOn.smcByte(isCharging: false) == 3)
        #expect(MagSafeLEDMode.off.smcByte(isCharging: true) == 1)
        #expect(MagSafeLEDMode.system.smcByte(isCharging: true) == 0)
    }

    @Test func smcParamStructIsEightyBytes() {
        #expect(SMCClient.paramStride == 80)
    }
}

import Foundation
import Testing
@testable import Granipa

@Suite("Battery helper setup message")
@MainActor
struct BatteryHelperSetupMessageTests {

    @Test("repairHelper surfaces install failure then success in helperSetupMessage")
    func repairHelperSurfacesInstallFailureThenSuccessMessage() async {
        let service = BatteryService()

        service.performHelperRepair = {
            throw BatteryHelperError.install("launchd refused")
        }
        await service.repairHelper()
        #expect(service.helperSetupMessage == "launchd refused")

        service.performHelperRepair = { }
        await service.repairHelper()
        #expect(service.helperSetupMessage == nil)
        #expect(service.controlMessage == "Battery helper registered.")
    }

    @Test("repairHelper reports progress while the injected repair executes")
    func repairHelperReportsProgressWhileRepairExecutes() async {
        let service = BatteryService()

        service.performHelperRepair = {
            #expect(service.helperSetupMessage == "Repairing the battery helper…")
        }
        await service.repairHelper()
        #expect(service.helperSetupMessage == nil)
        #expect(service.controlMessage == "Battery helper registered.")
    }
}

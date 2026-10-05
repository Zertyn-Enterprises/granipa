import Foundation
import ServiceManagement
import Testing

@testable import Granipa

@Suite struct LegacyBatteryHelperTests {
    @Test func unregistersOnlyAnExistingRegistration() {
        #expect(LegacyBatteryHelper.needsUnregister(.enabled))
        #expect(LegacyBatteryHelper.needsUnregister(.requiresApproval))
        #expect(!LegacyBatteryHelper.needsUnregister(.notRegistered))
        #expect(!LegacyBatteryHelper.needsUnregister(.notFound))
    }

    @Test func bundledPlistKeepsTheRegisteredLabel() throws {
        let plist = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/\(LegacyBatteryHelper.plistName)")
        let data = try Data(contentsOf: plist)
        let dict = try #require(
            try PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any])
        #expect(dict["Label"] as? String == "com.zertyn.granipa.batteryhelper")
        // The root daemon must stay on-demand only: it ships for unregistering.
        #expect(dict["RunAtLoad"] == nil)
        #expect(dict["KeepAlive"] == nil)
        #expect(dict["MachServices"] != nil)
    }
}

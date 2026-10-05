import Darwin

// Transitional stub: battery control was removed. It only keeps the bundled
// launchd plist a valid descriptor while LegacyBatteryHelper unregisters the
// daemon earlier builds registered. Nothing connects to it; if launched, it exits.
exit(EXIT_SUCCESS)

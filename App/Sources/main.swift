import AppKit

// Raw SPM binaries are not .app bundles; set a stable name for the Dock/crash reporter.
if Bundle.main.bundleIdentifier == nil || Bundle.main.bundleIdentifier?.isEmpty == true {
    // Best-effort identity when launched outside a bundle.
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()

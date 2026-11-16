# SwiftUI shell (Xcode)

Full Xcode is required for SwiftUI macros (`@State`, etc.). The runnable app on Command Line Tools is `App/Sources` (AppKit).

When Xcode is installed, open a generated project (`swift package generate-xcodeproj` is deprecated — use `xed .` / open Package.swift) and point the app target at these sources, or migrate scenes from here onto the AppKit state object.

import AppKit

// Strong reference prevents delegate from being deallocated
private var appDelegate: AppDelegate!

autoreleasepool {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    appDelegate = AppDelegate()
    app.delegate = appDelegate
    app.run()
}

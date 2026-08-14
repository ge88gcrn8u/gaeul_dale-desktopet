import AppKit
import SpriteKit
import QuartzCore
import CoreGraphics
import os

class PetView: SKView, SKSceneDelegate {

    private static let log = Logger(subsystem: "com.squirrelpet.dale", category: "PetView")

    private var squirrelNode: SquirrelNode!
    private var animManager: AnimationManager!
    private var isDragging = false
    private var dragStartPoint = CGPoint.zero
    private var windowStartOrigin = CGPoint.zero

    private let store = ReminderStore.shared
    private let scheduler = ReminderScheduler.shared
    private let dialogue = EncouragementDialogue.shared

    /// One-shot idle-comfort timer: after a long stretch without interaction,
    /// DAL-E softly says a warm message (then reschedules).
    private var idleComfortWorkItem: DispatchWorkItem?
    private let idleComfortDelay: TimeInterval = 5 * 60

    /// Render-health watchdog: SpriteKit's display link can die after display
    /// sleep (CVDisplayLink error -6661 / "no drawables available"), freezing
    /// the pet while clicks still register. Detect it by watching the per-frame
    /// `update` callback and rebuild the scene when no frame is rendered.
    private var lastRenderedTime: CFTimeInterval = 0
    private var lastRebuildTime: CFTimeInterval = 0
    private var watchdogTimer: Timer?
    private let renderStallThreshold: TimeInterval = 5.0
    private let rebuildCooldown: TimeInterval = 30.0

    /// True after a scene-only rebuild happened but no frame was rendered yet.
    /// When the light-weight scene rebuild fails to recover (the SKView's Metal
    /// drawable pool is gone after display sleep), escalate to recreating the
    /// whole SKView — re-presenting scenes on the same dead view cannot help.
    private var sceneRebuiltSinceLastFrame = false

    /// Fatal-stall escalation hook: PetWindow swaps in a brand-new PetView
    /// (fresh SKView → fresh CVDisplayLink / Metal drawables).
    var onFatalStall: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        allowsTransparency = true
        ignoresSiblingOrder = true
        preferredFramesPerSecond = 30
        setupScene()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupScene() {
        let scene = SKScene(size: bounds.size)
        scene.scaleMode = .aspectFit
        scene.backgroundColor = .clear
        scene.anchorPoint = CGPoint(x: 0, y: 0)
        scene.delegate = self
        squirrelNode = SquirrelNode()
        squirrelNode.position = CGPoint(x: scene.size.width / 2, y: scene.size.height * 0.22)
        scene.addChild(squirrelNode)
        presentScene(scene)
        animManager = AnimationManager(squirrelNode: squirrelNode, scene: scene, view: self)

        // SpriteKit's SKView can lose its Metal drawables after display
        // sleep/wake ("SKView: no drawables available for rendering…"), which
        // freezes every animation & bubble while AppKit UI (right-click menu)
        // keeps working. Recover rendering whenever the display wakes or the
        // screen parameters change.
        NotificationCenter.default.addObserver(
            self, selector: #selector(recoverRendering),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(recoverRendering),
            name: NSWorkspace.didWakeNotification, object: nil)

        // Reminder integration: wake / calm DAL-E via the existing animation.
        dialogue.attach(scene: scene, squirrel: squirrelNode)
        dialogue.onSceneActivity = { [weak self] active in self?.animManager.setExternalActivity(active) }
        scheduler.onActivate = { [weak self] _ in self?.wakeForReminder() }
        scheduler.onIdle = { [weak self] in self?.calmReminder() }

        // A warm message also triggers the soft hug animation.
        dialogue.onComfort = { [weak self] in self?.animManager.playComfortHug() }

        // Occasionally comfort the user after a long quiet stretch.
        scheduleIdleComfort()

        // Watch for a frozen render loop (display sleep can kill SpriteKit's
        // display link on macOS) and rebuild the scene if frames stop.
        startRenderWatchdog()

        // Small welcome message once at launch (skipped if a reminder is already due).
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, !self.scheduler.hasActiveReminder else { return }
            self.dialogue.say(.appOpen)
        }
    }

    // MARK: - Reminder wake / calm

    private func wakeForReminder() {
        (window as? PetWindow)?.raiseForReminder()
        animManager.startReminderJump()
    }

    private func calmReminder() {
        (window as? PetWindow)?.restoreLevel()
        animManager.stopReminderJump()
    }

    // MARK: - Display wake / screen change recovery

    /// Called on display wake / screen-parameter change. Forces the SKView to
    /// rebuild its Metal drawable pool (presenting through a blank scene), so
    /// animations & bubbles render again after the known "no drawables
    /// available" stall that follows display sleep on macOS.
    @objc private func recoverRendering() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let scene = self.scene else { return }
            PetView.log.info("🖥️ Display wake/change — recovering SKView rendering")
            self.isPaused = false
            scene.isPaused = false
            let blank = SKScene(size: scene.size)
            blank.scaleMode = scene.scaleMode
            blank.backgroundColor = scene.backgroundColor
            blank.anchorPoint = scene.anchorPoint
            self.presentScene(blank)
            self.presentScene(scene)
            self.needsDisplay = true
            // Keep the fresh scene rendering until its first frame is drawn.
            self.animManager?.resetFirstFramePause()
            self.animManager?.resumeAfterDisplayChange()
        }
    }

    // MARK: - Render-health watchdog

    /// SKSceneDelegate — called by SpriteKit once per rendered frame.
    func update(_ currentTime: TimeInterval, for scene: SKScene) {
        lastRenderedTime = CACurrentMediaTime()
        // Any rendered frame means the render loop is healthy again.
        sceneRebuiltSinceLastFrame = false
        // Let the animation manager pause rendering for idle once this scene
        // has actually drawn its first frame (idempotent, cheap).
        animManager?.markFirstFrameRendered()
    }

    private func startRenderWatchdog() {
        stopRenderWatchdog()
        lastRenderedTime = CACurrentMediaTime()
        let t = Timer(timeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.checkRenderHealth()
        }
        RunLoop.main.add(t, forMode: .common)
        watchdogTimer = t
    }

    private func stopRenderWatchdog() {
        watchdogTimer?.invalidate()
        watchdogTimer = nil
    }

    private func checkRenderHealth() {
        // While the display is asleep, SpriteKit legitimately stops rendering.
        if CGDisplayIsAsleep(CGMainDisplayID()) != 0 {
            lastRenderedTime = CACurrentMediaTime()
            return
        }
        // The scene is intentionally paused during idle stretches (power save);
        // that is not a render stall.
        if scene?.isPaused == true {
            lastRenderedTime = CACurrentMediaTime()
            return
        }
        let now = CACurrentMediaTime()
        let idle = now - lastRenderedTime
        guard idle > renderStallThreshold else { return }

        // A scene-only rebuild already failed to restore rendering: the SKView's
        // Metal drawable pool is dead, so presenting another scene on the same
        // view will never draw. Recreate the SKView itself for a fresh renderer.
        if sceneRebuiltSinceLastFrame {
            guard now - lastRebuildTime > renderStallThreshold else { return }
            PetView.log.error("🚨 Scene rebuild did not recover (no frame for \(idle, privacy: .public)s) — recreating SKView")
            stopRenderWatchdog()
            onFatalStall?()
            return
        }

        guard now - lastRebuildTime > rebuildCooldown else {
            PetView.log.error("🚨 SpriteKit still frozen (no frame for \(idle, privacy: .public)s) — retry later")
            return
        }
        lastRebuildTime = now
        sceneRebuiltSinceLastFrame = true
        PetView.log.error("🚨 SpriteKit frozen — no frame for \(idle, privacy: .public)s — rebuilding scene")
        rebuildScene()
    }

    /// Heavy recovery: rebuild the scene + sprite from scratch so SpriteKit
    /// creates a fresh CVDisplayLink (the old one is dead after display sleep).
    private func rebuildScene() {
        idleComfortWorkItem?.cancel()
        idleComfortWorkItem = nil

        let size = bounds.size
        squirrelNode?.removeFromParent()
        squirrelNode = SquirrelNode()
        squirrelNode.position = CGPoint(x: size.width / 2, y: size.height * 0.22)

        let scene = SKScene(size: size)
        scene.scaleMode = .aspectFit
        scene.backgroundColor = .clear
        scene.anchorPoint = CGPoint(x: 0, y: 0)
        scene.delegate = self
        scene.addChild(squirrelNode)

        presentScene(scene)
        animManager = AnimationManager(squirrelNode: squirrelNode, scene: scene, view: self)

        dialogue.attach(scene: scene, squirrel: squirrelNode)
        dialogue.onSceneActivity = { [weak self] active in self?.animManager.setExternalActivity(active) }
        dialogue.onComfort = { [weak self] in self?.animManager.playComfortHug() }
        scheduler.onActivate = { [weak self] _ in self?.wakeForReminder() }
        scheduler.onIdle = { [weak self] in self?.calmReminder() }
        scheduleIdleComfort()

        // A reminder that is still active should keep jumping after the rebuild.
        if scheduler.hasActiveReminder {
            animManager.startReminderJump()
        }
        lastRenderedTime = CACurrentMediaTime()
    }

    // MARK: - Reminder interaction

    private func presentReminderInteraction(_ reminder: Reminder) {
        let choice = ReminderUI.presentInteraction(for: reminder)

        switch choice {
        case .complete:
            store.completeCycle(id: reminder.id)
            scheduler.stopActive()
            dialogue.say(.reminderCompleted)

        case .snooze:
            if let newDate = ReminderUI.presentSnoozeOptions(for: reminder) {
                store.reschedule(id: reminder.id, to: newDate)
                scheduler.stopActive()
            }

        case .edit:
            if let draft = ReminderUI.presentEditForm(for: reminder) {
                store.update(id: reminder.id, draft: draft)
                scheduler.stopActive()
            }

        case .delete:
            let confirm = NSAlert()
            confirm.messageText = "🗑 删除提醒"
            confirm.informativeText = "确定删除「\(reminder.title)」吗？"
            confirm.addButton(withTitle: "删除")
            confirm.addButton(withTitle: "取消")
            if confirm.runModal() == .alertFirstButtonReturn {
                store.delete(id: reminder.id)
                scheduler.stopActive()
            }
        }

        scheduler.remindersChanged()
    }

    // MARK: - Idle comfort

    private func scheduleIdleComfort() {
        idleComfortWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if !self.scheduler.hasActiveReminder {
                self.dialogue.sayRandomComfort()
            }
            self.scheduleIdleComfort()
        }
        idleComfortWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + idleComfortDelay, execute: item)
    }

    deinit {
        idleComfortWorkItem?.cancel()
        stopRenderWatchdog()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - Hit testing

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let scene = scene, animManager != nil else { return nil }
        return isPointOnSquirrel(scene.convertPoint(fromView: point)) ? self : nil
    }

    private func isPointOnSquirrel(_ p: CGPoint) -> Bool {
        guard let s = squirrelNode else { return false }
        let dx = (p.x - s.position.x) / 55
        let dy = (p.y - s.position.y) / 80
        return dx * dx + dy * dy < 1.0
    }

    // MARK: - Mouse events

    override func mouseDown(with event: NSEvent) {
        scheduleIdleComfort()
        guard let scene = scene else { return }
        let sp = scene.convertPoint(fromView: convert(event.locationInWindow, from: nil))
        let onSquirrel = isPointOnSquirrel(sp)
        PetView.log.info("🖱️ mouseDown onSquirrel=\(onSquirrel, privacy: .public) scenePos=(\(sp.x, privacy: .public), \(sp.y, privacy: .public))")
        if onSquirrel {
            isDragging = false
            dragStartPoint = event.locationInWindow
            if let w = window { windowStartOrigin = w.frame.origin }
        } else { super.mouseDown(with: event) }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let w = window else { return }
        let dx = event.locationInWindow.x - dragStartPoint.x
        let dy = event.locationInWindow.y - dragStartPoint.y
        guard abs(dx) > 2 || abs(dy) > 2 else { return }
        isDragging = true
        var o = windowStartOrigin; o.x += dx; o.y += dy
        if let s = w.screen ?? NSScreen.main {
            let sf = s.visibleFrame, ws = w.frame.size
            o.x = max(sf.minX, min(o.x, sf.maxX - ws.width))
            o.y = max(sf.minY, min(o.y, sf.maxY - ws.height))
        }
        w.setFrameOrigin(o)
    }

    override func mouseUp(with event: NSEvent) {
        PetView.log.info("🖱️ mouseUp isDragging=\(self.isDragging, privacy: .public) activeReminder=\(self.scheduler.activeReminder?.title ?? "nil", privacy: .public)")
        if isDragging {
            if let w = window {
                UserDefaults.standard.set("\(w.frame.origin.x),\(w.frame.origin.y)", forKey: "PetWindowOrigin")
            }
            dialogue.sayRandomPlayful()
        } else if let reminder = scheduler.activeReminder {
            // A reminder is due → show the reminder interaction instead of idle play.
            presentReminderInteraction(reminder)
        } else {
            // Clicking DAL-E = a warm hug with a random comfort message.
            dialogue.sayRandomComfort()
        }
        isDragging = false
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let scene = scene else { return }
        let sp = scene.convertPoint(fromView: convert(event.locationInWindow, from: nil))
        let onSquirrel = isPointOnSquirrel(sp)
        PetView.log.info("🖱️ rightMouseDown onSquirrel=\(onSquirrel, privacy: .public)")
        if onSquirrel { showContextMenu(at: event) }
    }

    // MARK: - Context menu

    private func showContextMenu(at event: NSEvent) {
        let menu = NSMenu()
        let title = NSMenuItem(title: "🐿️ Dal-E", action: nil, keyEquivalent: "")
        title.isEnabled = false
        title.attributedTitle = NSAttributedString(string: "🐿️ Dal-E", attributes: [.font: NSFont.boldSystemFont(ofSize: 14)])
        menu.addItem(title); menu.addItem(.separator())

        let pause = NSMenuItem(title: animManager.isPaused ? "▶️ 继续动画" : "⏸️ 暂停动画", action: #selector(togglePause), keyEquivalent: "")
        pause.target = self; menu.addItem(pause)

        let show = NSMenuItem(title: "👁️ 重新显示", action: #selector(reShow), keyEquivalent: "")
        show.target = self; menu.addItem(show)
        menu.addItem(.separator())

        let chat = NSMenuItem(title: "💬 打开对话", action: #selector(openChat), keyEquivalent: "")
        chat.target = self; menu.addItem(chat)

        let garden = NSMenuItem(title: "🌰 提醒花园", action: #selector(openGarden), keyEquivalent: "")
        garden.target = self; menu.addItem(garden)

        let reminders = NSMenuItem(title: "⏰ 提醒", action: nil, keyEquivalent: "")
        reminders.submenu = buildRemindersMenu()
        menu.addItem(reminders)
        menu.addItem(.separator())

        let login = NSMenuItem(title: LoginItemManager.shared.isLoginItemEnabled ? "✅ 开机启动" : "☐ 开机启动", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self; menu.addItem(login)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self; menu.addItem(quit)

        if let w = window {
            menu.popUp(positioning: nil, at: w.convertPoint(toScreen: event.locationInWindow), in: nil)
        }
    }

    private func buildRemindersMenu() -> NSMenu {
        let sub = NSMenu()
        let create = NSMenuItem(title: "＋ 创建提醒", action: #selector(createReminder), keyEquivalent: "")
        create.target = self
        sub.addItem(create)

        let pending = store.pending.sorted { $0.scheduledAt < $1.scheduledAt }
        if !pending.isEmpty {
            sub.addItem(.separator())
            for r in pending {
                let prefix = r.isRecurring ? "🔁" : "🗑"
                let item = NSMenuItem(title: "\(prefix) \(r.scheduleSummary) · \(r.title)", action: #selector(deleteReminder(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = r.id
                sub.addItem(item)
            }
        }
        return sub
    }

    @objc private func createReminder() {
        guard let _ = ReminderUI.presentCreationForm() else { return }
        scheduler.remindersChanged()
        dialogue.say(.reminderCreated)
    }

    @objc private func deleteReminder(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        store.delete(id: id)
        scheduler.remindersChanged()
    }

    @objc private func openChat() {
        (NSApp.delegate as? AppDelegate)?.openChat()
    }

    @objc private func openGarden() {
        (NSApp.delegate as? AppDelegate)?.openGarden()
    }

    @objc private func togglePause() { animManager.togglePause() }
    @objc private func toggleLoginItem() { LoginItemManager.shared.toggle() }
    @objc private func quitApp() { NSApplication.shared.terminate(nil) }

    @objc private func reShow() {
        guard let w = window else { return }
        w.orderOut(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { w.makeKeyAndOrderFront(nil) }
    }
}

import SpriteKit

/// Energy-optimized animation manager.
/// - The scene/view is fully paused whenever DAL-E has nothing to animate, so
///   SpriteKit does NOT render at 30 fps during idle stretches (the biggest
///   power drain of a desktop pet).
/// - Idle micro-animations (blink / nudge) are scheduled with wall-clock
///   DispatchWorkItems instead of SKAction.wait chains, so the render loop
///   does not need to stay alive between animations.
/// - No repeatForever (one-shot actions with rescheduling).
class AnimationManager {

    private let squirrel: SquirrelNode
    private let scene: SKScene
    private let view: SKView
    private var isActionPlaying = false
    private var isPausedState = false

    /// True while DAL-E is jumping for an active reminder.
    private(set) var isReminderJumping = false

    /// Idle blink / nudge wall-clock schedulers. These survive scene pauses
    /// because DispatchWorkItem does not depend on the render loop.
    private var blinkWorkItem: DispatchWorkItem?
    private var nudgeWorkItem: DispatchWorkItem?

    /// True while a blink / nudge animation is actually playing (scene unpaused).
    private var isIdleAnimating = false

    /// Other scene users (e.g. a speech bubble) that need the render loop.
    private var externalActivityCount = 0

    /// Becomes true after the first frame is actually drawn. We must never pause
    /// the view before that, or a freshly presented scene would stay invisible.
    private var hasRenderedFrame = false

    var isPaused: Bool { isPausedState }

    // MARK: - Init

    init(squirrelNode: SquirrelNode, scene: SKScene, view: SKView) {
        self.squirrel = squirrelNode
        self.scene = scene
        self.view = view
        startIdleChains()
    }

    // ═══════════════════════════════════════════
    //  ⚡ Idle — wall-clock scheduling, rendering paused in between
    // ═══════════════════════════════════════════

    private func startIdleChains() {
        scheduleBlink()
        scheduleNudge()
        applyIdlePause()
    }

    private func stopIdleChains() {
        blinkWorkItem?.cancel()
        blinkWorkItem = nil
        nudgeWorkItem?.cancel()
        nudgeWorkItem = nil
        applyIdlePause()
    }

    /// Pause the render loop whenever nothing needs to be drawn. This is what
    /// stops SpriteKit from burning CPU/GPU at 30 fps while DAL-E is idle.
    private func applyIdlePause() {
        let shouldPause = hasRenderedFrame
            && !isActionPlaying && !isReminderJumping && !isIdleAnimating
            && externalActivityCount == 0
        if scene.isPaused != shouldPause { scene.isPaused = shouldPause }
        if view.isPaused != shouldPause { view.isPaused = shouldPause }
    }

    /// Called from SKSceneDelegate.update on the first rendered frame, so the
    /// idle pause only engages once the pet is actually visible.
    func markFirstFrameRendered() {
        guard !hasRenderedFrame else { return }
        hasRenderedFrame = true
        applyIdlePause()
    }

    /// Called after a scene is re-presented (display-wake recovery): keep the
    /// view unpaused until the fresh scene draws its first frame.
    func resetFirstFramePause() {
        hasRenderedFrame = false
        applyIdlePause()
    }

    /// Called by the speech bubble when it needs the render loop alive.
    func setExternalActivity(_ active: Bool) {
        externalActivityCount = max(0, externalActivityCount + (active ? 1 : -1))
        applyIdlePause()
    }

    // ── Blink (every 4–10 s) ──

    private func scheduleBlink() {
        blinkWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.blinkWorkItem = nil
            self?.runBlink()
        }
        blinkWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval.random(in: 4.0...10.0), execute: item)
    }

    private func runBlink() {
        guard !isPausedState, !isActionPlaying, !isReminderJumping, !isIdleAnimating else { scheduleBlink(); return }
        isIdleAnimating = true
        applyIdlePause()
        squirrel.wholeNode.run(SKAction.sequence([
            SKAction.scaleY(to: 0.85, duration: 0.06),
            SKAction.wait(forDuration: 0.04),
            SKAction.scaleY(to: 1.0,  duration: 0.08),
            SKAction.run { [weak self] in
                guard let self else { return }
                self.isIdleAnimating = false
                self.applyIdlePause()
                self.scheduleBlink()
            }
        ]))
    }

    // ── Idle nudge (every 12–22 s, tiny shift so it doesn't look frozen) ──

    private func scheduleNudge() {
        nudgeWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.nudgeWorkItem = nil
            self?.runNudge()
        }
        nudgeWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval.random(in: 12.0...22.0), execute: item)
    }

    private func runNudge() {
        guard !isPausedState, !isActionPlaying, !isReminderJumping, !isIdleAnimating else { scheduleNudge(); return }
        isIdleAnimating = true
        applyIdlePause()
        squirrel.wholeNode.run(SKAction.sequence([
            SKAction.moveBy(x: 0, y: 2, duration: 0.4),
            SKAction.moveBy(x: 0, y: -2, duration: 0.4),
            SKAction.run { [weak self] in
                guard let self else { return }
                self.isIdleAnimating = false
                self.applyIdlePause()
                self.scheduleNudge()
            }
        ]))
    }

    // ═══════════════════════════════════════════
    //  Happy Jump keyframes (also reused by the reminder jump)
    // ═══════════════════════════════════════════

    private func finishAction() {
        isActionPlaying = false
        startIdleChains()
    }

    private func makeHappyJumpAction() -> SKAction {
        let squash  = SKAction.scaleY(to: 0.80, duration: 0.12)
        let stretch = SKAction.group([
            SKAction.moveBy(x: 0, y: 55, duration: 0.35),
            SKAction.scaleY(to: 1.10, duration: 0.35),
        ])
        stretch.timingMode = .easeOut
        let land = SKAction.group([
            SKAction.moveBy(x: 0, y: -55, duration: 0.30),
            SKAction.scaleY(to: 0.85, duration: 0.15),
        ])
        land.timingMode = .easeIn
        let settle = SKAction.scaleY(to: 1.0, duration: 0.3)
        settle.timingMode = .easeOut
        let bounce = SKAction.sequence([
            SKAction.moveBy(x: 0, y: 6, duration: 0.10),
            SKAction.moveBy(x: 0, y: -6, duration: 0.10),
        ])

        return SKAction.sequence([squash, stretch, land, bounce, settle])
    }

    // ═══════════════════════════════════════════
    //  Reminder Jump — reuses the existing happy-jump
    //  keyframes in a loop while a reminder is active.
    // ═══════════════════════════════════════════

    func startReminderJump() {
        guard !isReminderJumping else { return }
        isReminderJumping = true
        stopIdleChains()
        squirrel.wholeNode.removeAllActions()
        runReminderJumpCycle()
    }

    func stopReminderJump() {
        guard isReminderJumping else { return }
        isReminderJumping = false
        squirrel.wholeNode.removeAllActions()
        if !isPausedState { startIdleChains() }
    }

    private func runReminderJumpCycle() {
        guard isReminderJumping else { return }
        squirrel.wholeNode.run(SKAction.sequence([
            makeHappyJumpAction(),
            SKAction.run { [weak self] in self?.runReminderJumpCycle() }
        ]))
    }

    // ═══════════════════════════════════════════
    //  Comfort Hug — soft, gentle (used on click / hug)
    // ═══════════════════════════════════════════

    /// A soft "leaning toward the bubble" hug: small rise, gentle pulse,
    /// light sway, then settle. Never aggressive.
    func playComfortHug() {
        guard !isActionPlaying, !isReminderJumping, !isPausedState else { return }
        isActionPlaying = true
        stopIdleChains()

        let node = squirrel.wholeNode
        let rise = SKAction.moveBy(x: 0, y: 9, duration: 0.5)
        rise.timingMode = .easeInEaseOut
        let pulse = SKAction.sequence([
            SKAction.scale(to: 1.04, duration: 0.35),
            SKAction.scale(to: 0.98, duration: 0.35),
            SKAction.scale(to: 1.0, duration: 0.25),
        ])
        let sway = SKAction.sequence([
            SKAction.rotate(toAngle: 0.05, duration: 0.4),
            SKAction.rotate(toAngle: -0.05, duration: 0.4),
            SKAction.rotate(toAngle: 0, duration: 0.4),
        ])
        sway.timingMode = .easeInEaseOut
        let settle = SKAction.moveBy(x: 0, y: -9, duration: 0.5)
        settle.timingMode = .easeInEaseOut

        node.run(SKAction.sequence([
            SKAction.group([rise, pulse]),
            sway,
            settle,
            SKAction.run { [weak self] in self?.finishAction() }
        ]))
    }

    // ═══════════════════════════════════════════
    //  Pause / Resume
    // ═══════════════════════════════════════════

    func togglePause() {
        isPausedState.toggle()
        if isPausedState {
            stopIdleChains()
            squirrel.wholeNode.isPaused = true
        } else {
            squirrel.wholeNode.isPaused = false
            if !isReminderJumping { startIdleChains() }
        }
    }

    // ═══════════════════════════════════════════
    //  Display wake recovery
    // ═══════════════════════════════════════════

    /// Called after display wake / screen change (PetView.recoverRendering).
    /// Re-applies the pause state to the nodes and makes sure the right
    /// animation loop (reminder jump / idle chains) is running again.
    func resumeAfterDisplayChange() {
        squirrel.wholeNode.isPaused = isPausedState
        if isReminderJumping {
            squirrel.wholeNode.removeAllActions()
            runReminderJumpCycle()
        } else if !isPausedState {
            startIdleChains()
        }
        applyIdlePause()
    }
}

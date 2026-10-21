# Nullgram (was "Tepegram next"): iOS Telegram's logic on Qt Quick

Owner's decision (2026-10-20 evening): rewrite Tepegram (now Nullgram) the way Telegram-iOS works.
Its videos of iOS Telegram (iPhone, iOS 26, 384×848 ~30 fps screen recordings) are in
`~/work/nullgram-ref/videos/` (IMG_0294 chat open, 0295 folders, 0296 tab bar /
liquid glass, 0297 channels + media, 0298 settings, 0299 writing, 0300 context menu edit).
Telegram-iOS source (GPL-2.0, shallow clone): `~/work/nullgram-ref/ios/`.
Tools (`~/work/nullgram-ref/tools/`, run with the STT venv's Python for PyAV plus
`PYTHONPATH=/usr/lib/python3/dist-packages` for Pillow): `motion.py` (stretches of motion),
`sheet.py` (frames on one picture), `strip.py` (one band of the screen over frames),
`edge.py` (a sliding page's edge per frame against model curves).

## Measured / read so far

**Page push/pop** (Display/Source/NavigationTransitionCoordinator.swift):
new page x = width·(1−p); page under x = −0.3·width·p; dim over it alpha 0.15·p; a 16 pt shadow at
the new page's edge, alpha 0.9·p. Push/pop: `.animated(duration: 0.5, curve: .spring)`.
Interactive (edge swipe) completion: duration clamp(distance/velocity, 0.05, 0.2) ease-in-out;
cancel: 0.1 s ease-in-out.

**The spring.** On iOS 26 `.spring` is CASpringAnimation mass 1, stiffness 555.027, damping 47.118
(critically damped, ω = 23.56/s), in real time (UIKitRuntimeUtils/UIKitUtils.m
make26SpringAnimationImpl). Before iOS 26: mass 3, stiffness 1000, damping 500, approximated in
ListViewAnimation.swift as bezier(0.23, 1.0, 0.32, 1.0). **Checked on the video** (IMG_0294,
chat push): page moved 0.36 / 0.60 / 0.77 / 0.88 / 0.93 / 0.97 at 33 ms steps; the iOS 26
spring 1 − (1 + ωt)·e^(−ωt) gives 0.33 / 0.58 / 0.76 / 0.87 / 0.93 / 0.96. Visible motion
≈ 370 ms. Keyboard: the same spring, duration 0.3832 (Telegram tests for that number);
keyboard, input panel and message list rise together.

**Tap → motion.** iOS too waits before the push: row highlighted at once, page starts
≈ 170 ms after the tap, already complete (messages laid out). Ours was 270–300 ms.

**Tab bar** (IMG_0296): tapping a tab swaps the page at once (no slide); only the lens moves,
in ≈ 130 ms, stretched like a drop and bending the icons under its rim, then settles into a
resting fill over ≈ 300 ms. On iOS 26 the lens is Apple's private `_UILiquidLensView`
(TelegramUI/Components/LiquidLens/Sources/LiquidLensView.swift): Telegram only sets it
lifted (on touch: bounds + 4 pt each side, refracting, `warpsContentBelow`) or resting
(fill black 0.1 light / white 0.1 dark) and moves it. We imitate it with our glass bands.

**Folders** (IMG_0295): list slides sideways between folders with the tab capsule, ≈ 0.5 s each.

**Context menu** (IMG_0300; TelegramUI/Components/ContextControllerImpl/Sources/
ContextControllerExtractedPresentationNode.swift, `case .animateIn`): long press → the whole chat
blurs, the message is lifted out and springs to its menu position, reactions row over it, actions
under it. Spring: duration 0.42, damping 104 with makeSpringBounceAnimation's mass 5, stiffness 900
(ζ ≈ 0.78; `animateSpring` sets speed = settlingDuration/duration, so the whole settling (0.615 s at
1e-3) is squeezed into 0.42 s → ω 19.6/s, peak +2 % at 0.25 s — the actions' width on the video fits exactly: a small overshoot — seen on the video, the menu grows from the bubble in ≈ 100 ms and
overshoots a little); content alpha 0→1 in 0.15 s; reaction emojis pop in left to right
(≈ 170 ms over the row). Finger sliding over the items highlights them; "Edit" puts an "Edit
Message" bar over the input.

**Sending** (IMG_0299 ≈ 6.0 s; TelegramUI/Sources/ChatMessageTransitionNode.swift): the text leaves
the field and the new bubble starts exactly where the text was, then goes to its place while the
list moves up by its height. 0.3 s; x and y on different curves (the path bends): vertical
bezier(0.19919, 0.01064, 0.27921, 0.91025), horizontal bezier(0.23, 1.0, 0.32, 1.0). Seen on the
video: in place after ≈ 130 ms. The same video also has the attach sheet ("Recents" gallery from
the foot), a round video being recorded and the profile opened from the header (media tabs).

## Qt Quick on the phone (proto.qml / proto.py)

Runs fullscreen under ztmetro (`QT_QPA_PLATFORM=wayland`). `threaded render loop`.
Push/pop with XAnimator/OpacityAnimator (render thread; NumberAnimation would run on the UI
thread with Python): calm 59–63 fps by frameSwapped, median 16.7 ms. With the UI thread's Python
busy 30 ms of 40: sync=0 for animator frames, but 11–16 frames over 20 ms per motion (look into).
**Pacing is right** (checked 2026-10-20 with WAYLAND_DEBUG): Qt asks `wl_surface.frame` before every
commit and ztmetro answers once per output frame, so commits are 16–17 ms apart (the panel has one
mode, 1440×3040 **60.00 Hz** — `modetest -c`; no higher rate on the S10 5G). The "~120/s" was Qt's
log and the Python hooks on the render thread, not real frames.
**Slow frames** (`proto.py --auto --qt` + `/tmp/gaps.sh`: commit gaps from the Wayland trace, 5–6
push/pops, ~176 frames): calm 2–3 over 20 ms; with 30 ms of Python per 40 ms on the UI thread
(`--busy`) 13; on a thread of its own (`--busythread`) 7–10 — so it is not the GIL but CPU load
(the TDLib build ran on 2 cores at the time). They fall at frames 1–2 of a motion (the page's
delegates made as it turns visible; the CPU still slow: `zgov`, OmonullOS's user-space governor,
looks every 250 ms and steps up only then) and at frames 31–34 (the animators' end: values
written back, bindings, a sync) where the spring has already come to rest, so it is not seen.
For the app: make pages before they move (as v0.5 did), and ask zgov for a touch boost
(input or a ztmetro animation → clusters at their caps for ~1 s; needs root to install).
Measure: `QT_FORCE_STDERR_LOGGING=1 QT_LOGGING_RULES="qt.scenegraph.time.renderloop=true"`
(Qt logs to journald otherwise); never time with Python slots on the render thread (GIL).
Rule for the app: no Python connected to render-thread signals.

## Next
- TDLib on the phone: building (`~/build/td/build.log`).
- Remaining videos (0297 channels/media, 0298 settings, 0299 writing, 0300 context menu).
- Spring as a render-thread easing: fit a BezierSpline to 1 − (1 + ωt)e^(−ωt), or a custom Animator.

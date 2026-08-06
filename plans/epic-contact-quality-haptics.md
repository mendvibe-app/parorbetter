# Epic: Native Contact-Quality Haptics

## Setup status (dev machine: Windows, Godot 4.7.1.stable)

Confirmed as of this doc's last update — don't redo these:
- [x] JDK 17 installed and on PATH
- [x] Godot Android export templates installed for 4.7.1.stable (`android_debug.apk`, `android_release.apk`, `android_source.zip` present in Export Template Manager)

Progress (agent + machine):
- [x] JDK 17, plugin zips staged: `android/plugins/` + `ios/plugins/haptics/`
- [x] Autoload `Haptics` → `scripts/autoload/haptics.gd`; `Haptics.init()` in `main.gd`
- [x] Contact mapping + non-blocking MISS double-pulse + desktop `vibrate_handheld` fallback
- [x] F1 **Haptic medium (smoke)** button; `export_presets` custom build + vibrate=true
- [x] **Editor/MCP verify (2026-08-05):** autoload live; `export_presets` has `gradle_build/use_gradle_build=true`, `plugins/Haptics=true`, `permissions/vibrate=true`; `Haptics.gdap` + `.aar` readable; Play + `game_eval` → `has_native_singleton=false`, path=`fallback_vibrate_handheld`, log `[Haptics] Native plugin not found…` (expected on desktop), no crash
- [x] Android custom-build tree present (`android/` + plugins). Confirm once in editor Export dialog if Gradle ever fails.
- [ ] Smoke export to a **physical Android device** → F1 haptic smoke → then play PERFECT/GOOD/THIN/MISS tiers
- [ ] iOS device (iPhone 7+) same tier feel check

Once device smoke feels distinct tiers, this epic is done for Android; repeat on iPhone 7+.

## Why

Current haptic feedback (`shot_routine.gd:476-485`) only varies **duration**:

```gdscript
func _haptic_impact(contact: ShotResult.ContactQuality) -> void:
	match contact:
		ShotResult.ContactQuality.PERFECT:
			Input.vibrate_handheld(18)
		ShotResult.ContactQuality.GOOD:
			Input.vibrate_handheld(12)
		ShotResult.ContactQuality.THIN, ShotResult.ContactQuality.FAT:
			Input.vibrate_handheld(6)
		_:
			Input.vibrate_handheld(4)
```

This is a real limitation of Godot's built-in API, not a design choice — `Input.vibrate_handheld()` only exposes duration on Android and doesn't expose iOS haptic intensity/sharpness at all. So today, every contact tier *feels* like the same buzz, just clipped shorter or longer.

Real golf doesn't work that way. A pure strike feels clean, crisp, almost nothing — a mishit sends a jarring shock through your hands. To get that distinction on-device we need **native impact-style haptics**, not just duration tricks.

## Solution: integrate `kyoz/godot-haptics`

MIT-licensed, actively maintained, supports both Android and iOS through native `UIImpactFeedbackGenerator` (iOS) and `VibrationEffect` amplitude control (Android) under one GDScript API:

```gdscript
Haptics.light()   # short, crisp — small/light collision
Haptics.medium()  # moderate impact
Haptics.heavy()   # large, forceful impact
```

Repo: https://github.com/kyoz/godot-haptics — latest tagged release is v1.0.6, published as a build specifically labeled "Godot 4.7" with assets `android-template-4.7.zip` and `ios-template-4.7.zip`. Our project is on 4.7.1.stable — a patch version off the plugin's stated target, which is normally a non-issue for a compiled native plugin, but still worth confirming at the smoke-test step rather than assuming. If it turns out incompatible, the repo ships build scripts (`DEVELOP.md`) to rebuild from source — budget time for that only if the smoke test actually fails.

**What each platform actually does under the hood** (confirmed by reading the plugin's native source, not just its README):

- **iOS** (`ios/plugin/haptics/haptics.mm`): calls Apple's real `UIImpactFeedbackGenerator` with `.light` / `.medium` / `.heavy` styles directly — the same native API Apple's own UI uses. This only fires on physical devices with a Taptic Engine (iPhone 7 and later); it silently no-ops on the iOS Simulator and on unsupported hardware — no crash, just nothing happens, which matters for your test plan.
- **Android** (`android/.../Haptics.java` + `HapticsImpactType.java`): on Android 8.0+ (API 26+), it uses `VibrationEffect.createWaveform()` with real graduated amplitudes — Light = 110/255, Medium = 180/255, Heavy = 255/255 — so the three tiers are genuinely different vibration *strength*, not just different length. On Android 7.1 and below it falls back to a legacy on/off pattern with no amplitude control, so older devices will feel a duration difference only. The plugin's manifest already declares the `VIBRATE` permission — nothing for us to add manually beyond enabling the plugin in the export preset.

**One implementation detail that will bite if missed:** the autoload script does not auto-initialize. It exposes `init()` deliberately, and until something calls `Haptics.init()` once at startup, `Haptics.light()/.medium()/.heavy()` all silently no-op and print `[Haptics] Not found plugin...` — this needs to be wired into whatever boot/autoload sequence the game already runs, not called for the first time inside `_haptic_impact()`.

## Contact-tier mapping

| Contact quality | Call | Why |
|---|---|---|
| PERFECT | `Haptics.light()` | Real pure strikes feel like *less*, not more — short, clean, minimal |
| GOOD | `Haptics.medium()` | Solid but not pure — noticeably more present than PERFECT |
| THIN / FAT | `Haptics.heavy()` | The jarring shock of a mishit — this is the tier that should feel *worst*, not weakest |
| MISS (default) | `Haptics.heavy()` twice, ~90ms apart | A distinct "clunk-clunk" pattern so a total miss reads differently from a mishit, without a 4th native style to reach for |

This flips the old mental model (longer buzz = better) to the real one (harshness = badness), consistent with the golf-grounding principle running through the rest of the game's feedback systems.

## Implementation

### 1. Install plugin
See the **Setup status** checklist at the top of this doc for the exact current state and remaining steps on the primary dev machine. Summary for any other machine starting fresh:
- Install JDK 17, confirm Android export templates are installed for the project's Godot version
- Project → Install Android Build Template… (creates `android/`), enable Use Custom Build in the Android export preset
- Download Android + iOS builds from the v1.0.6 release, extract to `android/plugins` and `ios/plugins`
- Enable `Haptics` plugin in both the Android and iOS **export presets** (Project menu, not committable via GDScript — `export_presets.cfg` isn't currently checked into this repo, so this is a manual one-time step in each dev's local Godot editor). The `VIBRATE` permission is already declared in the plugin's own `AndroidManifest.xml` — no separate permission checkbox needed.
- Add the plugin's `autoload` script (`autoload/godot_4/Haptics.gd`) to Project Settings → Autoload, named `Haptics`
- Call `Haptics.init()` once during game boot (see implementation detail above) — this is separate from adding the autoload and easy to miss

### 2. Init call + editor/desktop safety
The plugin's own autoload (`autoload/godot_4/Haptics.gd`) already no-ops safely when the native singleton isn't present — confirmed by reading it directly:

```gdscript
func init():
	if Engine.has_singleton("Haptics"):
		haptics = Engine.get_singleton("Haptics")

func light():
	if not haptics:
		not_found_plugin()   # prints a warning, returns — does not crash
		return
	haptics.light()
```

So the editor/desktop case is already handled — no wrapper code needed for that. Two things we do need to add on top of it:

1. **Call `Haptics.init()` once**, in whatever the game's existing boot/autoload sequence is, before any shot can fire. If this is skipped, every impact call silently no-ops with a console warning — no crash, no error the player sees, just no haptics. This is the most likely "why isn't this working" bug during implementation.
2. **Decide whether to keep the old `Input.vibrate_handheld()` calls as a safety-net fallback** for players on a build where the plugin somehow isn't loaded (e.g. plugin not enabled in export preset for a given build). Product call, not just a technical one: silence-on-failure (current plugin behavior) vs. always-something (duration-only fallback). Recommend picking this explicitly rather than defaulting into it:

```gdscript
func _haptic_impact(contact: ShotResult.ContactQuality) -> void:
	match contact:
		ShotResult.ContactQuality.PERFECT:
			Haptics.light()
		ShotResult.ContactQuality.GOOD:
			Haptics.medium()
		ShotResult.ContactQuality.THIN, ShotResult.ContactQuality.FAT:
			Haptics.heavy()
		_:
			Haptics.heavy()
			await get_tree().create_timer(0.09).timeout
			Haptics.heavy()
```

### 3. Double-pulse timing for MISS
Uses `await get_tree().create_timer(...).timeout`, which requires `_haptic_impact` to become an async-capable call. Confirm this doesn't stall `shot_routine.gd`'s existing flow at line 459 (`_haptic_impact(contact)` is called synchronously today, ahead of the practice-mode branch and `_emit_result`). Recommend firing the MISS double-pulse without blocking the calling function — either `call_deferred` the second pulse or don't `await` inline.

## Out of scope
- Extended styles (Rigid/Soft) beyond what `kyoz/godot-haptics` exposes — the plugin only wraps light/medium/heavy, not the full 5-style iOS set. Revisit only if light/medium/heavy proves insufficiently distinct in playtesting.
- Haptics anywhere outside the impact moment (tempo gesture, menu UI, putting) — this epic is contact-quality only.
- Android amplitude fine-tuning beyond what the plugin's three presets provide.

## Acceptance criteria
- PERFECT, GOOD, and THIN/FAT contact each produce a distinguishable native impact feel on a physical device on **both** platforms — not editor console logs, and not just one platform.
- `Haptics.init()` confirmed called before the first possible shot in a real play session (not just present somewhere in the codebase).
- MISS produces a recognizably different pattern (double pulse) from a single mishit, on both platforms.
- iOS: test device is iPhone 7 or later (Taptic Engine required — anything older will silently produce nothing, which is expected, not a bug).
- Android: test device has amplitude-capable vibration hardware (`vibrator.hasAmplitudeControl()` true — true on effectively all phones from the last several years, but worth a sanity check if testing on an older/budget device where light/medium/heavy might collapse into feeling the same).
- Running in the Godot editor or desktop export does not error or crash.
- No change to existing distance/tempo/scoring systems — this epic only touches `_haptic_impact()` and the new `Haptics` autoload wiring.

## Platform verification checklist (do this, don't assume it)
- [ ] Plugin installed and enabled in both export presets; confirm no editor export errors
- [ ] `Haptics.init()` wired into boot sequence
- [ ] Android build installed on physical device, all 4 tiers felt and distinguishable
- [ ] iOS build installed on physical iPhone 7+, all 4 tiers felt and distinguishable
- [ ] Editor play (desktop) confirmed non-crashing, console shows the plugin's own `[Haptics] Not found plugin` warning rather than any error

## Playtest order
1. Smoke-test plugin install + `Haptics.init()` on a real Android device first (simpler export config) before writing any tier-mapping logic
2. Once confirmed working, wire PERFECT/GOOD tiers only, hit balls of both qualities back-to-back, confirm the light/medium distinction is actually felt (not just theoretically different given the amplitude values)
3. Add THIN/FAT heavy() tier, hit a deliberately fat/thin shot, confirm it reads as "wrong" rather than just "more"
4. Add MISS double-pulse last, whiff on purpose, confirm the pattern is distinguishable from a single mishit buzz
5. Repeat steps 2-4 on a physical iPhone 7+ — do not assume iOS parity from the Android pass, the underlying implementations are completely different native APIs

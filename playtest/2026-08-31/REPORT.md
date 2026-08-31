# Playtest report
- Date / Godot version / renderer / launch command: 2026-08-31 / Godot 4.7.1.stable.official.a13da4feb / project renderer `mobile`, runtime fallback OpenGL 3 (llvmpipe) after Vulkan `VK_KHR_surface` failed / `DISPLAY=:1 godot --path /workspace --display-driver x11`
- Build/commit SHA: `51b512625bc7989fccaf579b9231a6d5cd745567` (`main`)
- Time spent in-game: ~70 minutes wall clock; ~30 minutes of actual clicks in the 405×720 window
- Session video: `playtest/2026-08-31/session_walkthrough.mp4` (22s screenshot walkthrough of screens actually reached). Live 8s clip of the end-state club select: `playtest/2026-08-31/session_live_club_select.mp4`. Full interactive RecordScreen captures did not finalize (incomplete mp4, no moov atom).

## What works
- Launch: `scenes/main.tscn` loads; window “Par or Better (DEBUG)” appears at 405×720 (`window_width_override` / `window_height_override`).
- Title (`Main/UIOverlay/StartScreen`): Survival, 18 Hole Round, Practice Green, Practice Range, Short Game, Club Coach all exist and (when clicked cleanly) load their modes.
- Survival shot loop (first hole): club picker → aim (drag bearing, yellow dispersion circle, Space confirms) → mandatory Practice 1/1 pad → real swing → result glance → next club select. One live shot landed ~15 yd (MISS). HUD lives (3 hearts), hole label, minimap, wind/flag, Menu (when not covered).
- Practice Range: fairway view, swing pad, “DRIVING RANGE / Swings 0”, Menu returns to title.
- Practice Green: vertical line-aim (“LINE AIM · on pin line · Confirm”), cup visible, Menu returns to title.
- Short Game: station picker (“SHORT GAME — pick a station (lie + distance)”) with greenside / fairway / rough / sand rows.
- Club Coach overlay: “CLUB COACH”, Close returns toward title. Logged `9i — avg 15 yd (1 shots)`.
- 18 Hole Round: hole 1 club select with Driver / 3-Wood / Hybrid window, HUD “Card” score style, par 4 Red tees.
- Full bag: toggle expands the bag (Driver through wedges); ★ marks `BallPhysics.pick_club`.
- F1 / on-screen Debug: opens `Main/UIOverlay/DebugPanel` (metrics, lives spin, Hole Out / Ace / Force Perfect / On Green, practice-rep sliders). F1 toggles.
- Left/Right-handed toggle on title flips the golfer sprite and label.
- Window resize 405×720 → 500×900: UI still laid out (canvas stretch `canvas_items` / `expand`). Idle 65s on club select: no freeze, no overlay spawn.
- No hard crash of the remaining Godot process during play.

## What does not work

### Title record box wraps “Survival” into “Suru val”
- Severity: Medium
- Area: `scenes/ui/start_screen.tscn` → `StartScreen/Panel/Hero/RecordBox/Inner/ScoreRow/RecordCol/ScoreLabel` (font size 48, box min width 360)
- What I expected: “Survival —” (or “Survival Hole 1”) on one line.
- What happened: Pixel Operator at 48px wraps inside the record panel: “Suru val -” on first boot; after a run “Survival Hole 1” still breaks badly. “18 Hole —” and “HCP — play 3 rounds” also cram.
- Repro steps:
  1. Boot `DISPLAY=:1 godot --path /workspace`.
  2. Look at the Record box on the title (no click required).
- Repro rate: 1/1
- Evidence: `01_title.png`, `11_title_after_survival.png`
- Log snippet: none
- HYPOTHESIS: `score_label.text = "Survival %s" % surv` at font 48 in a 360px panel; Pixel Operator glyphs are wide. Autowrap with no min-width/ellipsis.

### Practice Range (and Green) `_chosen_club.clear()` hits a read-only Dictionary; Range can skip club pick
- Severity: High
- Area: `scripts/course/hole_controller.gd` `load_range()` line 479 and `load_practice_green()` line 506 (`_chosen_club.clear()`). Range skip path: `_start_shot_ui()` `GameState.range_mode and not _chosen_club.is_empty()` → `_begin_range_swing()`.
- What I expected: Practice Range always opens the club picker (README / GETTING_STARTED: same club pick, then skip aim). Previous Survival club is forgotten.
- What happened: After confirming a Pitching Wedge in Survival and Menu → Practice Range, Range opened already on the swing pad with Pitching Wedge, Swings 0, no picker. Console: `Dictionary is in read-only state` on `clear()`. A later Range entry (after modes that never confirmed a club) did show the picker (Driver ★).
- Repro steps:
  1. Boot game → Survival.
  2. Confirm a club (any) and take at least the aim/swing so `_chosen_club` is assigned.
  3. Menu back to title.
  4. Practice Range.
  5. Note whether CHOOSE CLUB appears or the pad already has the last club.
- Repro rate: 1/2 Range entries (first after a confirmed club: skip; later after Short Game with no club commit: picker shown)
- Evidence: `07_practice_range.png` (PW on pad, Swings 0), `24_range_club_select.png` (later picker), `godot.log`
- Log snippet:
  ```
  ERROR: Dictionary is in read-only state.
     at: clear (core/variant/dictionary.cpp:311)
     [0] load_range (res://scripts/course/hole_controller.gd:479)
  ERROR: Dictionary is in read-only state.
     at: clear (core/variant/dictionary.cpp:311)
     [0] load_practice_green (res://scripts/course/hole_controller.gd:506)
  ```
- HYPOTHESIS: `_chosen_club = club` stores a reference into `const BAG: Array[Dictionary]` in `ball_physics.gd`. Const dicts are read-only in Godot 4.4+, so `.clear()` no-ops and the previous club sticks. Duplicate: practice green (overwritten later by `putter_for`).

### Club-select overlay blocks HUD Menu; Debug stays clickable
- Severity: Medium
- Area: `ClubSelect` (created in `HoleController._setup_club_select`, full-rect `ColorRect` `MOUSE_FILTER_STOP`) vs HUD `MenuButton` (`scripts/ui/hud.gd`) vs `Main/UIOverlay/DebugPanel/DebugButton` (CanvasLayer 20)
- What I expected: Menu always returns to title, including during CHOOSE CLUB.
- What happened: Menu is visible at top-right but the club-select dim eats clicks. Debug sits on a higher canvas layer and still receives clicks, so “click Menu” often opens Debug instead. No Esc/back on club select. Combined with Confirm misses, this felt like a soft-lock (F1 still opens Debug).
- Repro steps:
  1. Boot → Survival (or 18 Hole Round).
  2. On CHOOSE CLUB, click the HUD “Menu” label.
  3. Click the “Debug” chip just below it.
- Repro rate: 1/1 while club select is up. Menu worked from aim / swing / range / green (overlay dismissed).
- Evidence: `03_club_select_survival.png`, `09_18hole_club_select.png`, `20_stuck_club_select.png`
- Log snippet: none
- HYPOTHESIS: ClubSelect is moved to the end of hole `UILayer`, covering HUD Menu. DebugPanel lives on `Main/UIOverlay` layer 20, above the hole.

### Confirm club often does not commit (Full bag / late session)
- Severity: High
- Area: `ClubSelect` `_confirm` (`scripts/shot/club_select.gd` `_commit` / `_refresh_confirm_enabled`). Scene: hole `UILayer/ClubSelect`.
- What I expected: With hint “Confirm to aim with …”, the bottom Confirm button (or a second click after the 0.45s open lock) enters aim.
- What happened: First Survival compact picker did commit (reached aim + practice pad). After Full bag and after Debug Hole Out/Ace, Confirm stayed on screen despite the ready hint. Cursor sat on “Confirm 6-Iron” / “Confirm Driver”; clicks and Space did not advance. Hint showed Driver while ★ stayed on 6i. End of session still on this screen after 65s idle.
- Repro steps:
  1. Boot → Survival.
  2. CHOOSE CLUB → Full bag.
  3. Wait until hint reads “Confirm to aim with …”.
  4. Click the bottom full-width Confirm button (not a club row).
  5. Optional: F1 Debug → Hole Out or Ace → Close → try Confirm again.
- Repro rate: compact 3-club picker 0/1 fail (first hole worked); Full bag / post-debug 2/2 fail in this session
- Evidence: `16_confirm_hit.png`, `20_stuck_club_select.png` / `02_bug_softlock.png`, `21_after_idle.png`, `session_live_club_select.mp4`
- Log snippet: none (no GDScript error on click)
- HYPOTHESIS: `_confirm.disabled` lock (`OPEN_LOCK_SEC` 0.45 / `SWITCH_LOCK_SEC` 0.28) plus Full bag scroll layout; and/or `_process` not clearing the lock after Debug. ★ vs Confirm name is `_selected` (last tap / leftover Driver) vs `pick_club` (6-Iron) with a weak pressed-row style. Not proven as “button permanently disabled” in the theme — it looked enabled.

### Debug chip is on the title and every hole
- Severity: Polish
- Area: `scenes/ui/debug_panel.tscn` `DebugButton` (always `visible = true` in `debug_controls.gd`)
- What I expected: Debug only via F1, or hidden on the start screen.
- What happened: A “Debug” button sits top-right on title and in-game, stacked with Menu.
- Repro steps: Boot; look at title top-right.
- Repro rate: 1/1
- Evidence: `01_title.png`
- Log snippet: none

### Club Coach copy: “1 shots”
- Severity: Polish
- Area: `scripts/ui/coach_screen.gd` (player-facing list)
- What I expected: “1 shot” or an empty state only.
- What happened: “9i — avg 15 yd (1 shots)” and also “Not enough shots yet” on the same card.
- Repro steps: Play one shot → title → Club Coach.
- Repro rate: 1/1
- Evidence: `23_club_coach.png`
- Log snippet: none

### HUD yardage ≠ club-select yardage
- Severity: Low
- Area: HUD `scripts/ui/hud.gd` `refresh()` uses `hole.tee_yards(tee)`; club select uses ball→cup pixels (`HoleController._begin_club_select`)
- What I expected: One distance.
- What happened: Survival HUD “114 YDS” vs picker “109 yd”; 18-hole HUD “316 YDS” vs picker “324 yd”; later Survival “146 YDS” vs “155 yd”.
- Repro steps: Boot → Survival or 18 Hole Round; compare HUD vs CHOOSE CLUB header.
- Repro rate: 1/1 on holes checked
- Evidence: `03_club_select_survival.png`, `09_18hole_club_select.png`, `20_stuck_club_select.png`
- Log snippet: none
- HYPOTHESIS: tee-set card yards vs live pin distance (offset / generator). Confusing, not a blocker.

### README “Practice Swing” button is gone
- Severity: Polish (docs vs build)
- Area: README.md vs `scripts/course/practice_reps_check.py` (“Standalone Practice Swing button gone”); runtime shows “Practice 1/1 — find your tempo”
- What I expected: Optional Practice Swing button as documented.
- What happened: Auto practice rep after Confirm Aim; no standalone button. Tempo still grades.
- Repro steps: Survival → confirm club → confirm aim.
- Repro rate: 1/1
- Evidence: `05_swing_pad_practice.png`
- Log snippet: none

### No pause, options, or audio sliders
- Severity: Low (missing systems, not a regression)
- Area: no pause scene; AudioBus dummy driver this VM
- What I expected: Pass A pause/resume/options.
- What happened: None exist. Menu abandons the run (`main.gd` `_return_to_start` → `GameState.abandon_run()`).
- Repro steps: Play any mode; look for pause / settings.
- Repro rate: 1/1
- Evidence: n/a
- Log snippet: ALSA dummy driver (environment)

### Environment (not a game bug): Vulkan / ALSA fallback
- Severity: n/a (VM)
- Area: DisplayServer / AudioServer
- What I expected: Project `renderer/rendering_method=mobile` and audible SFX.
- What happened: Vulkan instance extension missing → OpenGL 3 llvmpipe. ALSA has no card → dummy audio. Game still rendered.
- Repro steps: Launch on this cloud VM.
- Repro rate: 1/1
- Evidence: `godot.log`
- Log snippet: `VK_KHR_surface not found`; `All audio drivers failed, falling back to the dummy driver.`

## Not tested
- Game over / COURSE CLEAR / ROUND COMPLETE (Debug Hole Out/Ace from club select did not show those panels; lives stayed at 3 hearts; Confirm stuck blocked a natural bogey-out).
- Practice Green actual putt stroke (entered line-aim only).
- Short Game station → shot (picker only).
- 18-hole play past club select; hole-out, scorecard, net HCP.
- Gamepad (none present). Input map only has `debug_toggle` (F1) and `confirm_shot` (Space).
- Audio quality / mute-on-pause (dummy driver; no pause).
- Android / touch / haptics.
- Save/load (no save slot; title “Record” is a best-run stat, not a resume).
- Quit via in-game control (none); window was left running.
- Opposite-direction keyboard (no move actions bound).

## First-run notes
A new player can see six mode buttons and will likely hit Survival. After that the loop is readable (CHOOSE CLUB → AIM → pad) but the 405×720 window plus Pixel Operator wrapping makes “Survival”, club names (8i/3i/9i), and Confirm vs ★ easy to misread. Mandatory Practice 1/1 is the first swing teacher; README’s optional Practice Swing button is not there. Menu vanishing under the picker is the first “am I stuck?” moment.

## Suggested next playtest focus
- Confirm club after Full bag and after F1 Hole Out — does `_commit` fire on device, and does `_chosen_club = BAG[i]` stay read-only?
- Survival to game over (0 lives) and 18-hole round complete, including scorecard.
- Practice Green putt + Short Game station shot on a touch device (pad feel, not mouse).

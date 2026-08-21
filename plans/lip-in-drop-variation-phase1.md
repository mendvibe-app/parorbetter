# Plan — Lip-in drop variation (pour vs toilet-bowl)

**Status:** CODE COMPLETE — device playtest pending.  
**Deliverable on approve:** `plans/lip-in-drop-variation-phase1.md`  
**Scope:** One PR. **Presentation only** — make rate / capture frozen. Horseshoe **lip-out** leave work is separate (do not bundle).  
**User lock:** Mostly **straight pour** for well-paced center lines; rim-curl only on **clear lips**; real-golf grounding + light variation (not every drop identical).

---

## 1. Understanding

Every make currently “toilet bowls” around the cup before dropping. A pure, dying center-cut putt should usually **pour straight in**. Lip-in curl is for balls that catch the edge.

---

## 2. Why it happens (HEAD)

`play_cup_drop` / `cup_drop_total_duration` (`ball.gd`):

```gdscript
const LIP_CENTER_OFFSET_MAX := 0.22   # offset < 0.42 px (capture r=1.9)
const LIP_CENTER_SPEED_MAX := 0.35    # speed < ~11.2 px/s (max capture 32)
# Center drop only if BOTH true; else rim_roll

const LIP_IN_ARC_MIN := TAU * 0.50    # every rim-roll ≥ half turn
const LIP_IN_ARC_MAX := TAU * 0.75
```

Two stacked problems:

1. **Center band is tiny.** Most makes that fall in are either slightly offline (`offset_ratio ≥ 0.22`) or still above ~11 px/s. Real “good” putts often sit in that gap → classified as rim-roll.
2. **Rim-roll floor is a full toilet-bowl.** Arc-length retune made lips readable by forcing ≥½ turn. That is correct for *clear* lips, wrong as the default for every non-perfect capture.

Make rate is unrelated — this is 100% `play_cup_drop` presentation.

---

## 3. Real-golf grounding

Pelz-style make looks (within capture):

| Look | When | Motion |
|------|------|--------|
| **Pour** | Low offset, dying / well-paced | Straight scale-down; little or no orbit |
| **Catch / short lip-in** | Moderate offset or a bit of pace | Short curl (⅛–⅓ turn), then drop |
| **Toilet-bowl lip-in** | High offset and/or hotter make | Long curl (½–¾ turn), then drop |

Variation: two pours are not clones (tiny timing / optional micro-wobble); two lips are not the same arc. Luck = micro-line at the cup we do not simulate — light `randf` *inside* the band set by offset×speed, same philosophy as lip-out leave.

---

## 4. Fix (presentation)

### 4a. Widen the pour band (PLAYTEST)

```gdscript
## PLAYTEST — well-paced center-ish lines pour; clear lips still curl
const LIP_CENTER_OFFSET_MAX := 0.50  ## was 0.22; ~half capture disc
const LIP_CENTER_SPEED_MAX := 0.55   ## was 0.35; ~17.6 px/s of 32
```

Keep **AND** (offset soft **and** speed soft) → pour. Either high offset or still-hot inside the make → curl path.

### 4b. Arc mapping: small arcs for mild lips, bowl only when earned

```gdscript
## PLAYTEST — do not floor every lip at half turn
const LIP_IN_ARC_MIN := TAU * 0.12  ## ~43° — readable nudge, not toilet-bowl
const LIP_IN_ARC_MAX := TAU * 0.75  ## full bowl only at high offset_ratio
```

`arc_rad = lerpf(MIN, MAX, offset_ratio) * lerpf(0.85, 1.15, speed_ratio)` as today, then:

```gdscript
## Light luck inside the geometry band (±~18% arc, clamped to min/max)
arc_rad *= lerpf(0.82, 1.18, randf())
```

Duration still tracks arc (existing curl_dur lerps); optionally scale curl_dur by `abs(arc_rad) / LIP_IN_ARC_MAX` so short curls are quick.

### 4c. Optional pour luck (same PR, small)

~10–15% of **near-threshold pours** (e.g. offset in `[0.35, 0.50)`) get a **short** curl instead of pure pour — “looked center, caught a hair.” Not a coin flip on dead-center dying putts (`offset < 0.25` and `speed_ratio < 0.35` always pour).

```gdscript
var pour := offset_ratio < LIP_CENTER_OFFSET_MAX and speed_ratio < LIP_CENTER_SPEED_MAX
if pour and offset_ratio >= 0.35 and randf() < 0.12:
    pour = false  # promote to short lip-in
    # arc will be near MIN because offset still moderate
```

### 4d. Unchanged

- Stash / `reset_at` / `visual.position` contract  
- `LIP_ORBIT_MAX`, grey overhang  
- Capture predicates, lip-**out** leave model  
- Controllers (still await `cup_drop_total_duration()`)

Update `cup_drop_total_duration()` to use the same pour predicate / curl_dur so banner timing stays matched.

---

## 5. Files

| File | Change |
|------|--------|
| `scripts/ball/ball.gd` | Widen center thresholds; lower `LIP_IN_ARC_MIN`; arc luck; optional near-threshold promote; keep `cup_drop_total_duration` in sync |
| `scripts/course/hole_out_feel_check.py` | Assert new center constants present; `LIP_IN_ARC_MIN` below half-turn (`< 0.35` τ factor); pour path still exists |
| `scripts/ball/cup_lip_out_check.py` | Only if it asserts old `LIP_IN_ARC_MIN >= 0.45` — **relax** to allow short lip-in floor (that assert was for lip-in readability, now wrong) |

---

## 6. Out of scope

- Make rate / `CUP_CAPTURE_*`  
- Lip-out leave (`LIP_OUT_EXIT_*`) — separate uncommitted/shipped work  
- Wind, aim circle, green friction  
- New SFX  

---

## 7. Acceptance

- [ ] Well-paced, near-center putt: **straight pour** most of the time (no half-turn bowl)  
- [ ] Clear edge catch: visible rim-curl; hotter/wider → longer curl  
- [ ] Not every make identical — arc/duration (and rare near-threshold promote) vary  
- [ ] Make rate unchanged  
- [ ] Listed checks pass  
- [ ] Device: practice green — 5 center pours + 3 lip makes, screenshot or feel note  

---

## 8. Go / no-go

**Proceed** with wider pour band, short→long arc mapping (min ~⅛ turn not ½), light geometry-tied luck.

**On approve:** write plan doc under `plans/`, implement one PR (can ship after or beside lip-out leave commit — do not mix concerns in one diff if leave is still dirty).

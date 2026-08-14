# Correction — Club Select, Golf Language Not Percentages

**Track:** correction, prompted by live playtest confusion
**Branch:** `fix/club-select-golf-language`, from main
**Size:** one function, copy/display only. No mechanic change.
**Grounded in:** real golf coaching language, confirmed via search, plus the precision-window
math worked through earlier this session.

---

## The problem

`_club_row_text()` currently shows a bare percentage for any club that isn't close to a full
swing:

```gdscript
// club_select.gd:206
return "%s%s  —  %d yd · %d%% swing%s" % [star, name, int(max_yd), int(pct * 100.0), badge]
```

`68% swing` is accurate and it's exactly the number a launch-monitor app would show — but
it's not something a golfer says or thinks in, and on its own it doesn't tell you what to
*do* with the information. Confirmed directly: a player reading this list has no way to know
that a low percentage means "harder to control precisely," because nothing frames it that
way.

---

## Grounding

**"Three-quarter" is real, established terminology** — not invented for this fix. Multiple
sources confirm it as the standard term for a swing between half and full, specifically used
for control.

**Real coaching gives explicit strategy for exactly this situation, and it argues against
finessing a big reduction:** *"If you're between clubs, pick the longer iron and swing
smoother. Decelerating to 'take distance off' usually creates a thin strike and a flyer."*
That's the real-world version of the precision-window problem worked through earlier this
session — golfers are taught to avoid the low-percentage club, not to get better at
executing it.

**"No-man's land"** is common golf slang for being stuck between clubs with no comfortable
option — worth using specifically for the situation where *every* club in the bag requires
either an awkward reduction or runs through.

---

## The fix

Replace the raw percentage with a real-golf descriptor band. Keep the underlying number
available (tooltip or secondary text) for anyone who wants it, but lead with language a
golfer actually uses:

```gdscript
func _club_row_text(name: String, max_yd: float, is_suggested: bool) -> String:
	var pct := BallPhysics.club_percent_today(_pin_yd, max_yd, _lie, _wind, _severity)
	var star := "★ " if is_suggested else ""
	var badge := _tendency_badge(name)

	if (
		_lie != "Green"
		and not BallPhysics.is_shortest_available(max_yd, _lie)
		and pct < BallPhysics.POWER_POCKET_LO
	):
		return "%s%s  —  %d yd · runs through%s" % [star, name, int(max_yd), badge]

	if pct >= 0.95:
		return "%s%s  —  %d yd%s" % [star, name, int(max_yd), badge]

	# PLAYTEST TARGET: band edges. Grounded in real golf swing-effort language, not
	# an arbitrary percentage — real coaching frames the lowest band as a club to
	# avoid, not a shot to master.
	var descriptor := ""
	if pct >= 0.85:
		descriptor = "smooth"
	elif pct >= 0.70:
		descriptor = "3/4"
	else:
		descriptor = "tight — one more club plays smoother"

	return "%s%s  —  %d yd · %s%s" % [star, name, int(max_yd), descriptor, badge]
```

**The lowest band (`< 0.70`) gets advisory language, not a neutral label** — matching the
real coaching stance that this is a club to avoid, not a shot to learn to finesse. This is
the one place the fix goes beyond a straight vocabulary swap, and it's grounded directly in
the coaching quote above, not invented.

**If every available club falls into the lowest band or "runs through,"** consider a distinct
"no-man's land" callout at the list level rather than per-row — flagged as an option, not
required for this pass; report if it's cheap to add alongside the per-row change.

---

## Out of scope

- `club_percent_today` / `recommended_power` — the underlying calculation is correct and
  confirmed (Phase 5 investigation). This is display language only.
- `pick_club()` / the suggested-club star logic — not touched, though worth a future look at
  whether it already biases toward the "smooth"/"full" band (a related but separate question).
- Any change to swing mechanics, amplitude mapping, or precision.
- Band edges (0.95 / 0.85 / 0.70) are playtest targets, not final — flagged in the code
  comment.

---

## Acceptance criteria

1. No club row displays a bare percentage.
2. Descriptor language matches real golf usage — "3/4," "smooth," not invented terminology.
3. The lowest band reads as advisory ("consider a different club"), not neutral.
4. `runs through` and the ≥95% blank-label convention are unchanged.
5. All `*_check.py` pass — check whether any check asserts the old `%d%% swing` string format
   and update if so.

---

## Playtest verification

1. Open club select for a mid-range approach distance where no club is near-full. Confirm the
   list reads clearly without needing to know what a raw percentage means.
2. Find or construct a "no-man's land" situation (every club either tight or runs-through).
   Note whether the per-row language alone communicates that, or whether it needs the
   list-level callout mentioned above.
3. Over a few holes, see whether this changes which club you reach for — the real test is
   whether it nudges toward the "smooth" choice the way a caddie would, not just whether it
   reads nicely in isolation.

---

## Notes for the agent

- Read this document and confirm understanding before writing code.
- Touch only `club_select.gd`.
- Band edges and the "tight" descriptor's exact wording are playtest targets — report if you
  think a different edge or phrase fits better, but don't invent new golf terminology beyond
  what's grounded above.

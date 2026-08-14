# Correction — Tendency Icons Replace Text Badge

**Status:** SHIPPED — merged to main (`feature/tendency-icons`)

Shipped — seven PixelLab-generated icons for tendency badges, `club_short_name` reused from Club Coach to shrink the row prefix, "ease up" (CAPTION 40) and "it runs" (BODY 48) as the final tight/runs-through copy, all bands confirmed under the 450px budget across the full bag, verified visually in-game. Overflow bug from the original marker-clarity session is now fully closed, not just partially addressed.

**Track:** correction, prompted by a real overflow bug in the club-select row
**Branch:** `feature/tendency-icons`, from main
**Size:** moderate — new art (via PixelLab), a small icon lookup, and a row layout change.
**Sequencing:** ships instead of a quick copy fix, by explicit choice — the overflow stays
broken until this lands, rather than shipping throwaway copy that gets replaced anyway.

---

## What's actually there today

Confirmed by reading the code directly, not assumed:

- `_tendency_badge()` in `club_select.gd` has carried this exact comment since it was written:
  *"Text stub for the tendency icon (Phase 3) — swap for an icon lookup in hud_icons.gd once
  tendency art exists; resolve_tip().tag is already the icon key to use then."* This was
  always meant to become an icon. It just never got built.
- Every tag `resolve_tip()` can return already carries an `icon_id` matching its `tag` —
  `rushed_transition`, `lingering_top`, `slice_tendency`, `hook_tendency`, `contact_issue`,
  `on_track`, `insufficient_data`. The lookup key is already designed in.
- `hud_icons.gd` already exists with a working pattern — `const` dictionaries of
  `preload()`'d 64×64 PNGs plus static lookup functions (`lie_texture()`, `club_texture()`).
  No tendency art or dictionary exists yet.
- `club_select.gd:273-274` already sets `btn.icon = HudIcons.club_texture(name)` with
  `btn.expand_icon = true` on the same row. **`Button.icon` is a single-texture slot, already
  occupied by the club-type icon** — a tendency icon needs its own layout element, not a
  swap into the existing slot.

---

## Why this is the right fix, not just a nice one

Confirmed via screenshot: the row overflows specifically because of two additions — the new
descriptor copy (`"tight — one more club plays smoother"`) and the tendency badge text
(`"· Rushing"`) stacking in the same single-line `Button.text`. Removing the badge text
entirely (not shortening it — removing it, replaced by an icon) takes the single biggest
chunk of text out of the row. It may resolve the overflow outright; if the descriptor text
alone still overflows after this lands, that's a much smaller, separate follow-up.

It also directly answers the question that prompted this: *"is all the information on there
valuable, and what could be an icon instead."* Tendency is the clearest candidate — a glance
at a symbol is faster to parse mid-round than reading a word, and it's already been the
planned design since before this session, not a new idea.

---

## Scope

### 1. Art — routes through PixelLab, not buildable from this chat session

Seven icons, matching the existing 64×64 house pixel-art style (reference `lie_*.png` /
`club_*.png` for palette and weight). One per tag:

| Tag | Concept to convey |
|---|---|
| `rushed_transition` | Rushed, hurried motion — something that reads as "too fast" |
| `lingering_top` | Hesitation, stalling — something that reads as "paused too long" |
| `slice_tendency` | Path curving right |
| `hook_tendency` | Path curving left |
| `contact_issue` | Inconsistent strike — thin/fat pattern |
| `on_track` | Positive, dialed-in — a checkmark-adjacent concept |
| `insufficient_data` | Neutral/unknown — not enough shots logged yet |

**Do not prescribe exact visual designs here** — that's the artist/PixelLab's job, working
from the concept and matching house style. This table defines what each icon needs to
communicate, not how it should look.

### 2. `hud_icons.gd` — extend the existing pattern, don't invent a new one

```gdscript
const TENDENCY := {
	"rushed_transition": preload("res://assets/ui/tendency_rushed.png"),
	"lingering_top": preload("res://assets/ui/tendency_lingering.png"),
	"slice_tendency": preload("res://assets/ui/tendency_slice.png"),
	"hook_tendency": preload("res://assets/ui/tendency_hook.png"),
	"contact_issue": preload("res://assets/ui/tendency_contact.png"),
	"on_track": preload("res://assets/ui/tendency_on_track.png"),
	"insufficient_data": preload("res://assets/ui/tendency_unknown.png"),
}

static func tendency_texture(tag: String) -> Texture2D:
	return TENDENCY.get(tag, null)
```

Same shape as `lie_texture()`/`club_texture()` already in the file — no new pattern.

### 3. `club_select.gd` — row layout, not just a string change

`_tendency_badge()` stops returning appended text. The row needs a second icon element
alongside the existing club-type icon (`btn.icon`), since that slot is already taken.
Concretely: report the cleanest way to add a second small icon to a `Button`-based row in
this codebase — likely a child `TextureRect` positioned in the row, or restructuring the row
from a bare `Button` into a `Button` wrapping an `HBoxContainer` with the club icon, label,
and tendency icon as siblings. **This is a real layout decision — report the approach before
implementing**, since it may touch how rows are constructed more than a one-line change.

`_club_row_text()` drops the badge parameter from its return string entirely — descriptor
copy (`smooth` / `3/4` / `tight — ...`) stays as text, tendency moves to the new icon.

---

## Out of scope

- Shortening the descriptor copy pre-emptively. Only touch it if, after the icon change, the
  row still overflows — report that finding rather than guessing at it now.
- Redesigning the club-type icon or its slot.
- A first-time legend/tooltip explaining what each tendency icon means. Worth flagging as a
  real open question (icons only work if players learn to read them) but not building it in
  this pass — report whether it feels necessary once the icons exist and are visible in
  context.
- `club_percent_today`, `resolve_tip()`, or any tendency-detection logic. Already correct,
  untouched.

---

## Acceptance criteria

1. All seven tendency icons exist, generated to match house pixel-art style.
2. `hud_icons.gd` has a working `tendency_texture()` lookup, same pattern as existing
   functions.
3. Club-select rows show both the club-type icon and a tendency icon (when one applies) as
   distinct elements — not competing for the same `Button.icon` slot.
4. No text badge (`"· Rushing"` etc.) remains in the row string.
5. Report whether the overflow bug is resolved by this change alone, or whether the
   descriptor copy still needs shortening as a small follow-up.
6. All `*_check.py` pass — check whether `club_select_check.py` or any other check asserts
   the old badge-in-string format.

---

## Playtest verification

1. Play until a club shows a tendency (needs `MIN_SAMPLES_FOR_TIP` logged shots on that club)
   — confirm the icon renders, doesn't overlap the club-type icon, and the row no longer runs
   off screen.
2. Glance at a row with a tendency icon without reading any tooltip — can you tell it's
   flagging something about that club, even if you can't yet identify exactly what? That's
   the honest bar for a first pass; full recognition comes with repetition.
3. Confirm rows without a resolved tendency (`insufficient_data` or no data at all) still lay
   out cleanly with no icon or a neutral one.

---

## Notes for the agent

- Read this document and confirm understanding before writing code.
- Art generation requires PixelLab — confirm your session has that connector before starting;
  if not, report back rather than attempting to fake or skip the art step.
- The row layout change (item 3) is the one part of this that isn't fully specified — report
  your proposed approach before implementing, since it affects how every row in this list is
  built.
- Touch `hud_icons.gd`, `club_select.gd`, and new files under `assets/ui/`. Nothing else.

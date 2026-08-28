# Wave E — Pad golfer redo (PixelLab)

**Date:** 2026-08-27  
**Status:** Review only — not promoted to `assets/ui/`

## What failed (do not retry)

Per-pose `create_image_pro` + `edit_image` restyle (`full_restyle/`, `full_swing_restyle_strip_x2.png`): shirt color and body scale drifted every frame.

Batch `edit_image` of the live kit poses onto the address lock (`dd44abe1`): zoomed into heads.

`animate_character` v3 on the lock (`char_v3_swing_strip_x2.png`): scale held, shirt flipped to a green vest + FX after frame 0.

## What to gate

One v3 character from `addr_cand_1`, then **pose states** of that ID with `use_color_palette_from_reference=true`.

- Character: `e820f735-c9fb-46be-b623-9f5271614fd1` (group `7bb314ee`)
- Strip: `char_states_south_strip_x2.png`
- South frames: `char_states/ui_golfer_*.png` (112×168, canvas shared)

| Pose | State id |
|------|----------|
| address (Idle) | `e820f735-c9fb-46be-b623-9f5271614fd1` |
| takeaway | `775b6c1c-8541-4fd7-a4a7-8ff3af5b8f80` |
| mid | `2e2b6327-3256-495c-8417-8711b5b2076c` |
| late | `3695a8db-ac3c-4180-aa76-d8cf8225385c` |
| top | `7d1f2799-62e4-48fb-a638-3806bb4d1d27` |
| early_down | `bacd71f4-6d5c-4e09-b0d4-96e3c84baeb6` |
| impact | `66e0e681-f7a3-4714-bf6a-3abada4d71cb` |
| follow | `c684328c-7b8c-415f-805a-c868d3070026` |

Feet y ≈ 132–137 on a 168 canvas. Engine still uses live kit in `assets/ui/`.

## Shirt + scale snap (`norm/`)

**Camera is south-east** (side/¾ facing right) — south was a front view, which made late tiny and early-down into a stretch.

Address is a new state off takeaway (`38cac8c4`) so the head matches. Planted on **128×192**, feet y=178, cap-to-feet 90px (`normalize_frames.py`).

Gate: `char_states_norm_strip_x2.png`

Mid SE had two clubs (backswing shaft through the cap + one in the hands). Extra shaft erased; original at `swing_mid/rotations/south-east_twoclub.png`.

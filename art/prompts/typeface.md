# UI Typeface — Pixel Operator

**Status**: Live  
**Depends on**: `art/STYLE.md` (**Pixel Kit Golf**)

## Live face

| | |
|--|--|
| Font | **Pixel Operator** (Jayvee Enaguas / HarvettFox96) |
| License | **CC0 1.0** — `assets/fonts/CC0-PixelOperator.txt` |
| File | `assets/fonts/PixelOperator.ttf` |
| Wired | `assets/ui/game_theme.tres`, `UiScale.FONT` |

Why: clear `0–9` at HUD sizes (yards, scores, tempo ratios). Pixelify Sans soft-merged **5/S**.  
Scale: denser face → `UiScale` **40 / 48 / 56** (was 32 / 40 / 48) + matching scene overrides.

## History

- PixelLab `create_font` samples rejected — empty digit glyphs.
- Free candidates gated in `art/generated/wave_C/fonts/` (`gate_candidates.py`).
- Pixel Operator won over Public Pixel (chunkier but wider) and VT323 (terminal).

## Optional later

- **Pixel Operator Mono** for aligned meter columns  
- **Press Start 2P** for title wordmark only  
- Pixelify kept under `assets/fonts/` as archive, not wired  

## Related

- Start screen kit redo — `art/prompts/title_screen.md`

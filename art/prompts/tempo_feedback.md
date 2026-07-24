# Prompt Skill: Tempo Feedback (Meter + Pure FX)

**Status**: Active  
**Depends on**: art/STYLE.md (**Crunchy Pixel**)  
**Purpose**: Meter chrome and pure-strike juice that match the tempo pad landmark family.

Any agent generating these assets must follow both this file and art/STYLE.md.

---

## 1. Context

Live feedback for the full-swing ratio strip and earned pure-contact reward.

Elements:
- Meter track / band background
- Meter needle marker
- Single pure-strike burst (keep minimal — one frame is enough)

---

## 2. Technical Constraints

- Style: Strictly follow art/STYLE.md
- View: Flat UI overlay
- Resolution: 64×64 markers; meter track may be 128×32 (tileable horizontally)
- Palette: Core palette only; pure FX may use sand light + light accent as spark
- Transparency: Required
- Naming:
  - `ui_tempo_meter_track.png`
  - `ui_tempo_meter_needle.png`
  - `fx_pure_burst.png`

---

## 3. Generation Guidance

### Meter track
- Dark green-gray trough with subtle border; room for a green “good” band drawn in code.

### Needle
- Small high-contrast pill or diamond; readable at ~20px on-screen.

### Pure burst
- Sharp 4–8 point spark, not a soft glow blob. Pixel-friendly.

---

## 4. Master Prompt Addition

Append to STYLE.md master template:

UI overlay tempo feedback, crunchy true pixel, hard silhouette, transparent, [specific element], tempo pad family

---

## 5. Output Expectations

- Generate individually → `art/generated/` → cleaned → `assets/ui/` (FX → `assets/ball/` for `fx_pure_burst.png` replacing / pairing with perfect glow)
- Do not resurrect unused legacy `power_meter.png` / `swing_bar.png` / `swing_marker.png` names.

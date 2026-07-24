# Prompt Skill: Tempo Pad (Full Swing)

**Status**: Active  
**Depends on**: art/STYLE.md (**Crunchy Pixel**)  
**Purpose**: Generate all visual elements for the full-swing tempo pad — the core skill surface of the game.

Any agent generating tempo pad art must follow both this file and art/STYLE.md.

---

## 1. Context

The tempo pad is the primary interaction surface for the full swing.  
It must clearly communicate the 3:1 tempo motion through visual landmarks.

Required landmarks (in order of the swing):
- START – address / beginning of takeaway
- TOP – top of the backswing
- THROUGH – impact zone
- FOLLOW – finish / follow-through

Additional elements:
- Pull lane (the path the finger/thumb follows)
- Idle coach / takeaway cue (visual that teaches the motion before the player touches)
- Optional: subtle address ball frame or position indicator

These are UI overlay elements, not top-down terrain tiles.

---

## 2. Technical Constraints

- Style: Strictly follow art/STYLE.md (Crunchy Pixel — visible pixels, hard outlines, dither OK)

- View: Flat UI / overlay (not perspective, not top-down course view)
- Resolution: Prefer 64×64 or 128×128 for individual landmarks. Larger combined pad elements up to 256×256 if needed.
- Palette: Stick to the core palette in STYLE.md. Very limited accent colors only if necessary for hierarchy.
- Edges: Crisp pixels. High readability at small mobile sizes.
- Transparency: Use transparent backgrounds.
- Naming convention:  
  ui_tempo_landmark_start.png  
  ui_tempo_landmark_top.png  
  ui_tempo_landmark_through.png  
  ui_tempo_landmark_follow.png  
  ui_tempo_lane.png  
  ui_tempo_coach_idle.png  

---

## 3. Generation Guidance

### Landmarks
- Each landmark should be distinct and readable at a glance.
- They should feel like part of the same visual family.
- Avoid text labels inside the art if possible (text can be handled in code). Use shape and color language instead.
- TOP should feel like the highest / turning point.
- THROUGH should feel like the moment of contact / power.

### Pull Lane
- Clear directional path.
- Should guide the eye from START → TOP → THROUGH → FOLLOW.
- Keep it simple so it doesn’t compete with the landmarks.

### Idle Coach / Takeaway Cue
- A subtle visual that suggests the beginning of the motion.
- Should feel helpful, not noisy.
- Can be a simplified golfer silhouette, arrow language, or abstract motion cue — as long as it stays on-style.

---

## 4. Master Prompt Addition

When generating any tempo pad asset, start from the STYLE.md master template and append:

UI overlay tempo swing pad, crunchy true pixel, visible pixels, hard outline, dithered fill OK, transparent background, [specific element], tempo landmark family

---

## 5. Output Expectations

- Generate individual elements first (landmarks, lane, coach).
- Do not generate a single giant combined pad unless specifically requested.
- After generation, assets go to art/generated/ for review, then cleaned versions move to assets/ui/.
- Putt uses a sibling cool-palette set — see `art/prompts/putt_pad.md`.

---

**Priority order for generation:**
1. The four landmarks (START, TOP, THROUGH, FOLLOW) — done
2. Pull lane (`ui_tempo_lane.png`) — vertical track strip, 64×128, fairway greens, transparent outside lane
3. Idle coach / takeaway cue (`ui_tempo_coach_idle.png`) — 64×64 abstract down-chevron / motion cue toward TOP

### Pull lane detail
- Soft vertical capsule or parallel rails; must stretch cleanly when drawn between START and TOP.
- Do not bake landmark icons into the lane texture.

### Coach detail
- One clear “pull down / takeaway” cue; coach stays abstract (golfer is separate overlay frames — `art/prompts/golfer.md`).
- Must not compete with START landmark at address.

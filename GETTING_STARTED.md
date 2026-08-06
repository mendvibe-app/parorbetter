# Getting started — Par or Better

Use this when cloning or resuming on a **new machine**. Goal: open the game, run contract checks, and continue where the last session left off.

**Repo:** `https://github.com/mendvibe-app/parorbetter.git`  
**Engine:** Godot **4.7.x** (see `project.godot` → `config/features`)  
**Language:** GDScript only (no C#)

---

## 1. Prerequisites

| Tool | Why | Notes |
|------|-----|--------|
| **Git** | Clone / push | Any recent Git |
| **Godot 4.7.x** | Run & edit | [godotengine.org](https://godotengine.org/) — match **4.7**, not 4.3/4.4. Mobile feature tag is fine (2D). |
| **Python 3.10+** | Contract checks (`scripts/**/*_check.py`) | stdlib only for checks; `Pillow` used by a few image checks (`pip install pillow` if those fail) |
| **Code agent (optional)** | Grok Build / Cursor | Project instructions: `AGENTS.md`, `.cursor/rules/ponytail.mdc` |

### Optional (only if you need them)

| Tool | Why |
|------|-----|
| **uv** + **godot-ai** | MCP bridge to a live Godot editor (`uvx … godot-ai attach`, ports 8000 / 9500). Plugin lives in `addons/godot_ai`. |
| **PixelLab** account / MCP | Art pipeline (`art/STYLE.md`, `art/prompts/kit.md`) — not required to play or ship gameplay. |
| **Android SDK / export templates** | Device builds only. Local APKs go under `builds/` (gitignored). |

---

## 2. Clone and open

```bash
git clone https://github.com/mendvibe-app/parorbetter.git
cd parorbetter
git checkout main
git pull
```

1. Open **Godot 4.7** → **Import** → select this folder’s `project.godot`.
2. Let the editor import assets (first open builds `.godot/` — gitignored).
3. Press **F5** (main scene: `scenes/main.tscn`).

If scripts fail to parse (e.g. new `class_name` not in cache): **Project → Reload Current Project**, or fully quit and reopen.

---

## 3. Verify the tree

### Contract checks (required “tests”)

There is no GDScript CI. Gameplay invariants live in Python parsers next to the code:

**Windows (PowerShell):**

```powershell
Get-ChildItem -Recurse scripts -Filter *_check.py | ForEach-Object {
  Write-Host $_.FullName
  python $_.FullName
  if ($LASTEXITCODE -ne 0) { throw "fail: $($_.Name)" }
}
```

**Unix:**

```bash
for f in scripts/*/*_check.py; do python3 "$f" || exit 1; done
```

### Headless Godot (optional, if `godot` is on PATH)

```bash
godot --path . --headless --import
godot --path . --headless --quit-after 120
```

Both should exit 0 when clean.

---

## 4. Play / debug loop

| Mode | How |
|------|-----|
| Full run | Start screen → Survival or 18-hole |
| Isolated shots | Start → **Practice Range** |
| Putting only | Practice green (if exposed on start) / land on green in range |
| Debug | **F1** — metrics, force perfect/mishit, hole jump, sliders |

**Shot loop:** Club (★ → Confirm) → Aim (drag / Confirm Aim / Space) → Tempo pad (backswing then through the ball) → dismiss result.

**Controls reminder:** see `README.md`. Deeper constants and folder map: `AGENTS.md`.

---

## 5. Agent / MCP setup (optional)

### Project rules for AI

- `AGENTS.md` — game map, constants, shot loop, autoloads  
- `.cursor/rules/ponytail.mdc` — shortest correct diff  
- Art: `art/STYLE.md` (**Pixel Kit Golf**)

### Godot AI MCP (editor bridge)

1. Plugin already under `addons/godot_ai` (committed). Enable in **Project → Project Settings → Plugins** if needed.
2. User-level Grok MCP config (not in repo), roughly:

   ```toml
   [mcp_servers."godot-ai"]
   # uvx … godot-ai attach  (ports 8000 / 9500)
   ```

3. **Open this project in the Godot editor** with the plugin enabled before relying on MCP tools.

**Never** clone a second `godot-ai` tree into the project. Duplicate `class_name Mcp*` scripts corrupt Godot’s global class cache. If that happens: delete the extra tree, **fully quit** the editor, reopen.

### PixelLab MCP

Only for generating kit art. Finals land in `assets/` after a wave gate; raw under `art/generated/`.

---

## 6. What not to commit

Already ignored or should stay local:

| Path | Reason |
|------|--------|
| `.godot/` | Editor import cache |
| `builds/`, `android/build/` | Heavy export output |
| `_tmp_*`, `*.b64`, `_green_dbg/` | Scratch / debug dumps |
| `debug/*.png` | Playtest screenshots (optional local only) |

`*.gd.uid` **are** committed (Godot 4.4+).

---

## 7. Resume context (session handoff)

Recent work landed around:

- **Tempo / direction** — swipe → path/shape; pad-right → draw (see `plans/epic-shot-direction-rework.md` if present)
- **Wind HUD + course pin** — shared cloth paint (`WindFlag.paint_flag`), mockup `plans/wind_direction_speed.png`, epic `plans/wind-flag-direction-strength-epic.md`
- **Hazards** — trees clear bunkers; sand lie uses paint alpha
- **Putt cup** — `CUP_CAPTURE_MAX_SPEED` lip-out (no hot teleport makes)
- **Haptics**, Cape/Leven water, scorecard, Godot AI addon

**Plans:** `plans/`  
**Philosophy:** ponytail — shortest correct diff + one `*_check.py` for non-trivial logic.

When starting a new AI session on the other machine: open this repo, point the agent at `AGENTS.md` + `GETTING_STARTED.md`, `git pull`, run contract checks, then continue.

---

## 8. Quick checklist (other house)

- [ ] Git clone / pull `main`
- [ ] Godot **4.7.x** installed and project imported
- [ ] `python` runs; contract checks all green
- [ ] F5 plays; Practice Range + one full hole
- [ ] (Optional) Godot AI plugin + MCP if using editor tools
- [ ] (Optional) PixelLab only if doing art

That’s enough to pick up without rediscovering tooling.

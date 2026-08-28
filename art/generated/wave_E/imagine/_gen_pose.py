"""One-off Imagine edit via xAI API. Reads XAI_API_KEY from env. No secrets in this file."""
from __future__ import annotations

import argparse
import base64
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
LOCK = HERE / "lock"
OUT = HERE / "pass3"

POSES = {
    "mid": {
        "refs": ["lock_takeaway.png", "lock_top.png"],
        "prompt": (
            "IMAGE_0 is takeaway (club still low, down-left). "
            "IMAGE_1 is top (club already up by the head). "
            "Copy identity only from those refs: olive cap, bald tan head, two black square eyes, "
            "cream polo with dark dots, dark pants, black shoes, ONE driver, hard 1px outline, "
            "chunky pixel art, facing right, same scale and foot plant.\n"
            "Generate ONLY mid-backswing: halfway BETWEEN takeaway and top. "
            "Hands at chest, not at the cap. Shaft about 45 degrees up-left. "
            "Club head well below the cap. Not takeaway (club not near the ground). "
            "Not top (club not behind or above the head). "
            "Transparent PNG, no black fill, no checker, no golf ball, no hair, no second club."
        ),
    },
    "mid_from_takeaway": {
        "refs": ["lock_takeaway.png"],
        "prompt": (
            "Keep this EXACT golfer: same olive cap, bald tan head, square eyes, "
            "cream dotted polo, dark pants, black shoes, ONE driver, same body scale, facing right. "
            "Do not redraw a new person.\n"
            "ONLY change the pose: raise the club from takeaway to mid-backswing. "
            "Hands move to chest height. Shaft about 45 degrees up-left. "
            "Club head stays well BELOW the cap — not up by the head, not still near the ground. "
            "Feet stay planted. One club only. Transparent PNG, no black or white fill, no ball."
        ),
    },
    "mid_horizontal": {
        "refs": ["lock_takeaway.png"],
        "prompt": (
            "Keep this EXACT golfer: olive cap, bald tan head, two black square eyes, "
            "cream dotted polo, dark pants, black shoes, ONE driver, facing right, same scale.\n"
            "Change ONLY the pose to halfway back: club SHAFT PARALLEL TO THE GROUND, "
            "pointing LEFT, horizontal like a table. Hands at the BELT / hip, not at the head. "
            "Club head at about hip height, well below the cap. "
            "NOT a high finish. NOT address. NOT club up by the ear. "
            "If the club is near the cap you failed. "
            "One club. Transparent PNG, no fill, no ball."
        ),
    },
    "early_down": {
        "refs": ["lock_top.png"],
        "prompt": (
            "Keep this EXACT golfer: olive cap, bald tan head, square eyes, cream dotted polo, "
            "dark pants, ONE driver, facing right.\n"
            "Change ONLY the pose to EARLY DOWNSWING: the club has started coming DOWN from the top. "
            "Club is in FRONT of the torso, shaft 45 degrees pointing DOWN-RIGHT toward the ground. "
            "Club head at KNEE height on the RIGHT side of the body (target side). "
            "Hands at the navel. "
            "NOT address: club is NOT on the ground. "
            "NOT top: club is NOT up by the head or behind him on the left. "
            "If the club is on the ground or up by the cap you failed. "
            "One club. Transparent PNG, no fill, no ball."
        ),
    },
    "impact": {
        "refs": ["lock_address.png"],
        "prompt": (
            "Keep this EXACT golfer: olive cap, bald tan head, square eyes, cream dotted polo, "
            "dark pants, ONE driver, facing right.\n"
            "Change ONLY the pose to IMPACT: striking the ball (NO ball in the image). "
            "Club head at GROUND height on the RIGHT, shaft steep, almost vertical. "
            "Arms extended through the shot, hips slightly open toward the right. "
            "NOT a horizontal sweep. NOT club pointing left. NOT club up by the head. "
            "If the shaft is parallel to the ground you failed. "
            "One club. Transparent PNG, no fill, no ball."
        ),
    },
    "impact_ground": {
        "refs": ["lock_address.png"],
        "prompt": (
            "Keep this EXACT golfer from the reference. Olive cap, bald tan head, square eyes, "
            "cream dotted polo, dark pants, facing right.\n"
            "Pose: IMPACT. Exactly ONE driver. The club head must be ATTACHED to the end of the shaft. "
            "Club head TOUCHING THE GROUND on the RIGHT side of his feet. "
            "Hunched like address, but arms straighter, as if he just hit. "
            "Do NOT draw a second club head. Do NOT draw a floating head. Do NOT draw a cane. "
            "No golf ball. Transparent PNG, no fill."
        ),
    },
    "follow_wrap": {
        "refs": ["lock_top.png"],
        "prompt": (
            "Keep this EXACT golfer: olive cap, bald tan head, square eyes, cream dotted polo, "
            "dark pants, ONE driver, facing right.\n"
            "Change ONLY the pose to FOLLOW-THROUGH AFTER the hit. "
            "Club wrapped over the LEFT shoulder, behind the head, shaft pointing left-up. "
            "Chest more open toward the camera. Weight on the FRONT (right) foot, back heel up. "
            "This is AFTER impact, not the top of the backswing. "
            "One club. Transparent PNG, no fill, no ball."
        ),
    },
    "late_from_top": {
        "refs": ["lock_top.png"],
        "prompt": (
            "Keep this EXACT golfer and camera: 3/4 view facing RIGHT, we see the LEFT shoulder and the side of the face. "
            "Right-handed. Do NOT turn his chest toward the camera. Do NOT make him left-handed. "
            "Do NOT square him up front-on.\n"
            "ONLY change the club a little: this is LATE backswing, just before the top. "
            "Shaft more upright than a high-left 10 o'clock, about 70-80 degrees, club head still to the LEFT of the cap, "
            "not fully behind the head yet. Same pixel kit style, grid shaft, one club, no ball."
        ),
    },
    "late_from_mid": {
        "refs": ["lock_mid.png"],
        "prompt": (
            "Keep this EXACT golfer and camera: profile/3/4 facing RIGHT, right-handed. "
            "Do NOT turn his chest toward the camera. Do NOT switch him to left-handed.\n"
            "ONLY raise the club from horizontal to LATE backswing: shaft about 70 degrees up-left, "
            "hands at chest/shoulder, club head still well below sitting on the cap. "
            "Keep the checker/grid shaft. One club. No ball."
        ),
    },
    "kit_restyle_mid": {
        "refs": ["lock_address.png", "lock_mid.png"],
        "prompt": (
            "IMAGE_0 is the STYLE lock. IMAGE_1 is the POSE to keep. "
            "Redraw IMAGE_1's golfer in the EXACT pixel rendering of IMAGE_0: "
            "chunky square pixels, hard 1px outline, cream polo with dark square dots, "
            "olive cap, bald tan head, two square eyes, driver shaft is a CHECKER/GRID of dark pixels "
            "not a smooth stick. Do not smooth. Do not anti-alias.\n"
            "KEEP IMAGE_1's pose: shaft PARALLEL TO THE GROUND pointing LEFT, hands at the belt. "
            "Do NOT copy IMAGE_0's address pose. If the club is on the ground you failed. "
            "One attached club head. No ball."
        ),
    },
    "early_down_left": {
        "refs": ["lock_top.png"],
        "prompt": (
            "Keep this EXACT golfer and camera: 3/4 facing RIGHT, left shoulder visible, right-handed. "
            "Do NOT turn his chest toward the camera.\n"
            "ONLY change the pose to EARLY DOWNSWING: the club has started coming DOWN from the top "
            "but is STILL ON THE LEFT side of the body. "
            "Shaft about 45 degrees, pointing DOWN-LEFT. Club head at about shoulder height, left of the cap. "
            "NOT at the ball. NOT on the right side of the body. NOT still at the top (club not behind the head). "
            "If the club is on the right or near the ground you failed. "
            "Same pixel kit, grid shaft, one club, no ball."
        ),
    },
    "chest_late": {
        "refs": ["lock_mid.png"],
        "prompt": (
            "Keep this EXACT body: we see the FRONT of the cream polo and the FACE in profile looking RIGHT. "
            "Chest toward the camera. Do NOT show his back. Do NOT bring the left shoulder toward the camera. "
            "Do NOT rotate the torso. Feet stay put. Right-handed.\n"
            "ONLY the arms and club move: raise the club from horizontal to about 60 degrees up-left. "
            "Hands at chest. Club still on the LEFT. One club, grid shaft, no ball."
        ),
    },
    "chest_top": {
        "refs": ["lock_mid.png"],
        "prompt": (
            "Keep this EXACT body: FRONT of the cream polo visible, FACE in profile looking RIGHT. "
            "Chest toward the camera. Do NOT show his back. Do NOT turn him. Do NOT left-shoulder-to-camera. "
            "Feet stay put. Right-handed.\n"
            "ONLY the arms and club move: this is the TOP of the backswing. Club high on the LEFT, "
            "shaft steep, club head up near cap height but still LEFT of the head. "
            "Torso must still match the reference. One club, no ball."
        ),
    },
    "chest_early_down": {
        "refs": ["lock_mid.png"],
        "prompt": (
            "Keep this EXACT body: FRONT of the polo, FACE in profile looking RIGHT. Chest toward camera. "
            "Do NOT show his back. Do NOT turn him.\n"
            "ONLY the arms and club move: early downswing, club coming DOWN on the LEFT, "
            "shaft about 30-45 degrees down from the top but still pointing left. "
            "Club still on the LEFT, not at the ball, not on the right. One club, no ball."
        ),
    },
    "chest_follow": {
        "refs": ["lock_address.png"],
        "prompt": (
            "Keep this EXACT body: FRONT of the polo, FACE in profile looking RIGHT. Chest toward camera. "
            "Do NOT show his back. Do NOT turn him around.\n"
            "This is FOLLOW-THROUGH AFTER the hit. Club is on the RIGHT side, high, shaft pointing up-right. "
            "Weight on the front foot. Club must NOT be on the left. "
            "If the club is on the left you failed. One club, no ball."
        ),
    },
    "chest_impact": {
        "refs": ["lock_address.png"],
        "prompt": (
            "Keep this EXACT body: FRONT of the polo, FACE in profile looking RIGHT. Hunched. "
            "Do NOT show his back. Do NOT walk. Do NOT turn him.\n"
            "This is IMPACT, striking the ball (NO ball). Club head TOUCHING THE GROUND on the RIGHT. "
            "Arms straighter than address, as if he just hit. Exactly ONE club head ATTACHED to the shaft. "
            "Not a horizontal sweep at the hip. Not a second floating head. One club."
        ),
    },
    "chest_early_from_top": {
        "refs": ["lock_top.png"],
        "prompt": (
            "Keep this EXACT body: FRONT of the polo, FACE in profile looking RIGHT. Chest toward camera. "
            "Do NOT stand him up. Do NOT show his back. Do NOT put the club on the right.\n"
            "ONLY lower the club from the top: early downswing, shaft about 45 degrees, still pointing LEFT. "
            "Club head still on the LEFT, around shoulder height. Hands still together. One club, no ball."
        ),
    },
    "chest_impact_through": {
        "refs": ["lock_mid.png"],
        "prompt": (
            "Keep this EXACT body: FRONT of the polo, FACE in profile looking RIGHT. Chest toward camera. "
            "Do NOT show his back. Do NOT stand him up. Do NOT walk.\n"
            "This is IMPACT through the ball (NO ball). The club has swung to the RIGHT. "
            "Shaft about 45 degrees pointing DOWN-RIGHT. Club head at SHIN/KNEE height on the RIGHT, "
            "NOT resting on the ground like address. Arms reaching toward the target on the right. "
            "If the club is on the left or sitting on the ground you failed. One club, no ball."
        ),
    },
    "chest_impact_from_addr": {
        "refs": ["lock_address.png"],
        "prompt": (
            "Keep this EXACT person and camera. Do NOT copy the address pose.\n"
            "This is IMPACT: club has just HIT and is moving through to the RIGHT. "
            "Shaft flatter than address, about 40 degrees down-right. Club head at KNEE height, "
            "not touching the ground. Arms more extended toward the right. Still hunched, still facing right. "
            "If this looks like address (club on the ground) you failed. One club, no ball."
        ),
    },
    "impact_at_ball": {
        "refs": ["lock_impact.png"],
        "prompt": (
            "Keep this EXACT golfer: chest toward camera, face in profile looking RIGHT, arms reaching right. "
            "Do NOT show his back. Do NOT walk further. Do NOT raise the club.\n"
            "ONLY change the club: this is IMPACT AT THE BALL, not follow-through. "
            "Drop the club head to the GROUND on the RIGHT, at FOOT level, as if striking a ball (NO ball). "
            "Shaft steeper, pointing down-right. Hands still together, a bit lower. "
            "If the club head is at knee or hip height you failed — that is already through. "
            "One club, one attached head, no ball."
        ),
    },
    "impact_at_ball_addr": {
        "refs": ["lock_address.png"],
        "prompt": (
            "Keep this EXACT person: chest toward camera, face profile looking RIGHT, hunched. "
            "Do NOT show his back. Do NOT stand him up. Do NOT walk.\n"
            "This is IMPACT, the club striking the ball (NO ball). "
            "Club head ON THE GROUND on the RIGHT, same place as a tee shot. "
            "Arms MORE EXTENDED than a setup, hands lower, committed hit — not a practice address. "
            "Do NOT sweep the club up to knee height (that is follow-through). "
            "Do NOT leave the arms as bent as address. One club, no ball."
        ),
    },
    "kit_restyle_early": {
        "refs": ["lock_address.png", "lock_early_down.png"],
        "prompt": (
            "IMAGE_0 is the STYLE lock. IMAGE_1 is the POSE to keep. "
            "Redraw IMAGE_1's golfer in the EXACT pixel rendering of IMAGE_0: "
            "chunky square pixels, hard 1px outline, cream polo with dark square dots, "
            "olive cap, bald tan head, two square eyes, CHECKER/GRID shaft not a smooth stick.\n"
            "KEEP IMAGE_1's pose: club at KNEE height on the RIGHT, shaft 45 degrees down-right. "
            "Do NOT copy IMAGE_0's address pose. Club must NOT touch the ground. "
            "One attached club head. No ball."
        ),
    },
    "kit_restyle_follow": {
        "refs": ["lock_top.png", "lock_follow.png"],
        "prompt": (
            "IMAGE_0 is the STYLE lock. IMAGE_1 is the POSE to keep. "
            "Redraw IMAGE_1's golfer in the EXACT pixel rendering of IMAGE_0: "
            "chunky square pixels, hard 1px outline, cream polo with dark square dots, "
            "olive cap, bald tan head, two square eyes, CHECKER/GRID shaft not a smooth stick.\n"
            "KEEP IMAGE_1's pose: follow-through, weight on the FRONT (right) foot, back foot trailing, "
            "club high-left AFTER the hit. Do NOT freeze at the top of the backswing. "
            "One attached club head. No ball."
        ),
    },
    "putt_address": {
        "refs": ["lock_address.png"],
        "prompt": (
            "Keep this EXACT person: olive cap, bald tan head, two square eyes, cream dotted polo, "
            "dark pants, chest toward camera, FACE in profile looking RIGHT. Do NOT show his back.\n"
            "Change ONLY the setup to PUTTING: crouch lower, narrower stance, hands much lower. "
            "Replace the driver with a SHORT PUTTER — thin shaft, small blade head, shaft about "
            "half as long as a driver. Putter head ON THE GROUND on the RIGHT, as if at a golf ball "
            "(NO ball). Do NOT keep the big driver head. Do NOT stand him up. One club."
        ),
    },
    "putt_takeaway": {
        "refs": ["lock_putt_address.png"],
        "prompt": (
            "Keep this EXACT crouched putter: chest toward camera, face profile RIGHT, short putter. "
            "Do NOT show his back. Do NOT stand him up. Do NOT give him a driver.\n"
            "ONLY the arms and putter move: TAKEAWAY. Putter goes a little BACK and LEFT, "
            "head still near the ground, just behind his feet on the left. Compact. "
            "If the putter is high or on the right you failed. One short putter, no ball."
        ),
    },
    "putt_mid": {
        "refs": ["lock_putt_takeaway.png"],
        "prompt": (
            "Keep this EXACT golfer and camera: visor pointing RIGHT, face in profile looking RIGHT, "
            "chest toward camera, crouched. Do NOT turn him around. Do NOT point the visor left.\n"
            "ONLY raise the putter a little: MID backswing, head at SHIN height still on the LEFT. "
            "Still a short putter. Compact. One club, no ball."
        ),
    },
    "putt_late": {
        "refs": ["lock_putt_address.png"],
        "prompt": (
            "Keep this EXACT crouched putter: chest toward camera, face profile RIGHT, short putter. "
            "Do NOT show his back. Do NOT stand him up.\n"
            "ONLY the arms and putter move: LATE backswing, just before the top. "
            "Putter head at KNEE height on the LEFT. Still compact. Not a driver top. "
            "One short putter, no ball."
        ),
    },
    "putt_top": {
        "refs": ["lock_putt_address.png"],
        "prompt": (
            "Keep this EXACT crouched putter: chest toward camera, face profile RIGHT, short putter. "
            "Do NOT show his back. Do NOT stand him up. Do NOT raise the putter to the cap.\n"
            "ONLY the arms and putter move: TOP of a putting stroke. Peak is WAIST/THIGH height "
            "on the LEFT, not chest, not head. Compact. If the putter is by the cap you failed. "
            "One short putter, no ball."
        ),
    },
    "putt_early_down": {
        "refs": ["lock_putt_top.png"],
        "prompt": (
            "Keep this EXACT crouched putter: chest toward camera, face profile RIGHT, short putter. "
            "Do NOT show his back. Do NOT stand him up. Do NOT put the putter on the right yet.\n"
            "ONLY lower the putter: EARLY downswing. Head still on the LEFT, now around SHIN height. "
            "Not at the ball yet. Not still at the top. One short putter, no ball."
        ),
    },
    "putt_impact": {
        "refs": ["lock_putt_address.png"],
        "prompt": (
            "Keep this EXACT crouched putter: chest toward camera, face profile RIGHT, short putter. "
            "Do NOT show his back. Do NOT stand him up. Do NOT walk.\n"
            "This is IMPACT, striking the ball (NO ball). Putter head ON THE GROUND on the RIGHT "
            "at the ball. Hands a bit ahead of the head (forward press). "
            "Do NOT sweep the putter up or out to the right at knee height — that is follow. "
            "One short putter."
        ),
    },
    "putt_follow": {
        "refs": ["lock_putt_address.png"],
        "prompt": (
            "Keep this EXACT crouched putter: chest toward camera, face profile RIGHT, short putter. "
            "Do NOT show his back. Do NOT stand him up. Do NOT wrap like a driver finish.\n"
            "This is a SHORT PUTT FOLLOW-THROUGH. Putter has gone PAST the ball to the RIGHT, "
            "head at SHIN height, shaft pointing down-right. Compact, still crouched. "
            "If the putter is on the left or high you failed. One short putter, no ball."
        ),
    },
    "chip_address": {
        "refs": ["lock_address.png"],
        "prompt": (
            "Keep this EXACT person: olive cap, bald tan head, two square eyes, cream dotted polo, "
            "dark pants, chest toward camera, FACE in profile looking RIGHT. Do NOT show his back.\n"
            "Change ONLY the setup to a CHIP: slightly open lean, narrower than a driver stance, "
            "hands a bit ahead. Replace the driver with a WEDGE — lofted iron head, thicker than "
            "a putter, shorter than a driver. Wedge head ON THE GROUND on the RIGHT (NO ball). "
            "Do NOT keep the big driver head. Do NOT crouch as low as a putt. One club."
        ),
    },
    "chip_takeaway": {
        "refs": ["lock_chip_address.png"],
        "prompt": (
            "Keep this EXACT chipping golfer: chest toward camera, face profile RIGHT, wedge. "
            "Do NOT show his back. Do NOT stand him up. Do NOT give him a driver.\n"
            "ONLY the arms and wedge move: TAKEAWAY. Club goes a little BACK and LEFT, "
            "head still low, just behind the feet. Compact chip, not a full swing. One wedge, no ball."
        ),
    },
    "chip_mid": {
        "refs": ["lock_chip_address.png"],
        "prompt": (
            "Keep this EXACT chipping golfer: chest toward camera, face profile RIGHT, wedge. "
            "Do NOT show his back.\n"
            "ONLY the arms and wedge move: MID backswing. Wedge at KNEE height on the LEFT, "
            "shaft pointing down-left. Compact. Not at the ball, not up by the cap. One wedge, no ball."
        ),
    },
    "chip_late": {
        "refs": ["lock_chip_mid.png"],
        "prompt": (
            "Keep this EXACT golfer and camera: visor RIGHT, face profile looking RIGHT, chest toward camera. "
            "Do NOT walk. Do NOT stand him fully up. Do NOT show his back.\n"
            "ONLY raise the wedge a little: LATE chip backswing. Club at THIGH height on the LEFT, "
            "still compact. Not up by the cap. Not a walking finish. One wedge, no ball."
        ),
    },
    "chip_top": {
        "refs": ["lock_chip_address.png"],
        "prompt": (
            "Keep this EXACT chipping golfer: chest toward camera, face profile RIGHT, wedge. "
            "Do NOT show his back. Do NOT raise the club to the cap.\n"
            "ONLY the arms and wedge move: TOP of a chip. Peak is WAIST/HIP height on the LEFT. "
            "If the wedge is by the cap you failed. One wedge, no ball."
        ),
    },
    "chip_early_down": {
        "refs": ["lock_chip_top.png"],
        "prompt": (
            "Keep this EXACT chipping golfer: chest toward camera, face profile RIGHT, wedge. "
            "Do NOT show his back. Do NOT put the club on the right yet.\n"
            "ONLY lower the wedge: EARLY downswing. Head still on the LEFT, around KNEE height. "
            "Not at the ball yet. One wedge, no ball."
        ),
    },
    "chip_impact": {
        "refs": ["lock_chip_address.png"],
        "prompt": (
            "Keep this EXACT chipping golfer: chest toward camera, face profile RIGHT, wedge. "
            "Do NOT show his back. Do NOT walk.\n"
            "This is IMPACT, striking the ball (NO ball). Wedge head ON THE GROUND on the RIGHT "
            "at the ball. Hands ahead of the head. Do NOT sweep the wedge up to knee height. "
            "One wedge."
        ),
    },
    "chip_follow": {
        "refs": ["lock_chip_address.png"],
        "prompt": (
            "Keep this EXACT chipping golfer: chest toward camera, face profile RIGHT, wedge. "
            "Do NOT show his back. Do NOT wrap like a driver finish.\n"
            "This is a SHORT CHIP FOLLOW-THROUGH. Wedge has gone PAST the ball to the RIGHT, "
            "head at KNEE height, shaft pointing up-right a little. Compact. "
            "If the wedge is on the left or up by the cap you failed. One wedge, no ball."
        ),
    },
}


def data_uri(path: Path) -> str:
    return "data:image/png;base64," + base64.b64encode(path.read_bytes()).decode("ascii")


def post(url: str, body: dict, key: str) -> dict:
    raw = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=raw,
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {key}",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=180) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        err = e.read().decode("utf-8", errors="replace")
        raise SystemExit(f"HTTP {e.code} {url}: {err[:2000]}") from e


def fetch_url(url: str, key: str) -> bytes:
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {key}"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def _write_png(dest: Path, data: bytes) -> None:
    from PIL import Image
    import io
    im = Image.open(io.BytesIO(data))
    im.save(dest, "PNG")


def save_images(payload: dict, stem: str, key: str) -> list[Path]:
    OUT.mkdir(parents=True, exist_ok=True)
    saved: list[Path] = []
    data = payload.get("data") or payload.get("images") or []
    if isinstance(payload.get("url"), str) and not data:
        data = [{"url": payload["url"]}]
    if not data and isinstance(payload.get("data"), dict):
        data = [payload["data"]]
    for i, item in enumerate(data):
        url = item.get("url") if isinstance(item, dict) else None
        b64 = (item.get("b64_json") or item.get("base64") or item.get("b64")) if isinstance(item, dict) else None
        dest = OUT / f"{stem}_{i}.png"
        if b64:
            if "," in str(b64):
                b64 = str(b64).split(",", 1)[1]
            raw = base64.b64decode(b64)
        elif url:
            if url.startswith("data:"):
                raw = base64.b64decode(url.split(",", 1)[1])
            else:
                raw = fetch_url(url, key)
        else:
            raise SystemExit(f"No image in item {i}: {json.dumps(item)[:400]}")
        _write_png(dest, raw)
        saved.append(dest)
        print(dest)
    if not saved:
        raise SystemExit("No images in response: " + json.dumps({k: payload[k] for k in payload if k != "data"})[:1500])
    return saved


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("pose", choices=sorted(POSES))
    ap.add_argument("-n", type=int, default=2)
    args = ap.parse_args()
    key = os.environ.get("XAI_API_KEY", "").strip()
    if not key:
        sys.exit("XAI_API_KEY is not set")
    spec = POSES[args.pose]
    refs = [LOCK / name for name in spec["refs"]]
    for p in refs:
        if not p.is_file():
            sys.exit(f"missing ref {p}")
    uris = [data_uri(p) for p in refs]
    prompt = spec["prompt"]
    attempts = [
        (
            "https://api.x.ai/v1/images/edits",
            {
                "model": "grok-imagine-image-2.0",
                "prompt": prompt,
                "n": args.n,
                "aspect_ratio": "1:1",
                "response_format": "b64_json",
                "format": "base64",
                "images": [{"url": u, "type": "image_url"} for u in uris],
            },
        ),
        (
            "https://api.x.ai/v1/images/edits",
            {
                "model": "grok-imagine-image-2.0",
                "prompt": prompt,
                "n": args.n,
                "aspect_ratio": "1:1",
                "image": [{"url": u, "type": "image_url"} for u in uris],
            },
        ),
        (
            "https://api.x.ai/v1/images/generations",
            {
                "model": "grok-imagine-image-2.0",
                "prompt": prompt,
                "n": args.n,
                "aspect_ratio": "1:1",
                "image_urls": uris,
            },
        ),
    ]
    last_err = None
    for url, body in attempts:
        try:
            payload = post(url, body, key)
            print("ok", url)
            save_images(payload, args.pose, key)
            return
        except SystemExit as e:
            last_err = str(e)
            if last_err.startswith("HTTP 4"):
                print("retry after", last_err[:300])
                continue
            raise
    sys.exit(last_err or "all attempts failed")


if __name__ == "__main__":
    main()

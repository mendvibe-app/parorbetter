#!/usr/bin/env python3
"""Assert wired contact/pure WAVs exist and AudioBus preloads them."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SFX = ROOT / "assets" / "sfx"
BUS = (ROOT / "scripts" / "autoload" / "audio_bus.gd").read_text(encoding="utf-8")

WIRED = {
    "contact_perfect.wav": "perfect",
    "contact_good.wav": "good",
    "contact_thin.wav": "thin",
    "contact_fat.wav": "fat",
    "contact_pure.wav": "pure",
    "putt.wav": "putt",
    "putt_drop.wav": "putt_drop",
}
PARKED = [
    "contact_good_alt.wav",
    "contact_short.wav",
    "contact_quick.wav",
    "contact_quick_alt.wav",
    "swing_whoosh.wav",
    "swing_hard.wav",
    "swing_air.wav",
    "shot_whistle.wav",
    "ball_bounce.wav",
]


def _wav_pcm16(path: Path) -> None:
    """Godot rejects WAVE_FORMAT_EXTENSIBLE / 24-bit — require PCM 16-bit."""
    import struct

    raw = path.read_bytes()
    assert raw[0:4] == b"RIFF" and raw[8:12] == b"WAVE", path.name
    i = 12
    while i + 8 <= len(raw):
        cid = raw[i : i + 4]
        size = struct.unpack_from("<I", raw, i + 4)[0]
        if cid == b"fmt ":
            fmt = struct.unpack_from("<H", raw, i + 8)[0]
            bits = struct.unpack_from("<H", raw, i + 8 + 14)[0]
            assert fmt == 1 and bits == 16, f"{path.name} fmt={fmt} bits={bits} (need PCM16)"
            return
        i += 8 + size + (size & 1)
    raise AssertionError(f"no fmt chunk in {path.name}")


def main() -> None:
    assert SFX.is_dir(), f"missing {SFX}"
    for name, key in WIRED.items():
        path = SFX / name
        assert path.is_file() and path.stat().st_size > 1000, f"missing/empty {name}"
        _wav_pcm16(path)
        assert f"res://assets/sfx/{name}" in BUS, f"AudioBus missing preload for {name}"
        if key not in ("pure", "putt", "putt_drop"):
            assert f'"{key}"' in BUS, f"AudioBus missing contact key {key}"
    assert "miss" in BUS and "contact_fat.wav" in BUS
    assert "func play_putt(" in BUS and "func play_putt_drop(" in BUS
    assert 'load("res://assets/sfx/putt.wav")' in BUS
    assert 'load("res://assets/sfx/putt_drop.wav")' in BUS
    for name in PARKED:
        path = SFX / name
        assert path.is_file() and path.stat().st_size > 1000, f"parked missing {name}"
        _wav_pcm16(path)
    # procedural hooks still present
    for fn in ("play_splash", "play_birdie", "play_ui", "play_tick"):
        assert f"func {fn}" in BUS, f"missing procedural {fn}"
    print("audio_bus_check: ok")


if __name__ == "__main__":
    main()

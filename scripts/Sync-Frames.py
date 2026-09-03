"""Losslessly copy the nine animation rows from the approved v2 atlas.

Optional maintainer tool; requires Pillow. Does not generate or retouch artwork.
Run only in the complete source repository, not a standalone Windows release.
"""

from pathlib import Path

from PIL import Image


ROWS = (
    ("idle", 6),
    ("running-right", 8),
    ("running-left", 8),
    ("waving", 4),
    ("jumping", 5),
    ("failed", 8),
    ("waiting", 6),
    ("running", 6),
    ("review", 6),
)


def main() -> None:
    repo = Path(__file__).resolve().parent.parent
    source = repo / "codex-native" / "bjut-yanxiaobei" / "spritesheet.webp"
    output = repo / "windows-companion" / "frames"
    with Image.open(source) as atlas:
        if atlas.size != (1536, 2288) or atlas.mode != "RGBA":
            raise ValueError("Expected an RGBA v2 atlas: 1536 x 2288")
        count = 0
        for row_index, (state, frame_count) in enumerate(ROWS):
            folder = output / state
            folder.mkdir(parents=True, exist_ok=True)
            for column in range(frame_count):
                left, top = column * 192, row_index * 208
                frame = atlas.crop((left, top, left + 192, top + 208))
                if frame.getchannel("A").getbbox() is None:
                    raise ValueError(f"Empty frame: {state}/{column:02}.png")
                frame.save(folder / f"{column:02}.png")
                count += 1
    print(f"Copied {count} frames from the approved atlas; source unchanged.")


if __name__ == "__main__":
    main()

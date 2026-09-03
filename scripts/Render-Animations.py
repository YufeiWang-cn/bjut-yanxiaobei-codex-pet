"""Render native and companion GIFs from the same frames and timing profile.

Optional maintainer tool. Requires Pillow; never connects to an account.
"""
import json
from pathlib import Path

from PIL import Image


def main() -> None:
    repo = Path(__file__).resolve().parent.parent
    app = repo / "windows-companion"
    timing = json.loads((app / "animation-timing.json").read_text(encoding="utf-8-sig"))
    if timing["schemaVersion"] != 1:
        raise ValueError("Unsupported animation timing schema")
    for profile in ("companion", "native"):
        output = repo / "docs" / "animations"
        if profile == "native":
            output /= "native"
        output.mkdir(parents=True, exist_ok=True)
        for state, durations in timing[profile].items():
            files = sorted((app / "frames" / state).glob("*.png"))
            if len(files) != len(durations) or any(not isinstance(ms, int) or ms < 40 for ms in durations):
                raise ValueError(f"Frame/timing mismatch: {profile}/{state}")
            frames = []
            for file in files:
                with Image.open(file) as frame:
                    frames.append(frame.convert("RGBA"))
            frames[0].save(output / f"{state}.gif", save_all=True,
                           append_images=frames[1:], duration=durations,
                           loop=0, disposal=2, optimize=False)
    print("Rendered 9 companion and 9 native GIFs from animation-timing.json")


if __name__ == "__main__":
    main()

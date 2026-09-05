"""Make near-black matte corners (and hairline strokes) transparent on brand PNGs."""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1] / "assets" / "images"
FILES = [
    ROOT / "app_icon_wa_cartoon.png",
    ROOT / "splash_wa_plate.png",
    ROOT / "app_icon_wa.png",
    ROOT / "brand_icons" / "wa_icon_100.png",
    ROOT / "brand_icons" / "wa_icon_100_transparent.png",
]


def fix(path: Path, thr: int = 28) -> None:
    im = Image.open(path).convert("RGBA")
    px = im.load()
    w, h = im.size
    changed = 0
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            if r <= thr and g <= thr and b <= thr:
                px[x, y] = (0, 0, 0, 0)
                changed += 1
    im.save(path)
    print(f"{path.name}: cleared {changed} px ({w}x{h})")


def main() -> None:
    for f in FILES:
        if f.exists():
            fix(f)
        else:
            print(f"missing: {f}")


if __name__ == "__main__":
    main()

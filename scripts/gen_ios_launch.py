from PIL import Image
from pathlib import Path

master = Image.open(r"d:\sudoproject\huihuo\assets\images\app_icon_master.png").convert("RGB")
launch = Path(r"d:\sudoproject\huihuo\ios\Runner\Assets.xcassets\LaunchImage.imageset")
for name, size in [
    ("LaunchImage.png", 168),
    ("beth.t@example.com", 336),
    ("rachel.c@example.org", 504),
]:
    master.resize((size, size), Image.Resampling.LANCZOS).save(launch / name, quality=92)
    print("wrote", name)

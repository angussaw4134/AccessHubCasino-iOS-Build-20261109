"""Copy project artwork into the native asset catalog; no third party dependencies."""
from pathlib import Path
import json
import shutil

root = Path(__file__).resolve().parents[1]
art = root.parent / "artwork"
catalog = root / "AccessHubCasino/Assets.xcassets"
catalog.mkdir(parents=True, exist_ok=True)
(catalog / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2))
names = ["CrashArt", "BlackjackArt", "MinesArt", "SlotsArt", "AHMonogram", "AHWordmark", "SymbolGem", "SymbolCrown", "SymbolSeven", "SymbolBell", "SymbolCherry", "Gem", "Mine", "CardBack", "TableTexture"]
missing = []
for name in names:
    source = art / f"{name}.png"
    if not source.exists():
        missing.append(str(source)); continue
    destination = catalog / f"{name}.imageset"
    destination.mkdir(exist_ok=True)
    shutil.copy2(source, destination / source.name)
    (destination / "Contents.json").write_text(json.dumps({"images": [{"filename": source.name, "idiom": "universal"}], "info": {"author": "xcode", "version": 1}}, indent=2))
source = art / "AppIcon1024.png"
if source.exists():
    destination = catalog / "AppIcon.appiconset"
    destination.mkdir(exist_ok=True)
    shutil.copy2(source, destination / "AppIcon.png")
    (destination / "Contents.json").write_text(json.dumps({"images": [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}], "info": {"author": "xcode", "version": 1}}, indent=2))
else:
    missing.append(str(source))
if missing:
    raise SystemExit("Missing artwork:\n" + "\n".join(missing))
print(f"Imported {len(names)} images and the iOS app icon.")

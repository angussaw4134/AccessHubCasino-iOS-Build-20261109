"""Read `xcrun simctl list devices available -j` and select two iPhone sizes.

Prefers an SE/mini for the small device and a Pro Max/Plus for the large one.
Uses the newest installed iOS runtime containing both classes. This selects
existing simulators; it does not download runtimes or create/delete devices.
"""
import json
import re
import sys

inventory = json.load(sys.stdin)["devices"]
runtimes = sorted((key for key in inventory if "iOS" in key), key=lambda key:tuple(map(int,re.findall(r"\d+",key))), reverse=True)
phones = []
for runtime in runtimes:
    candidates = [item for item in inventory[runtime] if item.get("isAvailable",True) and item["name"].startswith("iPhone")]
    if len(candidates) >= 2:
        phones = candidates
        break
if len(phones) < 2:
    raise SystemExit("Two available iPhone simulators are required. Install an iOS runtime in Xcode Settings > Platforms.")

def small_score(device):
    name=device["name"]
    return (0 if "SE" in name else 1 if "mini" in name else 2 if "16e" in name else 4 if "Pro Max" in name or "Plus" in name else 3, name)
def large_score(device):
    name=device["name"]
    return (0 if "Pro Max" in name else 1 if "Plus" in name else 2 if "Pro" in name else 3, name)
small=sorted(phones,key=small_score)[0]
large=sorted((phone for phone in phones if phone["udid"] != small["udid"]),key=large_score)[0]
for prefix,device in [("SMALL",small),("LARGE",large)]:
    print(f"{prefix}_ID={device['udid']}")
    print(f"{prefix}_NAME={device['name']}")

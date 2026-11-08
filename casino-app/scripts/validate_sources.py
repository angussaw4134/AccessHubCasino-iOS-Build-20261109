"""Cross-platform resource/source checks. This is NOT an Xcode build or device test."""
from pathlib import Path
import json
import plistlib
import sys
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
issues = []
count = 0
for path in list(root.rglob("*.plist")) + list(root.rglob("*.xcprivacy")):
    if ".python-tools" in path.parts: continue
    try:
        with path.open("rb") as stream: plistlib.load(stream)
        count += 1
    except Exception as error: issues.append(f"{path}: {error}")
for pattern in ("*.storyboard", "*.xcscheme", "*.xcworkspacedata"):
    for path in root.rglob(pattern):
        try: ET.parse(path); count += 1
        except Exception as error: issues.append(f"{path}: {error}")
catalog = root / "AccessHubCasino/Assets.xcassets"
for path in catalog.rglob("Contents.json"):
    try:
        data = json.loads(path.read_text())
        for image in data.get("images", []):
            if image.get("filename") and not (path.parent / image["filename"]).is_file(): issues.append(f"Missing image for {path}")
        count += 1
    except Exception as error: issues.append(f"{path}: {error}")
sys.path.insert(0, str(root / ".python-tools"))
try:
    from openstep_parser import OpenStepDecoder
    project = OpenStepDecoder.ParseFromString((root / "AccessHubCasino.xcodeproj/project.pbxproj").read_text())
    objects = project["objects"]
    assert objects[project["rootObject"]]["isa"] == "PBXProject"
    targets = objects[project["rootObject"]]["targets"]
    assert len(targets) == 3
    for identifier, record in objects.items():
        for property in ("fileRef", "mainGroup", "buildConfigurationList", "productReference", "target", "targetProxy", "containerPortal", "baseConfigurationReference"):
            if property in record and record[property] not in objects: issues.append(f"Dangling Xcode reference {identifier}.{property}")
        for property in ("buildConfigurations", "buildPhases", "children", "files", "targets", "dependencies"):
            for reference in record.get(property, []):
                if reference not in objects: issues.append(f"Dangling Xcode reference {identifier}.{property}.{reference}")
    count += 1
    print(f"Parsed Xcode OpenStep project: {len(objects)} objects, 3 targets, no dangling references.")
except ImportError:
    print("Optional Xcode project parser unavailable: python -m pip install --target .python-tools openstep-parser")
except Exception as error:
    issues.append(f"Xcode project: {error}")
try:
    import tree_sitter
    import tree_sitter_swift
    parser = tree_sitter.Parser(tree_sitter.Language(tree_sitter_swift.language()))
    sources = list((root / "AccessHubCasino").glob("*.swift")) + list((root / "AccessHubCasinoTests").glob("*.swift")) + list((root / "AccessHubCasinoUITests").glob("*.swift"))
    for path in sources:
        source = path.read_bytes()
        tree = parser.parse(source)
        def visit(node):
            if node.type == "ERROR" or node.is_missing:
                line = source[:node.start_byte].count(b"\n") + 1
                issues.append(f"{path.relative_to(root)}:{line}: Swift parser {node.type}")
            for child in node.children: visit(child)
        visit(tree.root_node); count += 1
    print(f"Parsed {len(sources)} Swift source/test files with tree-sitter (syntax only).")
except ImportError:
    print("Swift syntax parser unavailable. Optional: python -m pip install --target .python-tools tree-sitter tree-sitter-swift")
if issues:
    print("\n".join(issues)); raise SystemExit(1)
print(f"PASS: {count} source, resource, XML and asset checks. Xcode compilation and iPhone QA still required.")

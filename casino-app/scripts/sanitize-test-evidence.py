#!/usr/bin/env python3
"""Redact CI fixture credentials from exported text evidence, never raw xcresults.

Only sanitized logs, summary JSON, attachment manifests and PNG screenshots may
be uploaded. The raw result bundles and other exported attachments remain local
to the ephemeral runner because they can retain test-process environments.
"""
from pathlib import Path
import json
import os
import sys
import urllib.parse

root = Path(sys.argv[1]).resolve()
if not root.is_dir():
    print("No test evidence directory exists yet.")
    raise SystemExit(0)

names = [f"ACCESSHUB_TEST_{kind}_{size}"
         for kind in ("USERNAME", "PASSWORD") for size in ("SMALL", "LARGE")]
names += ["TEST_RUNNER_ACCESSHUB_TEST_USERNAME", "TEST_RUNNER_ACCESSHUB_TEST_PASSWORD"]
secrets = set()
for name in names:
    value = os.environ.get(name, "")
    if value:
        secrets.update((value, json.dumps(value, ensure_ascii=True)[1:-1],
                        json.dumps(value, ensure_ascii=False)[1:-1],
                        urllib.parse.quote(value, safe="")))

patterns = sorted(secrets, key=len, reverse=True)
count = 0
for path in root.rglob("*"):
    if not path.is_file() or any(part.endswith(".xcresult") for part in path.parts):
        continue
    if path.suffix.lower() not in (".log", ".txt", ".json"):
        continue
    # Derived data includes build products; it is not published as evidence.
    if any(part in ("DerivedData", "simulator") for part in path.relative_to(root).parts):
        continue
    text = path.read_text(encoding="utf-8", errors="replace")
    for secret in patterns:
        text = text.replace(secret, "[REDACTED_TEST_CREDENTIAL]")
    path.write_text(text, encoding="utf-8")
    count += 1
print(f"Sanitized {count} text evidence files; raw result bundles remain private to the runner.")

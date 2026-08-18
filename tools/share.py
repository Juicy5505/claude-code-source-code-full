#!/usr/bin/env python3
"""Share files from your machine with Claude, through the one channel that exists.

Claude Code sessions like this one run in an isolated cloud container. It is not
on your Tailscale network, it cannot open your Obsidian vault, and it cannot read
E:\\ or /Volumes/anything. The only thing it and you both touch is this git
repository. So: put the file in the repo, push, and it can read it.

That is what this does, with the two things you would otherwise have to remember:
it REDACTS secrets before committing, and it refuses files large enough to bloat
the repo.

    python3 tools/share.py ~/Documents/swings.json
    python3 tools/share.py "C:\\Users\\Alex\\iCloudDrive\\round.json" --note "18 holes, windy"
    python3 tools/share.py ~/Obsidian/myproject/01-Sessions/*.md --push

Works on Windows, macOS and Linux; Python 3 is the only requirement.

WHAT NOT TO SHARE
-----------------
Redaction here is a safety net, not a licence. It knows the shapes this project
produces — WHOOP tokens, bearer tokens, API keys — and it will miss a secret it
has never seen. Do not share a file whose whole purpose is to hold credentials,
and remember that anything pushed to a repository is recoverable from its history
even after a later deletion.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SHARED = REPO / "_shared"

# 8 MB. Large enough for any session log or export, small enough that a stray
# video or database does not end up permanently in the repository's history.
MAX_BYTES = 8 * 1024 * 1024

# Patterns worth catching before they reach a commit. Each is (regex, label).
# Deliberately broad: a false positive costs a redacted string in a file you can
# re-share, a false negative costs a live credential in permanent git history.
REDACTIONS: list[tuple[re.Pattern[str], str]] = [
    (re.compile(r'("(?:access|refresh|id)_token"\s*:\s*")[^"]{8,}(")'), r"\1<redacted>\2"),
    (re.compile(r'("(?:client_secret|api_key|apiKey|password|secret)"\s*:\s*")[^"]{4,}(")'), r"\1<redacted>\2"),
    (re.compile(r"(Bearer\s+)[A-Za-z0-9._~+/=-]{12,}"), r"\1<redacted>"),
    (re.compile(r"((?:WHOOP_CLIENT_SECRET|WB_INGEST_TOKEN|INGEST_TOKEN)\s*[=:]\s*)\S+"), r"\1<redacted>"),
    (re.compile(r"(ingestToken\s*=\s*\")[^\"]+(\")"), r"\1<redacted>\2"),
    # Tailscale auth keys and GitHub tokens have recognisable prefixes.
    (re.compile(r"\btskey-[A-Za-z0-9-]{10,}"), "<redacted-tailscale-key>"),
    (re.compile(r"\bgh[pousr]_[A-Za-z0-9]{20,}"), "<redacted-github-token>"),
    (re.compile(r"\b(?:sk|pk)-[A-Za-z0-9]{20,}"), "<redacted-api-key>"),
]

# Files that exist only to hold credentials. Refused outright rather than
# redacted, because a redacted token file conveys nothing anyway.
NEVER_SHARE = {"tokens.json", "id_rsa", "id_ed25519", ".env", "credentials.json"}


def redact(text: str) -> tuple[str, list[str]]:
    """Returns the redacted text and which rules fired."""
    fired = []
    for pattern, replacement in REDACTIONS:
        text, count = pattern.subn(replacement, text)
        if count:
            fired.append(f"{pattern.pattern[:40]}… ({count})")
    return text, fired


def looks_binary(data: bytes) -> bool:
    # A NUL byte in the first 8 KB is the usual heuristic, and good enough: the
    # point is only to decide whether redaction can run at all.
    return b"\0" in data[:8192]


def share_one(source: Path, destination_dir: Path) -> dict | None:
    if not source.exists():
        print(f"  skip  {source} — does not exist")
        return None
    if source.is_dir():
        print(f"  skip  {source} — is a directory (pass the files inside it)")
        return None
    if source.name in NEVER_SHARE:
        print(f"  REFUSE {source.name} — this file exists to hold credentials")
        return None

    size = source.stat().st_size
    if size > MAX_BYTES:
        print(f"  skip  {source.name} — {size // 1024}KB exceeds the {MAX_BYTES // 1024}KB limit")
        return None

    raw = source.read_bytes()
    destination = destination_dir / source.name
    if looks_binary(raw):
        destination.write_bytes(raw)
        print(f"  copy  {source.name}  ({size} bytes, binary — not redacted)")
        return {"name": source.name, "bytes": size, "binary": True, "redactions": []}

    text = raw.decode("utf-8", errors="replace")
    cleaned, fired = redact(text)
    destination.write_text(cleaned, encoding="utf-8")
    note = f"  [{len(fired)} redaction rule(s) fired]" if fired else ""
    print(f"  copy  {source.name}  ({size} bytes){note}")
    for rule in fired:
        print(f"          redacted: {rule}")
    return {"name": source.name, "bytes": size, "binary": False, "redactions": fired}


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("paths", nargs="+", help="files to share")
    parser.add_argument("--note", help="what these are, for Claude to read")
    parser.add_argument("--push", action="store_true",
                        help="commit and push (otherwise just stages the files)")
    parser.add_argument("--label", help="subfolder name (default: today's date)")
    args = parser.parse_args()

    label = args.label or datetime.now().strftime("%Y-%m-%d-%H%M")
    target = SHARED / label
    target.mkdir(parents=True, exist_ok=True)

    print(f"Sharing into {target.relative_to(REPO)}\n")
    shared = [entry for path in args.paths
              if (entry := share_one(Path(path).expanduser(), target)) is not None]

    if not shared:
        print("\nNothing shared.")
        # Leave no empty directory behind.
        try:
            target.rmdir()
        except OSError:
            pass
        return 1

    manifest = {
        "sharedAt": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
        "note": args.note or "",
        "files": shared,
    }
    (target / "MANIFEST.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )

    print(f"\n{len(shared)} file(s) staged in {target.relative_to(REPO)}")

    if not args.push:
        print("\nRun again with --push to commit and send them, or:")
        print(f"  git add {SHARED.relative_to(REPO)} && git commit -m 'share: {label}' && git push")
        return 0

    subprocess.run(["git", "add", str(SHARED)], cwd=REPO, check=True)
    message = f"share: {label}" + (f" — {args.note}" if args.note else "")
    subprocess.run(["git", "commit", "-m", message], cwd=REPO, check=True)
    branch = subprocess.run(
        ["git", "rev-parse", "--abbrev-ref", "HEAD"],
        cwd=REPO, capture_output=True, text=True, check=True,
    ).stdout.strip()
    subprocess.run(["git", "push", "-u", "origin", branch], cwd=REPO, check=True)

    print(f"\nPushed to {branch}. Tell Claude to look in _shared/{label}/")
    return 0


if __name__ == "__main__":
    sys.exit(main())

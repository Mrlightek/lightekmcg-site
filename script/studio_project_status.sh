#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

python3 - "$@" <<'PY'
from pathlib import Path
from collections import Counter, defaultdict
import json
import subprocess
import sys

show_all = "--all" in sys.argv[1:]

data = json.loads(
    Path(
        "config/project_tracking/lightek_studio.json"
    ).read_text()
)

project = data["project"]
items = data["items"]

done = [
    item for item in items
    if item["status"] == "done"
]

active = [
    item for item in items
    if item["status"] == "in_progress"
]

blocked = [
    item for item in items
    if item["status"] == "blocked"
]

remaining = [
    item for item in items
    if item["status"] != "done"
]

total_points = sum(
    item["effort"]
    for item in items
)

done_points = sum(
    item["effort"]
    for item in done
)

head = subprocess.run(
    ["git", "rev-parse", "--short", "HEAD"],
    text=True,
    capture_output=True,
    check=True
).stdout.strip()

print("===== LIGHTEK STUDIO STATUS =====")
print()
print("Current git HEAD:", head)
print(
    "Production floor:",
    project["production_floor"]["commit"],
    f"({project['production_floor']['status']})"
)
print("Current phase:", project["current_phase"])

tracking = project.get(
    "tracking",
    {}
)

github = tracking.get(
    "github",
    {}
)

lightek = tracking.get(
    "lightek",
    {}
)

if github.get("project_url"):
    print(
        "GitHub Project:",
        github["project_url"]
    )

if lightek.get("model"):
    print(
        "Lightek tracking:",
        lightek["model"]
    )

print()
print(
    "Item completion:",
    f"{len(done)}/{len(items)}",
    f"({len(done) / len(items) * 100:.1f}%)"
)

print(
    "Weighted scope completion:",
    f"{done_points}/{total_points}",
    f"({done_points / total_points * 100:.1f}%)"
)

print("In progress:", len(active))
print("Blocked:", len(blocked))

if active:
    print()
    print("IN PROGRESS")
    for item in active:
        print(
            f"  {item['key']} "
            f"[{item['priority']}] "
            f"{item['title']}"
        )

print()
print("NEXT HIGH-PRIORITY WORK")

priority_order = {
    "P0": 0,
    "P1": 1,
    "P2": 2,
    "P3": 3
}

phase = project["current_phase"]

next_items = sorted(
    [
        item for item in remaining
        if item["status"] != "in_progress"
    ],
    key=lambda item: (
        0 if item["phase"] == phase else 1,
        priority_order.get(
            item["priority"],
            99
        ),
        items.index(item)
    )
)

for item in next_items[:12]:
    print(
        f"  {item['key']} "
        f"[{item['priority']}] "
        f"{item['phase']} — "
        f"{item['title']}"
    )

phase_counts = defaultdict(
    lambda: {
        "total": 0,
        "done": 0,
        "points": 0,
        "done_points": 0
    }
)

for item in items:
    row = phase_counts[item["phase"]]

    row["total"] += 1
    row["points"] += item["effort"]

    if item["status"] == "done":
        row["done"] += 1
        row["done_points"] += item["effort"]

print()
print("PHASE SUMMARY")

for phase_name, values in phase_counts.items():
    pct = (
        values["done_points"]
        / values["points"]
        * 100
        if values["points"]
        else 0
    )

    print(
        f"  {phase_name}: "
        f"{values['done']}/{values['total']} items, "
        f"{pct:.1f}% weighted"
    )

if show_all:
    print()
    print("FULL ROADMAP")

    current_phase = None

    for item in items:
        if item["phase"] != current_phase:
            current_phase = item["phase"]
            print()
            print(current_phase.upper())

        marker = {
            "done": "✓",
            "in_progress": "→",
            "blocked": "!",
            "todo": "·"
        }.get(
            item["status"],
            "·"
        )

        print(
            f"  {marker} "
            f"{item['key']} "
            f"[{item['priority']}] "
            f"({item['effort']}pt) "
            f"{item['title']}"
        )

print()
print("PRODUCT LAW")
print(
    " ",
    project["product_law"]
)
PY

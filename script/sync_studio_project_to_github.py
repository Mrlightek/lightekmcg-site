#!/usr/bin/env python3

from pathlib import Path
import json
import os
import re
import subprocess
import sys
import time


MANIFEST = Path(
    "config/project_tracking/lightek_studio.json"
)


def format_duration(seconds):
    seconds = max(
        0,
        int(seconds)
    )

    minutes, seconds = divmod(
        seconds,
        60
    )

    hours, minutes = divmod(
        minutes,
        60
    )

    if hours:
        return (
            f"{hours:02d}:"
            f"{minutes:02d}:"
            f"{seconds:02d}"
        )

    return (
        f"{minutes:02d}:"
        f"{seconds:02d}"
    )


def sync_progress(
    current,
    total,
    key,
    stage,
    started_at,
    *,
    force_line=False
):
    total = max(
        int(total),
        1
    )

    current = max(
        0,
        min(
            int(current),
            total
        )
    )

    ratio = (
        current /
        total
    )

    width = 28

    filled = round(
        ratio *
        width
    )

    bar = (
        "█" * filled +
        "░" * (
            width -
            filled
        )
    )

    elapsed = (
        time.monotonic() -
        started_at
    )

    if current > 0:
        seconds_per_item = (
            elapsed /
            current
        )

        eta = (
            total -
            current
        ) * seconds_per_item

        eta_text = format_duration(
            eta
        )
    else:
        eta_text = "--:--"

    label = (
        key or
        "starting"
    )

    line = (
        f"GitHub sync "
        f"[{bar}] "
        f"{current:>2}/{total} "
        f"{ratio * 100:5.1f}%"
        f" | {label}"
        f" | {stage}"
        f" | elapsed "
        f"{format_duration(elapsed)}"
        f" | eta {eta_text}"
    )

    if sys.stderr.isatty():
        sys.stderr.write(
            "\r\033[K" +
            line
        )

        sys.stderr.flush()

        return

    if (
        force_line or
        stage in {
            "starting",
            "complete"
        }
    ):
        print(
            line,
            file=sys.stderr,
            flush=True
        )


def finish_sync_progress():
    if sys.stderr.isatty():
        sys.stderr.write(
            "\n"
        )

        sys.stderr.flush()


def progress_demo():
    total = 12
    started_at = time.monotonic()

    sync_progress(
        0,
        total,
        None,
        "starting",
        started_at,
        force_line=True
    )

    for sequence in range(
        1,
        total + 1
    ):
        key = (
            f"STUDIO-DEMO-{sequence:03d}"
        )

        sync_progress(
            sequence - 1,
            total,
            key,
            "updating issue",
            started_at
        )

        time.sleep(
            0.04
        )

        sync_progress(
            sequence - 1,
            total,
            key,
            "updating project fields",
            started_at
        )

        time.sleep(
            0.04
        )

        sync_progress(
            sequence,
            total,
            key,
            "complete",
            started_at,
            force_line=True
        )

    finish_sync_progress()

    print(
        "Progress demo complete."
    )


if "--progress-demo" in sys.argv:
    progress_demo()
    raise SystemExit(0)


def run(args, check=True):
    result = subprocess.run(
        args,
        text=True,
        capture_output=True
    )

    if check and result.returncode != 0:
        if result.stdout:
            print(
                result.stdout,
                end=""
            )

        if result.stderr:
            print(
                result.stderr,
                end="",
                file=sys.stderr
            )

        raise SystemExit(
            "ERROR running:\n  "
            + " ".join(args)
        )

    return result


def json_run(args):
    result = run(args)

    try:
        return json.loads(
            result.stdout
        )
    except json.JSONDecodeError:
        print(
            result.stdout,
            file=sys.stderr
        )

        raise SystemExit(
            "ERROR: expected JSON from:\n  "
            + " ".join(args)
        )


def field_map(
    project_number,
    owner
):
    data = json_run([
        "gh",
        "project",
        "field-list",
        str(project_number),
        "--owner",
        owner,
        "--limit",
        "100",
        "--format",
        "json"
    ])

    return {
        field["name"]: field
        for field in data["fields"]
    }


def ensure_single_select(
    project_number,
    owner,
    name,
    options
):
    fields = field_map(
        project_number,
        owner
    )

    if name not in fields:
        print(
            f"Creating project field: {name}"
        )

        json_run([
            "gh",
            "project",
            "field-create",
            str(project_number),
            "--owner",
            owner,
            "--name",
            name,
            "--data-type",
            "SINGLE_SELECT",
            "--single-select-options",
            ",".join(options),
            "--format",
            "json"
        ])

        fields = field_map(
            project_number,
            owner
        )

    field = fields[name]

    if field["type"] != "ProjectV2SingleSelectField":
        raise SystemExit(
            f"ERROR: project field {name!r} "
            "exists but is not SINGLE_SELECT."
        )

    actual = {
        option["name"]
        for option in field.get(
            "options",
            []
        )
    }

    missing = [
        option
        for option in options
        if option not in actual
    ]

    if missing:
        raise SystemExit(
            f"ERROR: project field {name!r} "
            f"is missing options: {missing}"
        )

    return field


def ensure_number_field(
    project_number,
    owner,
    name
):
    fields = field_map(
        project_number,
        owner
    )

    if name not in fields:
        print(
            f"Creating project field: {name}"
        )

        json_run([
            "gh",
            "project",
            "field-create",
            str(project_number),
            "--owner",
            owner,
            "--name",
            name,
            "--data-type",
            "NUMBER",
            "--format",
            "json"
        ])

        fields = field_map(
            project_number,
            owner
        )

    return fields[name]


def option_id(
    field,
    name
):
    for option in field.get(
        "options",
        []
    ):
        if (
            option["name"].lower()
            == name.lower()
        ):
            return option["id"]

    raise SystemExit(
        f"ERROR: option {name!r} "
        f"not found in field "
        f"{field['name']!r}"
    )


def issue_body(item):
    evidence = (
        "\n".join(
            f"- `{entry}`"
            for entry in item["evidence"]
        )
        if item["evidence"]
        else (
            "- No single commit was assigned "
            "during the initial roadmap backfill."
        )
    )

    return f"""<!-- LIGHTEK_STUDIO_KEY:{item['key']} -->

# Lightek Studio Tracking

- **Key:** `{item['key']}`
- **Phase:** {item['phase']}
- **Area:** {item['area']}
- **Status:** {item['status']}
- **Priority:** {item['priority']}
- **Effort:** {item['effort']} points

## Objective

{item['summary']}

## Evidence / known floor

{evidence}

## Product law

> What should Marlon have to do to create something?

Minimize that work. Backend complexity belongs to Lightek.

## Source of truth

`config/project_tracking/lightek_studio.json`

This issue is synchronized from the canonical Lightek Studio roadmap.
"""


def desired_github_status(status):
    if status == "done":
        return "Done"

    if status == "in_progress":
        return "In Progress"

    if status == "blocked":
        return "In Progress"

    return "Todo"


print(
    "===== LOAD CANONICAL MANIFEST ====="
)

data = json.loads(
    MANIFEST.read_text()
)

project_config = data["project"]
items = data["items"]

print(
    f"Items: {len(items)}"
)

print(
    "Current phase:",
    project_config["current_phase"]
)


print()
print(
    "===== DETECT REPOSITORY ====="
)

repo_info = json_run([
    "gh",
    "repo",
    "view",
    "--json",
    "nameWithOwner,name"
])

repo = repo_info[
    "nameWithOwner"
]

repo_name = repo_info[
    "name"
]

repo_owner = repo.split(
    "/",
    1
)[0]

owner = os.environ.get(
    "LIGHTEK_GITHUB_PROJECT_OWNER",
    repo_owner
)

print(
    "Repository:",
    repo
)

print(
    "Project owner:",
    owner
)


print()
print(
    "===== FIND OR CREATE GITHUB PROJECT ====="
)

title = project_config[
    "title"
]

projects = json_run([
    "gh",
    "project",
    "list",
    "--owner",
    owner,
    "--limit",
    "100",
    "--format",
    "json"
])

match = next(
    (
        project
        for project
        in projects.get(
            "projects",
            []
        )
        if project.get(
            "title"
        ) == title
    ),
    None
)

if match is None:
    print(
        "Creating GitHub Project:",
        title
    )

    match = json_run([
        "gh",
        "project",
        "create",
        "--owner",
        owner,
        "--title",
        title,
        "--format",
        "json"
    ])
else:
    print(
        "Using existing project:",
        title
    )

project_number = match[
    "number"
]

project_detail = json_run([
    "gh",
    "project",
    "view",
    str(project_number),
    "--owner",
    owner,
    "--format",
    "json"
])

project_id = project_detail[
    "id"
]

project_url = project_detail[
    "url"
]


done_items = [
    item
    for item in items
    if item["status"] == "done"
]

total_points = sum(
    item["effort"]
    for item in items
)

done_points = sum(
    item["effort"]
    for item in done_items
)

weighted_pct = (
    done_points
    / total_points
    * 100
)

readme = f"""# Lightek Studio

## Product law

**What should Marlon have to do to create something?**

Minimize that work. Backend complexity belongs to Lightek.

## Experience architecture

- Intent first
- UI/UX first
- Templates compress complexity
- PWA = approachable control surface
- Nevaeh = production intelligence
- Gatekeeper = capability/security boundary
- Blender = authoritative production runtime

## Current phase

**{project_config['current_phase']}**

## Production floor

`{project_config['production_floor']['commit']}` — {project_config['production_floor']['status']}

{project_config['production_floor']['description']}

## Tracking

- {len(done_items)}/{len(items)} roadmap items complete
- {done_points}/{total_points} weighted effort points complete
- {weighted_pct:.1f}% weighted tracked scope complete

The weighted percentage describes the currently documented scope.
It is not a delivery-date estimate and can change when scope changes.

## Canonical source

`config/project_tracking/lightek_studio.json`
"""

run([
    "gh",
    "project",
    "edit",
    str(project_number),
    "--owner",
    owner,
    "--description",
    (
        "Canonical roadmap for Lightek Studio: "
        "intent-first UX, Blender capability integration, "
        "templates, production systems and Lightek-wide creation."
    ),
    "--readme",
    readme
])


print()
print(
    "===== LINK PROJECT TO REPOSITORY ====="
)

link = run([
    "gh",
    "project",
    "link",
    str(project_number),
    "--owner",
    owner,
    "--repo",
    repo_name
], check=False)

if link.returncode == 0:
    print(
        "Project linked to repository."
    )
else:
    message = (
        link.stderr
        + link.stdout
    ).strip()

    if "already" in message.lower():
        print(
            "Project was already linked."
        )
    else:
        print(
            "WARNING: project link returned:"
        )
        print(
            message
        )


print()
print(
    "===== ENSURE PROJECT FIELDS ====="
)

phase_options = list(
    dict.fromkeys(
        item["phase"]
        for item in items
    )
)

priority_options = [
    "P0",
    "P1",
    "P2",
    "P3"
]

phase_field = ensure_single_select(
    project_number,
    owner,
    "Phase",
    phase_options
)

priority_field = ensure_single_select(
    project_number,
    owner,
    "Priority",
    priority_options
)

effort_field = ensure_number_field(
    project_number,
    owner,
    "Effort"
)

sequence_field = ensure_number_field(
    project_number,
    owner,
    "Sequence"
)

fields = field_map(
    project_number,
    owner
)

if "Status" not in fields:
    raise SystemExit(
        "ERROR: GitHub Project has no Status field."
    )

status_field = fields[
    "Status"
]

for required in [
    "Todo",
    "In Progress",
    "Done"
]:
    option_id(
        status_field,
        required
    )

print(
    "Project fields ready."
)


print()
print(
    "===== READ EXISTING TRACKED ISSUES ====="
)

existing_issues = json_run([
    "gh",
    "issue",
    "list",
    "--repo",
    repo,
    "--state",
    "all",
    "--limit",
    "500",
    "--json",
    "number,title,url,state,body"
])

issues_by_key = {}
issues_by_title = {}

marker_re = re.compile(
    r"<!-- LIGHTEK_STUDIO_KEY:([A-Z0-9-]+) -->"
)

for issue in existing_issues:
    issues_by_title[
        issue["title"]
    ] = issue

    match_key = marker_re.search(
        issue.get(
            "body",
            ""
        )
    )

    if match_key:
        issues_by_key[
            match_key.group(1)
        ] = issue


print()
print(
    "===== READ EXISTING PROJECT ITEMS ====="
)

project_items_data = json_run([
    "gh",
    "project",
    "item-list",
    str(project_number),
    "--owner",
    owner,
    "--limit",
    "500",
    "--format",
    "json"
])

project_items_by_url = {
    item["url"]: item
    for item
    in project_items_data.get(
        "items",
        []
    )
    if item.get(
        "url"
    )
}


def set_select(
    project_item_id,
    field,
    value
):
    run([
        "gh",
        "project",
        "item-edit",
        "--id",
        project_item_id,
        "--field-id",
        field["id"],
        "--project-id",
        project_id,
        "--single-select-option-id",
        option_id(
            field,
            value
        )
    ])


def set_number(
    project_item_id,
    field,
    value
):
    run([
        "gh",
        "project",
        "item-edit",
        "--id",
        project_item_id,
        "--field-id",
        field["id"],
        "--project-id",
        project_id,
        "--number",
        str(value)
    ])


print()
print(
    "===== SYNCHRONIZE ROADMAP ====="
)

created = 0
updated = 0

sync_total = len(items)
sync_started_at = time.monotonic()

sync_progress(
    0,
    sync_total,
    None,
    "starting",
    sync_started_at,
    force_line=True
)

for sequence, item in enumerate(
    items,
    start=1
):
    key = item[
        "key"
    ]

    title_text = (
        f"[{key}] "
        f"{item['title']}"
    )

    body = issue_body(
        item
    )

    issue = (
        issues_by_key.get(
            key
        )
        or issues_by_title.get(
            title_text
        )
    )

    if issue is None:
        sync_progress(
            sequence - 1,
            sync_total,
            key,
            "creating issue",
            sync_started_at
        )

        url = run([
            "gh",
            "issue",
            "create",
            "--repo",
            repo,
            "--title",
            title_text,
            "--body",
            body
        ]).stdout.strip()

        number = int(
            url.rstrip(
                "/"
            ).split(
                "/"
            )[-1]
        )

        issue = json_run([
            "gh",
            "issue",
            "view",
            str(number),
            "--repo",
            repo,
            "--json",
            "number,title,url,state,body"
        ])

        created += 1
    else:
        sync_progress(
            sequence - 1,
            sync_total,
            key,
            "updating issue",
            sync_started_at
        )

        run([
            "gh",
            "issue",
            "edit",
            str(issue["number"]),
            "--repo",
            repo,
            "--title",
            title_text,
            "--body",
            body
        ])

        updated += 1

    issue_state = issue[
        "state"
    ].upper()

    if (
        item["status"] == "done"
        and issue_state != "CLOSED"
    ):
        run([
            "gh",
            "issue",
            "close",
            str(issue["number"]),
            "--repo",
            repo,
            "--reason",
            "completed"
        ])

    elif (
        item["status"] != "done"
        and issue_state == "CLOSED"
    ):
        run([
            "gh",
            "issue",
            "reopen",
            str(issue["number"]),
            "--repo",
            repo
        ])

    issue_url = issue[
        "url"
    ]

    project_item = project_items_by_url.get(
        issue_url
    )

    if project_item is None:
        sync_progress(
            sequence - 1,
            sync_total,
            key,
            "adding to project",
            sync_started_at
        )

        project_item = json_run([
            "gh",
            "project",
            "item-add",
            str(project_number),
            "--owner",
            owner,
            "--url",
            issue_url,
            "--format",
            "json"
        ])

        project_items_by_url[
            issue_url
        ] = project_item

    project_item_id = project_item[
        "id"
    ]

    sync_progress(
        sequence - 1,
        sync_total,
        key,
        "updating project fields",
        sync_started_at
    )

    set_select(
        project_item_id,
        status_field,
        desired_github_status(
            item["status"]
        )
    )

    set_select(
        project_item_id,
        phase_field,
        item["phase"]
    )

    set_select(
        project_item_id,
        priority_field,
        item["priority"]
    )

    set_number(
        project_item_id,
        effort_field,
        item["effort"]
    )

    set_number(
        project_item_id,
        sequence_field,
        sequence
    )

    sync_progress(
        sequence,
        sync_total,
        key,
        "complete",
        sync_started_at,
        force_line=True
    )


finish_sync_progress()

print()
print(
    "===== SYNC COMPLETE ====="
)

print(
    "GitHub Project:",
    project_url
)

print(
    "Project number:",
    project_number
)

print(
    "Issues created:",
    created
)

print(
    "Issues updated:",
    updated
)

print(
    "Tracked items:",
    len(items)
)

print(
    "Completed items:",
    len(done_items)
)

print(
    "Weighted completion:",
    f"{weighted_pct:.1f}%"
)

print()
print(
    "Open the project:"
)

print(
    f"gh project view {project_number} "
    f"--owner {owner} --web"
)

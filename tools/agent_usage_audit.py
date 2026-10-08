#!/usr/bin/env python3
"""Read a selected local Codex thread tree; export usage, never message bodies.

Local rollout schema is not a public stable API. Fail on inconsistent counters;
deduplicate repeated snapshots and merge continuation files by thread ID.
"""
import argparse
import hashlib
import json
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path


FIELDS = (
    "input_tokens", "cached_input_tokens", "cache_write_input_tokens",
    "output_tokens", "reasoning_output_tokens", "total_tokens",
)


def instant(value):
    result = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if result.tzinfo is None:
        raise ValueError("timezone required")
    return result.astimezone(timezone.utc)


def usage(value):
    if not isinstance(value, dict):
        raise ValueError("missing usage")
    # Missing fields are unavailable, never silently zero.
    if any(type(value.get(k)) is not int or value[k] < 0 for k in FIELDS):
        raise ValueError("invalid or missing usage field")
    if value["cached_input_tokens"] + value["cache_write_input_tokens"] > value["input_tokens"]:
        raise ValueError("input detail overflow")
    if value["reasoning_output_tokens"] > value["output_tokens"]:
        raise ValueError("output detail overflow")
    if value["total_tokens"] != value["input_tokens"] + value["output_tokens"]:
        raise ValueError("total mismatch")
    return {k: value[k] for k in FIELDS}


def load_tree(directory, project, root):
    """Read metadata first; parse bodies only for this project's selected tree."""
    candidates = []
    for path in sorted(directory.rglob("*.jsonl")):
        with path.open(encoding="utf-8") as stream:
            first = stream.readline()
        try:
            record = json.loads(first)
        except ValueError:
            continue
        meta = record.get("payload", {})
        if record.get("type") != "session_meta" or meta.get("cwd") != str(project):
            continue
        if not isinstance(meta.get("id"), str):
            continue
        candidates.append((path, meta))
    selected = {root}
    while True:
        added = {m["id"] for _, m in candidates if m.get("parent_thread_id") in selected}
        if added <= selected:
            break
        selected.update(added)
    threads = {}
    files = 0
    for path, meta in candidates:
        if meta["id"] not in selected:
            continue
        thread = threads.setdefault(meta["id"], {"meta": meta, "events": []})
        files += 1
        # Ignore only a live writer's incomplete final line, not earlier damage.
        with path.open(encoding="utf-8") as stream:
            for number, line in enumerate(stream, 1):
                try:
                    record = json.loads(line)
                except ValueError:
                    if not line.endswith("\n") and stream.read() == "":
                        break
                    raise ValueError("malformed rollout record") from None
                if record.get("type") in ("turn_context", "event_msg"):
                    thread["events"].append(record)
    if root not in threads:
        raise ValueError("root thread not found in project")
    return threads, files


def summarize(threads, root, since=None, until=None):
    groups = {}
    session_rows = []
    diagnostics = Counter()
    for thread_id, thread in sorted(threads.items()):
        previous = None
        model, effort = "unavailable", "unavailable"
        own = Counter()
        first_input = None
        first_cached = None
        first_time = last_time = None
        models = set()
        for record in sorted(thread["events"], key=lambda r: instant(r["timestamp"])):
            payload = record.get("payload", {})
            if record["type"] == "turn_context":
                model = payload.get("model") or "unavailable"
                effort = payload.get("effort") or payload.get("reasoning_effort") or "unavailable"
                continue
            if payload.get("type") != "token_count" or not payload.get("info"):
                continue
            info = payload["info"]
            total = usage(info.get("total_token_usage"))
            at = instant(record["timestamp"])
            in_window = (since is None or at >= since) and (until is None or at < until)
            if previous is not None and total == previous:
                if in_window:
                    diagnostics["duplicate_snapshots"] += 1
                continue
            last = usage(info.get("last_token_usage"))
            if previous is None:
                # A truncated/resumed file may start with historical carry-in.
                delta = last
                if any(total[k] < last[k] for k in FIELDS):
                    raise ValueError("invalid initial carry-in")
                if total != last:
                    diagnostics["carry_in_sessions"] += 1
            else:
                delta = {k: total[k] - previous[k] for k in FIELDS}
                if any(v < 0 for v in delta.values()):
                    raise ValueError("counter reset: segment manually before comparison")
                if delta != last:
                    raise ValueError("usage gap: cannot attribute missing calls")
                usage(delta)
            previous = total
            if not in_window:
                continue
            role = "main" if thread_id == root else (
                "automatic_review" if model == "codex-auto-review" else "subagent"
            )
            key = (role, model, effort)
            group = groups.setdefault(key, Counter())
            group.update(delta)
            group["calls"] += 1
            own.update(delta)
            own["calls"] += 1
            models.add((model, effort))
            if first_input is None:
                first_input, first_cached = delta["input_tokens"], delta["cached_input_tokens"]
                first_time = record["timestamp"]
            last_time = record["timestamp"]
        if own:
            # Hash labels; do not export IDs, account metadata, prompts or paths.
            row = metrics(own)
            row.update(session_label=hashlib.sha256(thread_id.encode()).hexdigest()[:16],
                       role="main" if thread_id == root else "child",
                       models=[list(m) for m in sorted(models)],
                       first_observed_input_tokens=first_input,
                       first_observed_cached_tokens=first_cached,
                       first_usage_at=first_time, last_usage_at=last_time)
            session_rows.append(row)
    totals = Counter()
    rows = []
    for (role, model, effort), values in sorted(groups.items()):
        totals.update(values)
        rows.append(dict(role=role, model=model, effort=effort, **metrics(values)))
    return dict(schema_version=1, since=since.isoformat() if since else None,
                until_exclusive=until.isoformat() if until else None,
                groups=rows, sessions=session_rows, totals=metrics(totals),
                diagnostics=dict(diagnostics), billing_cost=None,
                warning="Observed rollout counters, not an invoice or controlled A/B result.")


def metrics(values):
    result = dict(values)
    if not values:
        return result
    result["noncached_input_tokens"] = values["input_tokens"] - values["cached_input_tokens"]
    result["cache_read_fraction"] = (values["cached_input_tokens"] / values["input_tokens"]
                                     if values["input_tokens"] else None)
    # Reasoning is already included in output, never add it a second time.
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sessions-dir", type=Path, required=True)
    parser.add_argument("--project", type=Path, required=True)
    parser.add_argument("--root-thread", required=True)
    parser.add_argument("--since", type=instant)
    parser.add_argument("--until", type=instant)
    args = parser.parse_args()
    if args.since and args.until and args.since >= args.until:
        parser.error("since must precede until")
    try:
        threads, files = load_tree(args.sessions_dir, args.project, args.root_thread)
        report = summarize(threads, args.root_thread, args.since, args.until)
    except (ValueError, OSError, KeyError):
        parser.exit(2, "Usage audit failed: incomplete or inconsistent local metadata/counters.\n")
    report["source_files"] = files
    report["source_threads"] = len(threads)
    print(json.dumps(report, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()

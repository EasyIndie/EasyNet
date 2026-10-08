"""Synthetic usage fixtures; never read personal Codex sessions in tests."""
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location(
    "agent_usage_audit", Path(__file__).resolve().parents[1] / "tools/agent_usage_audit.py"
)
audit = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(audit)


def tokens(i=100, c=80, o=10, r=4):
    return dict(input_tokens=i, cached_input_tokens=c, cache_write_input_tokens=0,
                output_tokens=o, reasoning_output_tokens=r, total_tokens=i + o)


def event(second, total=None, last=None):
    total = total or tokens()
    return dict(timestamp=f"2026-10-08T00:00:{second:02d}Z", type="event_msg",
                payload=dict(type="token_count", info=dict(
                    total_token_usage=total, last_token_usage=last or total)))


def context(second=0, model="test-model", effort="medium"):
    return dict(timestamp=f"2026-10-08T00:00:{second:02d}Z", type="turn_context",
                payload=dict(model=model, effort=effort))


def tree(events):
    return {"root": dict(meta={}, events=events)}


class UsageAuditTests(unittest.TestCase):
    def test_duplicate_snapshot_and_reasoning_not_double_counted(self):
        report = audit.summarize(tree([context(), event(1), event(2)]), "root")
        self.assertEqual(report["totals"]["calls"], 1)
        self.assertEqual(report["totals"]["total_tokens"], 110)
        self.assertEqual(report["diagnostics"]["duplicate_snapshots"], 1)
        self.assertEqual(report["totals"]["noncached_input_tokens"], 20)

    def test_first_record_carry_in_is_not_new_usage(self):
        report = audit.summarize(tree([context(), event(1, tokens(300, 240, 30, 12),
                                                                   tokens())]), "root")
        self.assertEqual(report["totals"]["input_tokens"], 100)
        self.assertEqual(report["diagnostics"]["carry_in_sessions"], 1)

    def test_model_switch_and_time_window_use_incremental_usage(self):
        report = audit.summarize(tree([
            context(), event(1), context(2, "next-model", "high"),
            event(3, tokens(200, 160, 20, 8), tokens()),
        ]), "root", audit.instant("2026-10-08T00:00:02Z"),
            audit.instant("2026-10-08T00:00:04Z"))
        self.assertEqual(report["totals"]["input_tokens"], 100)
        self.assertEqual(report["groups"][0]["model"], "next-model")
        self.assertEqual(report["groups"][0]["effort"], "high")

    def test_missing_usage_field_is_unavailable_not_zero(self):
        value = tokens()
        del value["cache_write_input_tokens"]
        with self.assertRaises(ValueError):
            audit.usage(value)

    def test_inconsistent_details_and_bool_counter_rejected(self):
        for value in [tokens(c=101), tokens(r=11), tokens(i=True)]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                audit.usage(value)

    def test_gap_and_reset_require_manual_segmentation(self):
        for total in [tokens(300, 240, 30, 12), tokens(50, 40, 5, 2)]:
            with self.subTest(total=total), self.assertRaises(ValueError):
                audit.summarize(tree([context(), event(1), event(2, total, tokens())]), "root")

    def test_automatic_review_not_mixed_with_worker(self):
        threads = tree([context(), event(1)])
        threads["child"] = dict(meta={}, events=[context(model="codex-auto-review"), event(2)])
        report = audit.summarize(threads, "root")
        self.assertEqual({r["role"] for r in report["groups"]}, {"main", "automatic_review"})
        self.assertEqual(report["totals"]["calls"], 2)
        self.assertIsNone(report["billing_cost"])

    def test_continuations_descendants_and_private_content(self):
        with tempfile.TemporaryDirectory() as name:
            directory = Path(name)

            def write(filename, thread_id, parent=None, project="/fixture", extra=()):
                records = [dict(type="session_meta", payload=dict(
                    id=thread_id, parent_thread_id=parent, cwd=project,
                    creator_account_id="PRIVATE-ACCOUNT", base_instructions="PRIVATE-PROMPT")),
                    context(), event(1), *extra]
                (directory / filename).write_text("".join(json.dumps(r) + "\n" for r in records))

            write("root.jsonl", "root")
            write("continued.jsonl", "root", extra=[event(2, tokens(200, 160, 20, 8), tokens())])
            write("child.jsonl", "child", "root")
            write("grandchild.jsonl", "grandchild", "child")
            write("unrelated.jsonl", "other")
            write("other-project.jsonl", "elsewhere", "root", "/other")
            threads, files = audit.load_tree(directory, Path("/fixture"), "root")
            self.assertEqual(files, 4)
            self.assertEqual(set(threads), {"root", "child", "grandchild"})
            result = audit.summarize(threads, "root")
            self.assertEqual(result["totals"]["calls"], 4)
            self.assertNotIn("PRIVATE", json.dumps(result))
            self.assertNotIn("grandchild", json.dumps(result))

    def test_only_final_unfinished_line_may_be_ignored(self):
        with tempfile.TemporaryDirectory() as name:
            directory = Path(name)
            path = directory / "root.jsonl"
            meta = json.dumps(dict(type="session_meta", payload=dict(id="root", cwd="/fixture")))
            path.write_text(meta + "\n" + json.dumps(context()) + "\n{" )
            self.assertEqual(audit.load_tree(directory, Path("/fixture"), "root")[1], 1)
            path.write_text(meta + "\n{\n" + json.dumps(context()) + "\n")
            with self.assertRaises(ValueError):
                audit.load_tree(directory, Path("/fixture"), "root")


if __name__ == "__main__":
    unittest.main()

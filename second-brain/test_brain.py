#!/usr/bin/env python3
"""Tests for the brain CLI.

Run:  python3 second-brain/test_brain.py

No dependencies, matching the rest of this repo. Every test runs against a real
temporary vault on disk rather than mocks, because the failure modes that matter
here are filesystem ones: clobbering a note, duplicating a section, losing the
binding between a project and its vault.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

BRAIN = Path(__file__).resolve().parent / "brain"


class VaultCase(unittest.TestCase):
    """A throwaway project bound to a throwaway vault, per test."""

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.project = root / "proj"
        self.project.mkdir()
        (self.project / ".git").mkdir()  # makes it a project root
        self.env = {
            **os.environ,
            "HOME": str(root / "home"),
            "BRAIN_VAULT_ROOT": str(root / "vaults"),
        }
        (root / "home").mkdir()
        self.brain("init")
        self.vault = root / "vaults" / "proj"

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def brain(self, *args: str, stdin: str = "", check: bool = True):
        proc = subprocess.run(
            [sys.executable, str(BRAIN), *args],
            cwd=self.project, env=self.env, input=stdin,
            capture_output=True, text=True,
        )
        if check and proc.returncode != 0:
            self.fail(f"brain {' '.join(args)} failed ({proc.returncode})\n{proc.stderr}")
        return proc

    def session_text(self) -> str:
        notes = list((self.vault / "01-Sessions").glob("*.md"))
        self.assertEqual(len(notes), 1, "expected exactly one session note")
        return notes[0].read_text(encoding="utf-8")


class TestInit(VaultCase):
    def test_creates_the_full_layout(self):
        for folder in ("00-Inbox", "01-Sessions", "02-Decisions", "03-Knowledge",
                       "04-Code", "05-Graph", "06-Integrations", "99-Meta"):
            self.assertTrue((self.vault / folder).is_dir(), folder)
        self.assertTrue((self.vault / "MOC.md").exists())
        self.assertTrue((self.vault / "CLAUDE.md").exists())
        self.assertTrue((self.vault / "99-Meta" / "Toolchain.md").exists())
        # .obsidian is what makes Obsidian open it as a vault rather than
        # prompting to create one.
        self.assertTrue((self.vault / ".obsidian" / "app.json").exists())

    def test_binds_the_project_via_a_committable_marker(self):
        marker = json.loads((self.project / ".brain.json").read_text())
        self.assertEqual(Path(marker["vault"]), self.vault)

    def test_re_init_does_not_clobber_existing_notes(self):
        moc = self.vault / "MOC.md"
        moc.write_text("# hand-edited, do not lose this\n", encoding="utf-8")
        self.brain("init")
        self.assertIn("hand-edited", moc.read_text(encoding="utf-8"))

    def test_where_resolves_from_a_subdirectory(self):
        nested = self.project / "src" / "deep"
        nested.mkdir(parents=True)
        proc = subprocess.run(
            [sys.executable, str(BRAIN), "where"],
            cwd=nested, env=self.env, capture_output=True, text=True,
        )
        self.assertEqual(proc.stdout.strip(), str(self.vault))

    def test_unbound_project_says_what_to_run(self):
        loose = Path(self.tmp.name) / "loose"
        loose.mkdir()
        proc = subprocess.run(
            [sys.executable, str(BRAIN), "where"],
            cwd=loose, env=self.env, capture_output=True, text=True,
        )
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("brain init", proc.stderr)


class TestCapture(VaultCase):
    def test_prompt_records_verbatim_as_a_blockquote(self):
        self.brain("prompt", "line one\nline two")
        text = self.session_text()
        self.assertIn("> line one", text)
        self.assertIn("> line two", text)

    def test_prompt_accepts_the_hook_json_payload(self):
        self.brain("prompt", stdin=json.dumps({"session_id": "s", "prompt": "from the hook"}))
        self.assertIn("> from the hook", self.session_text())

    def test_empty_prompt_writes_nothing(self):
        before = self.session_text()
        self.brain("prompt", stdin=json.dumps({"prompt": "   "}))
        self.assertEqual(before, self.session_text())

    def test_entries_land_in_their_own_sections(self):
        self.brain("prompt", "asked")
        self.brain("log", "did", "--kind", "build")
        text = self.session_text()
        prompts = text.split("## Prompts")[1].split("## ")[0]
        actions = text.split("## Actions")[1].split("## ")[0]
        self.assertIn("asked", prompts)
        self.assertNotIn("did", prompts)
        self.assertIn("did", actions)

    def test_prompts_stay_grouped_when_interleaved_with_actions(self):
        # The whole reason add_to_section rewrites rather than appends: a day's
        # prompts must read as a list, not be scattered through the actions.
        self.brain("prompt", "first")
        self.brain("log", "middle")
        self.brain("prompt", "second")
        prompts = self.session_text().split("## Prompts")[1].split("## ")[0]
        self.assertIn("first", prompts)
        self.assertIn("second", prompts)
        self.assertNotIn("middle", prompts)


class TestToolHook(VaultCase):
    def payload(self, tool: str, path: str) -> str:
        return json.dumps({"tool_name": tool, "tool_input": {"file_path": path}})

    def test_records_a_file_change_as_a_repo_relative_path(self):
        self.brain("tool", stdin=self.payload("Write", str(self.project / "src/app.ts")))
        self.assertIn("`src/app.ts`", self.session_text())

    def test_same_file_twice_is_recorded_once(self):
        self.brain("tool", stdin=self.payload("Write", str(self.project / "src/app.ts")))
        self.brain("tool", stdin=self.payload("Edit", str(self.project / "src/app.ts")))
        self.assertEqual(self.session_text().count("`src/app.ts`"), 1)

    def test_a_tool_with_no_file_is_ignored(self):
        before = self.session_text()
        self.brain("tool", stdin=json.dumps({"tool_name": "Grep", "tool_input": {"pattern": "x"}}))
        self.assertEqual(before, self.session_text())

    def test_malformed_payload_never_fails_the_tool_call(self):
        # A hook that exits non-zero on garbage would break the user's session.
        proc = self.brain("tool", stdin="not json at all", check=False)
        self.assertEqual(proc.returncode, 0)


class TestDecisionsAndKnowledge(VaultCase):
    def test_decision_writes_a_note_and_links_it_from_the_session(self):
        self.brain("decision", "Use the watch", "--why", "WHOOP has no motion API")
        notes = list((self.vault / "02-Decisions").glob("*.md"))
        self.assertEqual(len(notes), 1)
        body = notes[0].read_text(encoding="utf-8")
        self.assertIn("WHOOP has no motion API", body)
        self.assertIn("## Revisit if", body)
        self.assertIn("Use the watch", self.session_text())

    def test_decision_refuses_to_overwrite_a_same_day_duplicate(self):
        self.brain("decision", "Use the watch")
        proc = self.brain("decision", "Use the watch", check=False)
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("exists", proc.stderr)

    def test_titles_with_link_breaking_characters_are_made_safe(self):
        self.brain("decision", "Use [[brackets]] and slash/es | pipes")
        name = next((self.vault / "02-Decisions").glob("*.md")).name
        for bad in "[]|/":
            self.assertNotIn(bad, name)

    def test_note_revises_rather_than_replaces(self):
        self.brain("note", "BLE facts", "--body", "original finding")
        self.brain("note", "BLE facts", "--body", "corrected finding")
        body = (self.vault / "03-Knowledge" / "BLE facts.md").read_text(encoding="utf-8")
        self.assertIn("original finding", body)
        self.assertIn("corrected finding", body)
        self.assertIn("Revised", body)


class TestIndexAndRecall(VaultCase):
    def test_index_is_idempotent(self):
        self.brain("decision", "A choice")
        self.brain("index")
        first = (self.vault / "MOC.md").read_text(encoding="utf-8")
        self.brain("index")
        self.brain("index")
        self.assertEqual(first, (self.vault / "MOC.md").read_text(encoding="utf-8"))

    def test_index_surfaces_orphan_notes(self):
        # A note nothing links to is the silent failure of a memory vault: it
        # was written, so it feels captured, but nothing leads back to it.
        (self.vault / "03-Knowledge" / "Stranded.md").write_text("# Stranded\n", encoding="utf-8")
        (self.vault / "00-Inbox" / "Orphan.md").write_text("# Orphan\n", encoding="utf-8")
        self.brain("index")
        unlinked = (self.vault / "MOC.md").read_text(encoding="utf-8").split("## Unlinked")[1]
        self.assertIn("Orphan", unlinked)

    def test_recall_carries_decisions_and_open_threads(self):
        self.brain("decision", "Settled thing")
        self.brain("prompt", "something was asked")
        self.brain("session-end", "half-finished migration")
        out = self.brain("recall").stdout
        self.assertIn("Settled thing", out)
        self.assertIn("half-finished migration", out)
        self.assertIn("do not re-litigate", out)

    def test_session_start_is_silent_in_an_unbound_directory(self):
        # Most directories are not brain-backed. A hook that shouts in all of
        # them gets disabled within a day.
        loose = Path(self.tmp.name) / "elsewhere"
        loose.mkdir()
        proc = subprocess.run(
            [sys.executable, str(BRAIN), "session-start"],
            cwd=loose, env=self.env, capture_output=True, text=True,
        )
        self.assertEqual(proc.returncode, 0)
        self.assertEqual(proc.stdout.strip(), "")

    def test_session_end_writes_nothing_when_nothing_was_asked(self):
        self.brain("session-end", stdin=json.dumps({"reason": "clear"}))
        threads = (self.vault / "99-Meta" / "Open Threads.md").read_text(encoding="utf-8")
        self.assertNotIn("session ended", threads)

    def test_session_end_carries_the_thread_forward_when_work_happened(self):
        self.brain("prompt", "do the thing")
        self.brain("session-end", stdin=json.dumps({"reason": "clear"}))
        threads = (self.vault / "99-Meta" / "Open Threads.md").read_text(encoding="utf-8")
        self.assertIn("session ended (clear)", threads)

    def test_search_finds_across_folders(self):
        self.brain("note", "Findable", "--body", "a distinctive phrase")
        out = self.brain("search", "distinctive phrase").stdout
        self.assertIn("Findable", out)

    def test_search_reports_a_miss_without_crashing(self):
        proc = self.brain("search", "nothing matches this", check=False)
        self.assertEqual(proc.returncode, 1)
        self.assertIn("no match", proc.stdout)


class TestGraph(VaultCase):
    """Graphify wiring. The build path needs graphify installed, so what is
    asserted here is the behaviour when it is not — which is the state most
    machines are in, and the one where a bad error message costs the most."""

    def test_missing_graphify_explains_how_to_install_it(self):
        env = {**self.env, "PATH": "/nonexistent"}
        proc = subprocess.run(
            [sys.executable, str(BRAIN), "graph"],
            cwd=self.project, env=env, capture_output=True, text=True,
        )
        self.assertEqual(proc.returncode, 1)
        self.assertIn("uv tool install graphifyy", proc.stderr)
        self.assertIn("graphify install", proc.stderr)

    def test_a_query_without_graphify_reports_the_tool_not_the_graph(self):
        # Precedence matters: "no graph yet" would send someone off to build one
        # with a binary they do not have.
        env = {**self.env, "PATH": "/nonexistent"}
        proc = subprocess.run(
            [sys.executable, str(BRAIN), "graph", "--query", "what calls this?"],
            cwd=self.project, env=env, capture_output=True, text=True,
        )
        self.assertIn("graphify is not installed", proc.stderr)

    @unittest.skipUnless(shutil.which("graphify"), "graphify not installed here")
    def test_querying_before_building_says_so(self):
        proc = self.brain("graph", "--query", "what calls this?", check=False)
        self.assertEqual(proc.returncode, 1)
        self.assertIn("no graph yet", proc.stderr)

    @unittest.skipUnless(shutil.which("graphify"), "graphify not installed here")
    def test_build_writes_into_the_vault(self):
        self.brain("graph", "--code-only")
        self.assertTrue((self.vault / "05-Graph" / "Code Graph.md").exists())


class TestSafety(VaultCase):
    def test_a_corrupt_registry_fails_loud_instead_of_orphaning_vaults(self):
        registry = Path(self.env["HOME"]) / ".brain" / "vaults.json"
        registry.write_text("{ truncated", encoding="utf-8")
        proc = self.brain("list", check=False)
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("not valid JSON", proc.stderr)

    def test_a_missing_vault_is_reported_not_recreated(self):

        shutil.rmtree(self.vault)
        proc = self.brain("log", "anything", check=False)
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("registered but missing", proc.stderr)

    def test_doctor_reports_without_crashing_and_flags_what_is_missing(self):
        proc = self.brain("doctor", check=False)
        self.assertIn("checks passing", proc.stdout)
        for tool in ("graphify", "hermes", "openclaw", "figma mcp"):
            self.assertIn(tool, proc.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)

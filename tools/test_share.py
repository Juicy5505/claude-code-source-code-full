"""Tests for the file-sharing helper.

This tool copies files from a personal machine into a git repository, which is
permanent and public-ish by default. Its redaction is the only thing standing
between a pasted config and a live credential in git history forever, so it is
tested against the shapes this project actually produces.

    python3 tools/test_share.py
"""

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import share


class TestRedaction(unittest.TestCase):
    def redacted(self, text):
        return share.redact(text)[0]

    def assert_gone(self, secret, text):
        out = self.redacted(text)
        self.assertNotIn(secret, out, f"secret survived redaction: {out!r}")
        self.assertIn("redacted", out)

    def test_whoop_oauth_tokens(self):
        self.assert_gone(
            "eyJhbGciOiJIUzI1NiJ9.PAYLOAD.SIG",
            '{"access_token": "eyJhbGciOiJIUzI1NiJ9.PAYLOAD.SIG"}',
        )
        self.assert_gone(
            "rt_9f8a7b6c5d4e3f2a",
            '{"refresh_token": "rt_9f8a7b6c5d4e3f2a"}',
        )

    def test_client_secret_and_api_keys(self):
        self.assert_gone("s3cr3tvalue", '{"client_secret": "s3cr3tvalue"}')
        self.assert_gone("hunter2hunter2", '{"password": "hunter2hunter2"}')

    def test_bearer_headers(self):
        self.assert_gone(
            "abcdefghijklmnop123",
            'headers = {"Authorization": "Bearer abcdefghijklmnop123"}',
        )

    def test_this_projects_own_env_vars(self):
        for line in (
            "WB_INGEST_TOKEN=supersecretvalue",
            "INGEST_TOKEN: anothersecret",
            "WHOOP_CLIENT_SECRET=abc123def456",
        ):
            out = self.redacted(line)
            self.assertIn("<redacted>", out, line)

    def test_the_watch_config_line(self):
        # The literal shape a user is most likely to paste from SessionModel.
        self.assert_gone(
            "my-real-token",
            'var ingestToken = "my-real-token"',
        )

    def test_tailscale_and_github_keys(self):
        self.assert_gone("tskey-auth-kABCDEF1234-9xyzQRS",
                         'authkey = "tskey-auth-kABCDEF1234-9xyzQRS"')
        self.assert_gone("ghp_abcdefghijklmnopqrstuvwxyz012345",
                         "token: ghp_abcdefghijklmnopqrstuvwxyz012345")
        self.assert_gone("sk-abcdefghijklmnopqrstuvwxyz",
                         "key = sk-abcdefghijklmnopqrstuvwxyz")

    def test_ordinary_data_is_untouched(self):
        # Over-redaction would quietly destroy the data being shared.
        payload = json.dumps({
            "mode": "round",
            "swings": [{"index": 1, "distance_yd": 251.5, "tempo_ratio": 2.9}],
            "note": "a token of appreciation for the access road",
        })
        self.assertEqual(self.redacted(payload), payload)

    def test_a_tailnet_address_is_not_a_secret(self):
        # Useful context for debugging, and not a credential.
        line = 'INGEST_URL = "http://100.101.102.103:8790"'
        self.assertEqual(self.redacted(line), line)


class TestFileHandling(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.src = Path(self.tmp.name) / "src"
        self.dst = Path(self.tmp.name) / "dst"
        self.src.mkdir()
        self.dst.mkdir()
        self.addCleanup(self.tmp.cleanup)

    def write(self, name, content):
        path = self.src / name
        if isinstance(content, bytes):
            path.write_bytes(content)
        else:
            path.write_text(content, encoding="utf-8")
        return path

    def test_refuses_a_credentials_file_outright(self):
        # Redacting tokens.json would leave a file conveying nothing, so it is
        # refused rather than emptied.
        path = self.write("tokens.json", '{"access_token": "x"}')
        self.assertIsNone(share.share_one(path, self.dst))
        self.assertFalse((self.dst / "tokens.json").exists())

    def test_refuses_ssh_keys_and_dotenv(self):
        for name in ("id_rsa", "id_ed25519", ".env"):
            self.assertIsNone(share.share_one(self.write(name, "secret"), self.dst))

    def test_refuses_an_oversized_file(self):
        path = self.write("huge.bin", b"\x01" * (share.MAX_BYTES + 1))
        self.assertIsNone(share.share_one(path, self.dst))

    def test_skips_a_missing_file_without_crashing(self):
        self.assertIsNone(share.share_one(self.src / "nope.json", self.dst))

    def test_skips_a_directory(self):
        (self.src / "adir").mkdir()
        self.assertIsNone(share.share_one(self.src / "adir", self.dst))

    def test_copies_and_redacts_a_text_file(self):
        path = self.write("cfg.py", 'TOKEN = "x"\nWB_INGEST_TOKEN=realsecret\n')
        result = share.share_one(path, self.dst)
        self.assertIsNotNone(result)
        written = (self.dst / "cfg.py").read_text(encoding="utf-8")
        self.assertNotIn("realsecret", written)
        self.assertTrue(result["redactions"])

    def test_binary_is_copied_byte_for_byte_and_flagged(self):
        blob = bytes(range(256))
        path = self.write("photo.bin", blob)
        result = share.share_one(path, self.dst)
        self.assertTrue(result["binary"])
        self.assertEqual((self.dst / "photo.bin").read_bytes(), blob)

    def test_invalid_utf8_does_not_crash_redaction(self):
        # A latin-1 CSV exported from a spreadsheet is a realistic input.
        path = self.write("weird.csv", "course,score\nSt Andr\xe9s,72\n".encode("latin-1"))
        self.assertIsNotNone(share.share_one(path, self.dst))


if __name__ == "__main__":
    unittest.main(verbosity=2)

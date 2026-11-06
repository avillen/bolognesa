import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class LocalWorktreeTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.bin = self.base / "bin"
        self.bin.mkdir()
        git = self.bin / "git"
        git.write_text('#!/bin/sh\nprintf "%s\\n" "$FAKE_ROOT"\n')
        git.chmod(0o755)
        mix = self.bin / "mix"
        mix.write_text('#!/bin/sh\nprintf "%s|%s|%s|%s\\n" "$*" "$PORT" "$BOLOGNESA_DB_NAME" "$BOLOGNESA_TEST_DB_NAME"\n')
        mix.chmod(0o755)

    def run_local(self, name, action):
        root = self.base / name
        target = root / "scripts/dev"
        target.mkdir(parents=True, exist_ok=True)
        shutil.copy(ROOT / "scripts/dev/local.sh", target / "local.sh")
        env = dict(os.environ, PATH=f'{self.bin}:{os.environ["PATH"]}', FAKE_ROOT=str(root))
        return subprocess.run(["sh", str(target / "local.sh"), action],
                              env=env, text=True, capture_output=True)

    def test_worktrees_have_stable_distinct_ports_and_databases(self):
        one = self.run_local("one", "info")
        two = self.run_local("two", "info")
        self.assertEqual(one.returncode, 0, one.stderr)
        self.assertEqual(two.returncode, 0, two.stderr)
        self.assertEqual(one.stdout, self.run_local("one", "info").stdout)
        self.assertNotEqual(one.stdout, two.stdout)

    def test_setup_receives_worktree_specific_configuration(self):
        result = self.run_local("one", "setup")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("setup|", result.stdout)
        self.assertIn("bolognesa_dev_", result.stdout)
        self.assertIn("bolognesa_test_", result.stdout)

    def test_unknown_command_fails(self):
        self.assertNotEqual(self.run_local("one", "unknown").returncode, 0)

    def test_mcp_requires_setup_instead_of_compiling_automatically(self):
        result = self.run_local("one", "mcp")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("setup", result.stderr)


if __name__ == "__main__":
    unittest.main()

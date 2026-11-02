import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class ComposeWorktreeTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.bin = self.base / "bin"
        self.bin.mkdir()
        self.write_executable(
            "git",
            '#!/bin/sh\ncase "$*" in *--show-toplevel*) printf "%s\\n" "$FAKE_ROOT";; '
            '*--git-common-dir*) printf "%s\\n" "$FAKE_COMMON";; '
            '*--git-path*) printf "%s\\n" "$FAKE_OWNER_FILE";; esac\n',
        )
        self.write_executable(
            "docker",
            '#!/bin/sh\ncase "$1" in ps) [ "${FAKE_COLLISION:-}" = 1 ] && echo container; exit 0;; '
            'inspect) echo /different/checkout; exit 0;; '
            'volume) [ -n "${FAKE_VOLUME:-}" ] || exit 1; '
            '[ "$#" -gt 3 ] && printf "%s\\n" "$FAKE_OWNER"; exit 0;; '
            'image) [ -n "${FAKE_IMAGE:-}" ] || exit 1; '
            '[ "$#" -gt 3 ] && printf "%s\\n" "$FAKE_IMAGE"; exit 0;; '
            'compose) printf "%s %s\\n" "$*" "$BOLOGNESA_DEV_PORT";; esac\n',
        )

    def write_executable(self, name, contents):
        path = self.bin / name
        path.write_text(contents)
        path.chmod(0o755)

    def run_compose(self, name, collision=False):
        root = self.base / name
        target = root / "scripts/dev"
        target.mkdir(parents=True, exist_ok=True)
        shutil.copy(ROOT / "scripts/dev/compose.sh", target / "compose.sh")
        env = dict(os.environ, PATH=f'{self.bin}:{os.environ["PATH"]}',
                   FAKE_ROOT=str(root), FAKE_COMMON=str(self.base / "common"))
        if collision:
            env["FAKE_COLLISION"] = "1"
        return subprocess.run(["sh", str(target / "compose.sh"), "config"],
                              env=env, text=True, capture_output=True)

    def test_each_checkout_has_stable_distinct_project_and_port(self):
        first = self.run_compose("one")
        second = self.run_compose("two")
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(first.stdout, self.run_compose("one").stdout)
        self.assertNotEqual(first.stdout.split()[2], second.stdout.split()[2])
        self.assertNotEqual(first.stdout.split()[-1], second.stdout.split()[-1])

    def test_rejects_project_owned_by_another_checkout(self):
        result = self.run_compose("one", collision=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("belongs to another checkout", result.stderr)

    def run_teardown(self, primary=False, owner=None, image=None, marker=False):
        root = self.base / "checkout"
        target = root / "scripts/dev"
        target.mkdir(parents=True, exist_ok=True)
        for script in ("compose.sh", "teardown.sh"):
            shutil.copy(ROOT / "scripts/dev" / script, target / script)
        main = root if primary else self.base / "primary"
        main.mkdir(exist_ok=True)
        env = dict(os.environ, PATH=f'{self.bin}:{os.environ["PATH"]}',
                   FAKE_ROOT=str(root), FAKE_COMMON=str(main / ".git"), TMPDIR=str(self.base),
                   FAKE_OWNER_FILE=str(self.base / "owner"))
        if marker:
            (self.base / "owner").write_text(str(root.resolve()) + "\n")
        if owner is not None:
            env.update(FAKE_VOLUME="1", FAKE_OWNER=owner)
        if image is not None:
            env["FAKE_IMAGE"] = image
        return subprocess.run(["sh", str(target / "teardown.sh")],
                              env=env, text=True, capture_output=True)

    def test_teardown_removes_only_linked_worktree_project(self):
        result = self.run_teardown()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("down --volumes --remove-orphans", result.stdout)

    def test_teardown_refuses_primary_checkout(self):
        result = self.run_teardown(primary=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("primary checkout", result.stderr)

    def test_teardown_refuses_another_worktrees_volume(self):
        result = self.run_teardown(owner="/different/checkout")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("another checkout's database", result.stderr)

    def test_teardown_refuses_unlabelled_volume_without_container(self):
        result = self.run_teardown(owner="<no value>")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Cannot establish ownership", result.stderr)

    def test_teardown_accepts_owned_volume_after_containers_are_removed(self):
        result = self.run_teardown(owner="<no value>", marker=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("down --volumes --remove-orphans", result.stdout)

    def test_teardown_refuses_an_unrelated_image(self):
        result = self.run_teardown(image="another-project")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("image not owned", result.stderr)


if __name__ == "__main__":
    unittest.main()

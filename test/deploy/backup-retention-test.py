import os
from pathlib import Path
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
SCRIPTS = REPO / 'deploy/compose/scripts'


class BackupRetentionTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.installation = self.root / "installation with ' quote"
        self.installation.mkdir()
        (self.installation / '.env').touch()
        (self.installation / 'compose.yaml').touch()
        self.backups = self.installation / "backup copies with ' quote"
        self.backups.mkdir()
        self.docker = self.root / 'docker'
        self.docker.write_text('''#!/bin/sh
set -eu
if [ "$1" = compose ]; then
 shift
 while [ "${1:-}" = -f ] || [ "${1:-}" = --env-file ] || [ "${1:-}" = --project-directory ]; do shift 2; done
 case "$*" in
  'ps -a -q db') echo existing-db ;;
  'exec -T db pg_restore --list') test "${FAIL_VALIDATE:-no}" != yes ;;
  'exec -T db sh -c'*) test "${FAIL_DUMP:-no}" != yes; echo synthetic-dump ;;
 esac
elif [ "$1" = inspect ]; then echo healthy
fi
''')
        self.docker.chmod(0o700)
        self.env = {**os.environ, 'DEPLOY_DIR': str(self.installation),
                    'DOCKER_BIN': str(self.docker), 'DEPLOY_BACKUP_KEEP': '3'}
        # Modification order deliberately differs from the timestamp in the name.
        self.old = []
        for number in range(5):
            suffix = '-10' if number % 2 == 0 else ''
            path = self.backups / f'pre-migration-2000010{5-number}-120000{suffix}.dump'
            path.write_text('old-valid-dump')
            Path(str(path)+'.image-ref').write_text('matching-image')
            os.utime(path, (number+1, number+1))
            self.old.append(path)
        self.unrelated = self.backups / 'manual-copy.dump'
        self.unrelated.write_text('manual')
        self.special = self.backups / 'pre-series-normalization-20000101-120000.dump'
        self.special.write_text('special recovery point')
        (self.backups / '.bolognesa-backup.incomplete').write_text('partial')
        (self.backups / 'pre-migration-unrecognized.dump').write_text('other')
        self.external = self.root / 'external.dump'
        self.external.write_text('external')
        self.symlink = self.backups / 'pre-migration-20990101-120000-99.dump'
        self.symlink.symlink_to(self.external)

    def backup(self, **env):
        return subprocess.run(['sh', str(SCRIPTS/'backup.sh'), str(self.backups)],
                              env={**self.env, **env}, capture_output=True, text=True)

    def managed(self):
        return {p for p in self.backups.glob('pre-migration-*.dump')
                if p.is_file() and not p.is_symlink() and p.name != 'pre-migration-unrecognized.dump'}

    def test_valid_backup_retains_three_latest_and_matching_image_references(self):
        result = self.backup(DEPLOY_BACKUP_KEEP='')
        self.assertEqual(result.returncode, 0, result.stderr)
        newest = Path(result.stdout.strip())
        self.assertEqual(self.managed(), {*self.old[-2:], newest})
        for removed in self.old[:-2]:
            self.assertFalse(Path(str(removed)+'.image-ref').exists())
        for retained in self.old[-2:]:
            self.assertTrue(Path(str(retained)+'.image-ref').exists())
        self.assertTrue(self.unrelated.exists())
        self.assertTrue(self.special.exists())
        self.assertTrue(self.symlink.is_symlink())
        self.assertEqual(self.external.read_text(), 'external')
        self.assertTrue((self.backups/'.bolognesa-backup.incomplete').exists())

    def test_custom_retention(self):
        result = self.backup(DEPLOY_BACKUP_KEEP='5')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.managed()), 5)
        self.assertFalse(self.old[0].exists())

    def test_failed_dump_or_validation_preserves_every_existing_copy(self):
        for failure in ['FAIL_DUMP', 'FAIL_VALIDATE']:
            with self.subTest(failure=failure):
                result = self.backup(**{failure: 'yes'})
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.managed(), set(self.old))
                self.assertTrue(all(Path(str(p)+'.image-ref').exists() for p in self.old))

    def test_invalid_limits_do_not_create_or_remove_backups(self):
        for value in ['0', '-1', 'three', '99999999999999999999999999']:
            with self.subTest(value=value):
                result = self.backup(DEPLOY_BACKUP_KEEP=value)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.managed(), set(self.old))

    def test_dry_run_and_protected_copy(self):
        command = ['sh', str(SCRIPTS/'prune-backups.sh'), '--dry-run',
                   str(self.backups), self.old[0].name]
        result = subprocess.run(command, env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.managed(), set(self.old))
        self.assertIn(self.old[1].name, result.stdout)
        self.assertIn(self.old[2].name, result.stdout)
        command.remove('--dry-run')
        result = subprocess.run(command, env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.managed(), {self.old[0], *self.old[-2:]})


if __name__ == '__main__':
    unittest.main()

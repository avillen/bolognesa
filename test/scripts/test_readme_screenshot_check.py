import importlib.util
import struct
import tempfile
import unittest
import zlib
from pathlib import Path

spec = importlib.util.spec_from_file_location('checker', Path('scripts/check_readme_screenshots.py'))
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)

def png(width, height, pixels):
    def chunk(kind, body):
        return struct.pack('>I', len(body)) + kind + body + struct.pack('>I', zlib.crc32(kind + body))
    scanlines = b''.join(b'\0' + bytes(pixels[y * width * 3:(y + 1) * width * 3]) for y in range(height))
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(scanlines)) + chunk(b'IEND', b'')

class ScreenshotCheckTest(unittest.TestCase):
    def test_minor_native_rasterization_is_allowed_only_for_music_player(self):
        with tempfile.TemporaryDirectory() as folder:
            expected, actual = Path(folder) / 'expected', Path(folder) / 'actual'
            expected.mkdir(); actual.mkdir()
            for name in ['music-player.png', 'home.png']:
                (expected / name).write_bytes(png(2, 2, [100] * 12))
                (actual / name).write_bytes(png(2, 2, [101] + [100] * 11))
            self.assertEqual(checker.differences(expected, actual), ['home.png'])

    def test_music_list_allows_only_tiny_navigation_antialiasing(self):
        with tempfile.TemporaryDirectory() as folder:
            expected, actual = Path(folder) / 'expected', Path(folder) / 'actual'
            expected.mkdir(); actual.mkdir()
            (expected / 'music.png').write_bytes(png(8, 8, [100] * 192))
            (actual / 'music.png').write_bytes(png(8, 8, [101] + [100] * 191))
            self.assertEqual(checker.differences(expected, actual), [])
            (actual / 'music.png').write_bytes(png(8, 8, [102] + [100] * 191))
            self.assertEqual(checker.differences(expected, actual), ['music.png'])
            (actual / 'music.png').write_bytes(png(8, 8, [101] * 192))
            self.assertEqual(checker.differences(expected, actual), ['music.png'])

    def test_visual_changes_and_size_changes_are_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            first, second = Path(folder) / 'first.png', Path(folder) / 'second.png'
            first.write_bytes(png(16, 16, [100] * 768))
            second.write_bytes(png(16, 16, [200] + [100] * 767))
            self.assertFalse(checker.native_audio_matches(first, second))
            second.write_bytes(png(16, 16, [101] * 768))
            self.assertFalse(checker.native_audio_matches(first, second))
            second.write_bytes(png(2, 2, [100] * 12))
            self.assertFalse(checker.native_audio_matches(first, second))

    def test_missing_capture_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            expected, actual = Path(folder) / 'expected', Path(folder) / 'actual'
            expected.mkdir(); actual.mkdir()
            (expected / 'music-player.png').write_bytes(png(2, 2, [100] * 12))
            self.assertEqual(checker.differences(expected, actual), ['music-player.png'])

if __name__ == '__main__':
    unittest.main()

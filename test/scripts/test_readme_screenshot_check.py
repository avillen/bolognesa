import importlib.util
import struct
import tempfile
import unittest
import zlib
from pathlib import Path

spec = importlib.util.spec_from_file_location('checker', Path('scripts/screenshots/compare-readme-screenshots.py'))
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

    def test_catalog_surfaces_allow_only_tiny_antialiasing(self):
        for name in ['music.png', 'series-detail.png', 'season.png', 'about.png']:
            with self.subTest(capture=name), tempfile.TemporaryDirectory() as folder:
                expected, actual = Path(folder) / 'expected', Path(folder) / 'actual'
                expected.mkdir(); actual.mkdir()
                (expected / name).write_bytes(png(16, 16, [100] * 768))
                (actual / name).write_bytes(png(16, 16, [101] + [100] * 767))
                self.assertEqual(checker.differences(expected, actual), [])
                (actual / name).write_bytes(png(16, 16, [102] + [100] * 767))
                self.assertEqual(checker.differences(expected, actual), [name])
                (actual / name).write_bytes(png(16, 16, [101] * 768))
                self.assertEqual(checker.differences(expected, actual), [name])

    def test_episode_and_mobile_movie_allow_bounded_antialiasing(self):
        for name in ['episode.png', 'movie-mobile.png']:
            with self.subTest(capture=name), tempfile.TemporaryDirectory() as folder:
                expected, actual = Path(folder) / 'expected', Path(folder) / 'actual'
                expected.mkdir(); actual.mkdir()
                (expected / name).write_bytes(png(16, 16, [100] * 768))
                (actual / name).write_bytes(png(16, 16, [102] + [100] * 767))
                self.assertEqual(checker.differences(expected, actual), [])
                (actual / name).write_bytes(png(16, 16, [103] + [100] * 767))
                self.assertEqual(checker.differences(expected, actual), [name])
                (actual / name).write_bytes(png(16, 16, [101] * 768))
                self.assertEqual(checker.differences(expected, actual), [name])

    def test_video_player_corners_allow_one_small_shadow_raster_difference(self):
        with tempfile.TemporaryDirectory() as folder:
            expected, actual = Path(folder) / 'expected', Path(folder) / 'actual'
            expected.mkdir(); actual.mkdir()
            for name in ['movie.png', 'episode.png', 'player.png']:
                (expected / name).write_bytes(png(8, 8, [100] * 192))
                changed = [100] * 192
                changed[0] = 117
                (actual / name).write_bytes(png(8, 8, changed))
                self.assertEqual(checker.differences(expected, actual), [])

                changed[3] = 117
                (actual / name).write_bytes(png(8, 8, changed))
                self.assertEqual(checker.differences(expected, actual), [name])

                changed[3] = 100
                changed[0] = 121
                (actual / name).write_bytes(png(8, 8, changed))
                self.assertEqual(checker.differences(expected, actual), [name])
                (actual / name).write_bytes((expected / name).read_bytes())

    def test_mobile_corners_have_small_capture_specific_budgets(self):
        for name, budget, delta in [('series.png', 8, 1), ('series-mobile.png', 8, 1), ('series-detail-mobile.png', 64, 2), ('episode-mobile.png', 8, 1), ('music-mobile.png', 128, 2)]:
            with self.subTest(capture=name), tempfile.TemporaryDirectory() as folder:
                expected, actual = Path(folder) / 'expected', Path(folder) / 'actual'
                expected.mkdir(); actual.mkdir()
                (expected / name).write_bytes(png(16, 16, [100] * 768))
                changed = [100] * 768
                for index in range(budget):
                    changed[index * 3] += delta
                (actual / name).write_bytes(png(16, 16, changed))
                self.assertEqual(checker.differences(expected, actual), [])
                changed[budget * 3] += delta
                (actual / name).write_bytes(png(16, 16, changed))
                self.assertEqual(checker.differences(expected, actual), [name])
                (actual / name).write_bytes(png(16, 16, [101 + delta] + [100] * 767))
                self.assertEqual(checker.differences(expected, actual), [name])

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

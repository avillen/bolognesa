import importlib.util
import struct
import tempfile
import unittest
import zlib
from pathlib import Path

spec = importlib.util.spec_from_file_location('checker', Path('scripts/screenshots/compare-readme-screenshots.py'))
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)

WIDTH = HEIGHT = 100  # 10,000 pixels: faint budget is 10 pixels.


def png(pixels, width=WIDTH, height=HEIGHT, level=9):
    def chunk(kind, body):
        return struct.pack('>I', len(body)) + kind + body + struct.pack('>I', zlib.crc32(kind + body))
    scanlines = b''.join(b'\0' + bytes(pixels[y * width * 3:(y + 1) * width * 3]) for y in range(height))
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(scanlines, level)) + chunk(b'IEND', b''))


def changed(count, delta):
    pixels = [100] * (WIDTH * HEIGHT * 3)
    for index in range(count):
        pixels[index * 3] += delta
    return pixels


class ScreenshotCheckTest(unittest.TestCase):
    def check(self, actual_bytes, name='any.png'):
        with tempfile.TemporaryDirectory() as folder:
            expected, actual = Path(folder) / 'expected', Path(folder) / 'actual'
            expected.mkdir(); actual.mkdir()
            (expected / name).write_bytes(png(changed(0, 0)))
            if actual_bytes is not None:
                (actual / name).write_bytes(actual_bytes)
            return checker.differences(expected, actual)

    def test_same_pixels_with_different_encoding_match(self):
        self.assertEqual(self.check(png(changed(0, 0), level=1)), [])

    def test_faint_antialiasing_is_bounded_by_ratio(self):
        self.assertEqual(self.check(png(changed(10, 2))), [])
        self.assertEqual(self.check(png(changed(11, 2))), ['any.png'])

    def test_strong_differences_are_limited_to_isolated_pixels(self):
        self.assertEqual(self.check(png(changed(16, 60))), [])
        self.assertEqual(self.check(png(changed(17, 60))), ['any.png'])

    def test_size_changes_and_invalid_files_are_rejected(self):
        self.assertEqual(self.check(png([100] * 12, 2, 2)), ['any.png'])
        self.assertEqual(self.check(b'not a png'), ['any.png'])

    def test_missing_capture_is_rejected(self):
        self.assertEqual(self.check(None), ['any.png'])


if __name__ == '__main__':
    unittest.main()

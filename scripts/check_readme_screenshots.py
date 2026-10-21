"""Compare captures, allowing bounded audio-control and icon rasterization differences."""
import struct
import sys
import zlib
from pathlib import Path

MAX_NATIVE_PIXELS = 128
MAX_CHANNEL_DELTA = 64
RASTER_LIMITS = {
    "music-player.png": (MAX_NATIVE_PIXELS, MAX_CHANNEL_DELTA, 0, 0, 0),
    "music.png": (16, 1, 0, 0, 0),
    "series-detail.png": (16, 1, 0, 0, 0),
    "season.png": (16, 1, 0, 0, 0),
    "about.png": (16, 1, 0, 0, 0),
    # Observed rounded-corner rasterization on the compact mobile series screens.
    "series.png": (8, 1, 0, 0, 0),
    "series-mobile.png": (8, 1, 0, 0, 0),
    "series-detail-mobile.png": (64, 2, 0, 0, 0),
    "episode-mobile.png": (8, 1, 0, 0, 0),
    "movie-mobile.png": (128, 2, 0, 0, 0),
    "episode.png": (32, 2, 1, 16, 20),
    "movie.png": (0, 0, 1, 16, 20),
    "player.png": (0, 0, 1, 16, 20),
}


def _png_rows(path):
    data = path.read_bytes()
    if not data.startswith(b'\x89PNG\r\n\x1a\n'):
        raise ValueError('Not a PNG capture')
    offset, compressed = 8, bytearray()
    while offset < len(data):
        size = struct.unpack('>I', data[offset:offset + 4])[0]
        kind = data[offset + 4:offset + 8]
        body = data[offset + 8:offset + 8 + size]
        offset += size + 12
        if kind == b'IHDR':
            width, height, depth, color, _, _, interlace = struct.unpack('>IIBBBBB', body)
        elif kind == b'IDAT':
            compressed.extend(body)
    if depth != 8 or interlace != 0 or width * height > 16_000_000:
        raise ValueError('Unsupported capture format')
    channels = {2: 3, 6: 4}[color]
    stride = width * channels
    packed = zlib.decompress(compressed)
    if len(packed) != height * (stride + 1):
        raise ValueError('Invalid capture size')
    previous, rows, offset = bytearray(stride), [], 0
    for _ in range(height):
        filter_kind = packed[offset]
        row = bytearray(packed[offset + 1:offset + 1 + stride])
        offset += stride + 1
        for index in range(stride):
            left = row[index - channels] if index >= channels else 0
            above = previous[index]
            diagonal = previous[index - channels] if index >= channels else 0
            if filter_kind == 0:
                prediction = 0
            elif filter_kind == 1:
                prediction = left
            elif filter_kind == 2:
                prediction = above
            elif filter_kind == 3:
                prediction = (left + above) // 2
            elif filter_kind == 4:
                value = left + above - diagonal
                distances = [abs(value - left), abs(value - above), abs(value - diagonal)]
                prediction = (left, above, diagonal)[distances.index(min(distances))]
            else:
                raise ValueError('Unsupported PNG filter')
            row[index] = (row[index] + prediction) % 256
        rows.append(row)
        previous = row
    return width, height, channels, rows


def native_audio_matches(expected, actual):
    """Allow small native rasterization differences; reject larger visual changes."""
    return _raster_matches(expected, actual, MAX_NATIVE_PIXELS, MAX_CHANNEL_DELTA)


def _raster_matches(
    expected,
    actual,
    max_pixels,
    max_channel_delta,
    outlier_pixels=0,
    min_outlier_channel_delta=0,
    max_outlier_channel_delta=0,
):
    try:
        first, second = _png_rows(expected), _png_rows(actual)
        if first[:3] != second[:3]:
            return False
        width, _, channels, rows = first
        changed, outliers = 0, 0
        for left, right in zip(rows, second[3]):
            for index in range(0, width * channels, channels):
                a, b = left[index:index + channels], right[index:index + channels]
                if a == b:
                    continue
                channel_delta = max(abs(x - y) for x, y in zip(a, b))
                if channel_delta <= max_channel_delta:
                    changed += 1
                    if changed > max_pixels:
                        return False
                elif min_outlier_channel_delta <= channel_delta <= max_outlier_channel_delta:
                    outliers += 1
                    if outliers > outlier_pixels:
                        return False
                else:
                    return False
        return True
    except (ValueError, KeyError, struct.error, zlib.error, UnboundLocalError):
        return False


def differences(expected, actual):
    first = {p.relative_to(expected).as_posix(): p for p in expected.rglob('*') if p.is_file()}
    second = {p.relative_to(actual).as_posix(): p for p in actual.rglob('*') if p.is_file()}
    changed = []
    for name in sorted(first.keys() | second.keys()):
        if name not in first or name not in second:
            changed.append(name)
        elif first[name].read_bytes() != second[name].read_bytes():
            limits = RASTER_LIMITS.get(name)
            if limits is None or not _raster_matches(first[name], second[name], *limits):
                changed.append(name)
    return changed


if __name__ == '__main__':
    changed = differences(Path(sys.argv[1]), Path(sys.argv[2]))
    for filename in changed:
        print('Capture differs: ' + filename)
    sys.exit(bool(changed))

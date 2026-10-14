#!/usr/bin/env python3
"""Generate deterministic, local video/subtitle fixtures without downloads."""
import argparse
import struct
from pathlib import Path


def chunk(name, payload):
    return name + struct.pack('<I', len(payload)) + payload + (b'\0' if len(payload) & 1 else b'')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('directory', type=Path)
    args = parser.parse_args()
    args.directory.mkdir(parents=True, exist_ok=True)
    width, height, fps, count = 160, 90, 5, 50
    size = width * height * 3
    header = struct.pack('<14I', 1000000 // fps, size * fps, 0, 0x10,
                         count, 0, 1, size, width, height, 0, 0, 0, 0)
    stream = struct.pack('<4s4sIHH8I4h', b'vids', b'DIB ', 0, 0, 0,
                         0, 1, fps, 0, count, size, 0xffffffff, 0,
                         0, 0, width, height)
    bitmap = struct.pack('<IiiHHIIiiII', 40, width, height, 1, 24,
                         0, size, 0, 0, 0, 0)
    headers = chunk(b'LIST', b'hdrl' + chunk(b'avih', header) +
                    chunk(b'LIST', b'strl' + chunk(b'strh', stream) + chunk(b'strf', bitmap)))
    frames, index, position = [], [], 4
    for number in range(count):
        # Bottom-up BGR rows. Motion is visible and every frame is a keyframe.
        frame = bytes(component for y in range(height) for x in range(width)
                      for component in ((x * 3 + number * 9) % 256,
                                        (y * 3 + number * 5) % 256,
                                        (x + y + number * 13) % 256))
        encoded = chunk(b'00db', frame)
        frames.append(encoded)
        index.append(struct.pack('<4sIII', b'00db', 0x10, position, size))
        position += len(encoded)
    body = b'AVI ' + headers + chunk(b'LIST', b'movi' + b''.join(frames)) + chunk(b'idx1', b''.join(index))
    (args.directory / 'video-fixture.avi').write_bytes(chunk(b'RIFF', body))
    (args.directory / 'video-fixture.srt').write_text(
        '1\n00:00:00,500 --> 00:00:04,000\nNative VLC subtitle test\n\n'
        '2\n00:00:04,500 --> 00:00:09,000\nSecond subtitle cue\n', encoding='utf-8')
    print(f'Generated {count} RGB frames, {fps} fps, {width}x{height}, and SRT subtitles')


if __name__ == '__main__':
    main()

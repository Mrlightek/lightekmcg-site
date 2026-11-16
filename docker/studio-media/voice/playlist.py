#!/usr/bin/env python3
"""Load the private CPU voice once per reply; publish each segment atomically."""
import argparse
import json
import math
from pathlib import Path
import subprocess
import sys
from array import array
from synthesize import load_engine


def validate(value):
    if not isinstance(value, dict) or set(value) != {'parts', 'voice', 'speed'}:
        raise ValueError('Use playlist parts and installed voice settings')
    parts, voice, speed = value['parts'], value['voice'], value['speed']
    if not isinstance(parts, list) or not 1 <= len(parts) <= 12 or any(
            not isinstance(text, str) or not 1 <= len(text) <= 120 or '\0' in text for text in parts):
        raise ValueError('Use up to twelve bounded speech parts')
    if voice not in ('nevaeh-natural', 'nevaeh-warm') or type(speed) is not int or not 100 <= speed <= 220:
        raise ValueError('Use installed voice settings')
    return parts, voice, speed


def render(value, directory, engine_factory=load_engine):
    parts, voice, speed = validate(value)
    speak = engine_factory()  # One model initialization, shared by every part.
    directory = Path(directory)
    for index, text in enumerate(parts):
        wav, stream = directory / f'part-{index}.wav', directory / f'part-{index}.ts'
        speak(text, str(wav), voice, speed)
        subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', str(wav), '-ac', '1', '-ar', '24000',
                        '-c:a', 'aac', '-b:a', '64k', '-muxdelay', '0', '-muxpreload', '0',
                        '-avoid_negative_ts', 'make_zero', '-f', 'mpegts', str(stream)], check=True, timeout=30)
        probe = subprocess.check_output(['ffprobe', '-v', 'error', '-show_entries', 'format=duration',
                                         '-of', 'json', str(stream)], timeout=15)
        duration = float(json.loads(probe)['format']['duration'])
        if not math.isfinite(duration) or not .05 <= duration <= 20:
            raise ValueError('Speech segment exceeds its playback limit')
        raw = subprocess.check_output(['ffmpeg', '-v', 'error', '-i', str(stream),
                                       '-vn', '-ac', '1', '-ar', '8000', '-f', 's16le', '-'], timeout=30)
        rate = 8000
        samples = array('h', raw)
        if sys.byteorder != 'little':
            samples.byteswap()
        hop = max(1, round(rate * .04))
        energy = [math.sqrt(sum(v*v for v in samples[i:i+hop]) / len(samples[i:i+hop])) / 32768
                  for i in range(0, len(samples), hop)]
        if not energy:
            raise ValueError('Speech segment has no audio samples')
        peak = max(max(energy), .02)
        frames = [{'time': i * .04, 'value': 0 if v < .007 else round(min(v / peak, 1), 4)}
                  for i, v in enumerate(energy)]
        target = directory / f'part-{index}.json'
        temporary = target.with_suffix('.json.tmp')
        temporary.write_text(json.dumps({'duration': duration, 'mouth_frames': frames}), encoding='utf-8')
        temporary.replace(target)  # Ruby can publish this item while the next is synthesizing.


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--directory', required=True)
    args = parser.parse_args()
    raw = sys.stdin.buffer.read(20001)
    if len(raw) > 20000:
        parser.error('Speech playlist is too large')
    render(json.loads(raw), args.directory)


if __name__ == '__main__':
    main()

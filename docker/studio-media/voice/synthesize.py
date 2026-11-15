#!/usr/bin/env python3
"""Offline CPU voice synthesis; model/voice files are installed at image build."""
import argparse
import os
import re
from pathlib import Path
import sys
import wave


def spoken_phonemes(text, tokenizer):
    """Keep the written name intact while fixing its spoken pronunciation."""
    pieces = re.split(r"(\bnevaeh(?:['’]s)?\b)", text, flags=re.IGNORECASE)
    sounds = []
    for piece in pieces:
        if not piece.strip():
            continue
        if re.fullmatch(r"nevaeh(?:['’]s)?", piece, flags=re.IGNORECASE):
            sounds.append('nəvˈeɪə' + ('z' if piece.lower().endswith(('\'s', '’s')) else ''))
        else:
            sounds.append(tokenizer.phonemize(piece, 'en-us'))
    return ' '.join(sounds)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', required=True)
    parser.add_argument('--voice', choices=['nevaeh-natural', 'nevaeh-warm'], default='nevaeh-natural')
    parser.add_argument('--speed', type=int, default=170)
    parser.add_argument('--threads', type=int, default=1)
    args = parser.parse_args()
    text = sys.stdin.buffer.read(4097).decode('utf-8')
    if not 1 <= len(text) <= 1000 or '\0' in text or not 100 <= args.speed <= 220 or not 1 <= args.threads <= 4:
        parser.error('Use 1–1000 characters, speed 100–220 and 1–4 CPU threads')
    os.environ['OPENBLAS_NUM_THREADS'] = str(args.threads)
    os.environ['OMP_NUM_THREADS'] = str(args.threads)
    import numpy as np
    import onnxruntime as ort
    from kokoro_onnx import Kokoro
    directory = Path(os.environ.get('LIGHTEK_VOICE_MODELS', '/opt/lightek-voice/models'))
    options = ort.SessionOptions()
    options.intra_op_num_threads = args.threads
    options.inter_op_num_threads = 1
    options.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL
    session = ort.InferenceSession(str(directory / 'model.onnx'), sess_options=options, providers=['CPUExecutionProvider'])
    engine = Kokoro.from_session(session, str(directory / 'voices.bin'))
    # Stable, original preset blend. No uploaded person's voice is cloned.
    style = (0.7 * engine.get_voice_style('af_heart') + 0.3 * engine.get_voice_style('af_bella')) if args.voice == 'nevaeh-natural' else engine.get_voice_style('af_bella')
    phonemes = spoken_phonemes(text, engine.tokenizer)
    audio, rate = engine.create(phonemes, voice=style, speed=args.speed / 170.0, lang='en-us', is_phonemes=True)
    audio = np.asarray(audio).reshape(-1)
    if not np.isfinite(audio).all() or not 0.05 <= audio.size / rate <= 120 or np.max(np.abs(audio), initial=0) < 0.0001:
        raise ValueError('Natural voice produced invalid or silent audio')
    pcm = (np.clip(audio, -1, 1) * 32767).astype('<i2')
    with wave.open(args.output, 'wb') as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(rate)
        output.writeframes(pcm.tobytes())


if __name__ == '__main__':
    main()

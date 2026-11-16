import importlib.util
import json
import math
from pathlib import Path
import struct
import sys
import tempfile
import unittest
import wave

VOICE = Path(__file__).resolve().parents[2] / 'docker/studio-media/voice'
sys.path.insert(0, str(VOICE))
spec = importlib.util.spec_from_file_location('voice_playlist', VOICE / 'playlist.py')
playlist = importlib.util.module_from_spec(spec)
spec.loader.exec_module(playlist)


class VoicePlaylistTest(unittest.TestCase):
    def test_single_engine_publishes_real_playable_segments_incrementally(self):
        with tempfile.TemporaryDirectory() as root:
            loads, calls = [], []
            def factory():
                loads.append(True)
                def speak(text, path, voice, speed):
                    if calls:
                        self.assertTrue((Path(root) / f'part-{len(calls)-1}.json').exists())
                    calls.append(text)
                    with wave.open(path, 'wb') as output:
                        output.setnchannels(1)
                        output.setsampwidth(2)
                        output.setframerate(24000)
                        output.writeframes(b''.join(struct.pack('<h', round(8000*math.sin(i*.08))) for i in range(24000)))
                return speak
            playlist.render({'parts': ['First sentence.', 'Second sentence.', 'Third sentence.'],
                             'voice': 'nevaeh-natural', 'speed': 170}, root, factory)
            self.assertEqual(1, len(loads))
            self.assertEqual(3, len(calls))
            for index in range(3):
                meta = json.loads((Path(root) / f'part-{index}.json').read_text())
                self.assertGreater(meta['duration'], .9)
                self.assertLess(meta['duration'], 1.2)
                self.assertTrue(all(0 <= f['value'] <= 1 for f in meta['mouth_frames']))
                self.assertGreater((Path(root) / f'part-{index}.ts').stat().st_size, 1000)
                self.assertFalse((Path(root) / f'part-{index}.json.tmp').exists())

    def test_rejects_invalid_inputs_before_loading_model(self):
        for value in ({'parts': ['Hi'], 'voice': 'foreign', 'speed': 170},
                      {'parts': ['x'*121], 'voice': 'nevaeh-natural', 'speed': 170},
                      {'parts': ['Hi'], 'voice': 'nevaeh-natural', 'speed': True}):
            with self.assertRaises(ValueError):
                playlist.render(value, '/unused', lambda: self.fail('Loaded model for invalid inputs'))


if __name__ == '__main__':
    unittest.main()

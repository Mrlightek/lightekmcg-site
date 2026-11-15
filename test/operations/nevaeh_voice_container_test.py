"""Real Docker/ONNX regression for phonemizer's temporary shared library."""
import array
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import wave

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(os.environ.get('NEVAEH_TEST_VOICE_CONTAINER') == '1' and shutil.which('docker'),
                     'requires the built CPU voice image and NEVAEH_TEST_VOICE_CONTAINER=1')
class NevaehVoiceContainerTest(unittest.TestCase):
    def command(self, directory, libraries):
        # Use the production Ruby command builder, not a second set of flags.
        ruby = '''require "json"; require "securerandom"
load "app/services/studio/media_process.rb"
Studio::MediaProcess.define_singleton_method(:cpu_limit) { "1" }
puts JSON.generate(Studio::MediaProcess.container(
  ["/opt/lightek-voice/venv/bin/python", "/opt/lightek-voice/synthesize.py", "--output", "/work/reply.wav"],
  root: ARGV[0], image: "lightek/nevaeh-voice:test", stdin: true, voice_libraries: ARGV[1]=="true"))
'''
        output = subprocess.check_output([os.environ.get('LIGHTEK_TEST_RUBY', 'ruby'), '-e', ruby, str(directory), str(libraries).lower()], cwd=ROOT, text=True)
        return json.loads(output)

    def test_default_noexec_temp_mount_reproduces_library_mapping_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run(self.command(directory, False), input='Nevaeh voice is ready.', text=True, capture_output=True, timeout=180)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('failed to map segment from shared object', result.stderr)
            self.assertFalse((Path(directory)/'reply.wav').exists())

    def test_voice_library_mount_generates_real_audible_wav(self):
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run(self.command(directory, True), input='Nevaeh voice is ready.', text=True, capture_output=True, timeout=180)
            self.assertEqual(result.returncode, 0, result.stderr)
            with wave.open(str(Path(directory)/'reply.wav')) as audio:
                self.assertEqual(audio.getnchannels(), 1)
                self.assertEqual(audio.getsampwidth(), 2)
                self.assertGreater(audio.getnframes()/audio.getframerate(), 0.5)
                samples = array.array('h', audio.readframes(audio.getnframes()))
                self.assertGreater(max(map(abs, samples)), 50)


if __name__ == '__main__':
    unittest.main()

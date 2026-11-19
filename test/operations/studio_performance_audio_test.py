"""Exercise the two supported Blender audio APIs without a GPU or UI."""
import importlib.util
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[2]
class PerformanceAudioTest(unittest.TestCase):
    def load(self, modern):
        class Mixdown:
            def get_rna_type(inner):
                return SimpleNamespace(properties={'mixrate','channels'} if modern else set())
            def __call__(inner, **options):
                self.options=options
                Path(options['filepath']).write_bytes(b'packed scene audio')
        scene=SimpleNamespace(render=SimpleNamespace(fps=12,fps_base=1,ffmpeg=SimpleNamespace()),frame_start=1,frame_end=48)
        bpy=SimpleNamespace(context=SimpleNamespace(scene=scene),ops=SimpleNamespace(sound=SimpleNamespace(mixdown=Mixdown())))
        spec=importlib.util.spec_from_file_location('studio_performance_audio',ROOT/'blender/performance.py')
        module=importlib.util.module_from_spec(spec)
        with patch.dict(sys.modules,{'bpy':bpy,'mathutils':SimpleNamespace(Euler=None),'visemes':SimpleNamespace(),'motion':SimpleNamespace()}):
            spec.loader.exec_module(module)
        return module,scene
    def verify_mix(self,modern):
        module,scene=self.load(modern)
        with tempfile.TemporaryDirectory() as root:
            path=Path(root)/'movie.mp4';path.write_bytes(b'picture')
            def encode(args,**kwargs):
                Path(args[-1]).write_bytes(b'picture and mixed sound')
                return SimpleNamespace(returncode=0)
            with patch.object(module.subprocess,'run',side_effect=encode):
                module.mux_movie(str(path),force=True)
            self.assertEqual(b'picture and mixed sound',path.read_bytes())
            self.assertFalse((Path(root)/'movie-mix.wav').exists())
        if modern:
            self.assertEqual(48000,self.options['mixrate']);self.assertEqual('STEREO',self.options['channels'])
        else:
            self.assertNotIn('mixrate',self.options);self.assertNotIn('channels',self.options)
            self.assertEqual(48000,scene.render.ffmpeg.audio_mixrate);self.assertEqual('STEREO',scene.render.ffmpeg.audio_channels)
    def test_ubuntu_blender_mixdown_uses_scene_audio_settings(self): self.verify_mix(False)
    def test_newer_blender_mixdown_uses_operator_audio_arguments(self): self.verify_mix(True)
    def test_listener_reactions_cannot_animate_over_own_speech(self):
        module,_=self.load(True)
        with self.assertRaisesRegex(RuntimeError,'overlap'):
            module.apply_listener_reactions({}, {'character_profile':{'bindings':{}},'performance':{'start':1,'duration':1},'listener_reactions':[{'kind':'listen','start':1.5,'duration':.5}]})
if __name__=='__main__': unittest.main()

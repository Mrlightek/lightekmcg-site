import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('voice', ROOT/'docker/studio-media/voice/synthesize.py')
voice = importlib.util.module_from_spec(spec)
spec.loader.exec_module(voice)


class PronunciationTest(unittest.TestCase):
    def test_name_and_possessives_get_exact_phonemes_without_changing_other_words(self):
        class Tokenizer:
            def phonemize(self, text, lang):
                return '<'+text.strip()+'>'
        tokenizer = Tokenizer()
        for name in ['Nevaeh', 'NEVAEH', 'nevaeh']:
            self.assertEqual(voice.spoken_phonemes('Hello '+name+'.', tokenizer), '<Hello> nəvˈeɪə <.>')
        for name in ["Nevaeh's", 'Nevaeh’s']:
            self.assertEqual(voice.spoken_phonemes(name+' workspace', tokenizer), 'nəvˈeɪəz <workspace>')
        self.assertEqual(voice.spoken_phonemes('NevaehSpeech is a model.', tokenizer), '<NevaehSpeech is a model.>')


if __name__ == '__main__':
    unittest.main()

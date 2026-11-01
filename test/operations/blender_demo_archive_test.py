import importlib.util
from pathlib import Path
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location('extract_demo', Path(__file__).resolve().parents[2] / 'blender/extract_demo.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class DemoArchiveTest(unittest.TestCase):
    def test_nested_blender_files_and_texture_paths_are_retained(self):
        with tempfile.TemporaryDirectory() as root:
            archive = Path(root) / 'demo.zip'
            with zipfile.ZipFile(archive, 'w') as handle:
                handle.writestr('scenes/demo.blend', b'BLENDER')
                handle.writestr('textures/wood.png', b'PNG')
            files = module.extract(archive, Path(root) / 'out')
            self.assertEqual(1, len(files))
            self.assertTrue(Path(files[0]).exists())
            self.assertEqual(b'PNG', (Path(root) / 'out/textures/wood.png').read_bytes())

    def test_parent_traversal_is_rejected(self):
        with tempfile.TemporaryDirectory() as root:
            archive = Path(root) / 'demo.zip'
            with zipfile.ZipFile(archive, 'w') as handle:
                handle.writestr('../outside.blend', b'BLENDER')
            with self.assertRaises(ValueError):
                module.extract(archive, Path(root) / 'out')
            self.assertFalse((Path(root) / 'outside.blend').exists())


if __name__ == '__main__':
    unittest.main()

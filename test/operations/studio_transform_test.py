"""Verify the production manifest transform without requiring a Blender process."""
import ast
import math
from pathlib import Path
from types import SimpleNamespace
import unittest

source = Path(__file__).resolve().parents[2] / 'blender/runner.py'
tree = ast.parse(source.read_text())
functions = [node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name in ('vector3', 'apply_transform')]
namespace = {'math': math}
exec(compile(ast.Module(body=functions, type_ignores=[]), str(source), 'exec'), namespace)

class StudioTransformTest(unittest.TestCase):
    def test_editor_degrees_match_blender_radians_and_preserve_vectors(self):
        obj = SimpleNamespace(location=None, rotation_euler=None, scale=None)
        namespace['apply_transform'](obj, {'location': [1, 2, 3], 'rotation': [90, -45, 180], 'scale': [2, 3, 4]})
        self.assertEqual([1., 2., 3.], obj.location)
        self.assertEqual([2., 3., 4.], obj.scale)
        for actual, expected in zip(obj.rotation_euler, [math.pi / 2, -math.pi / 4, math.pi]):
            self.assertAlmostEqual(expected, actual)

    def test_default_transform_is_identity(self):
        obj = SimpleNamespace(location=None, rotation_euler=None, scale=None)
        namespace['apply_transform'](obj, {})
        self.assertEqual([0., 0., 0.], obj.location)
        self.assertEqual([0., 0., 0.], obj.rotation_euler)
        self.assertEqual([1., 1., 1.], obj.scale)

if __name__ == '__main__':
    unittest.main()

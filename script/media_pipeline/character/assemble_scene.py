"""Blender entry point for a character shot with a Mixamo animation."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))

from bpy_render import main

if __name__ == "__main__":
    main()

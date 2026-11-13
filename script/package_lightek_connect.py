#!/usr/bin/env python3
"""Build the WordPress ZIP with the same locally bundled UI served to Shopify."""
from pathlib import Path
import shutil
import zipfile
root = Path(__file__).resolve().parents[1]
plugin = root / "integrations/wordpress/lightek-connect"
assets = plugin / "assets"
assets.mkdir(exist_ok=True)
for name in ("workspace.js", "workspace.css"):
    shutil.copyfile(root / "public/lightek-connect" / name, assets / name)
output = root / "tmp/lightek-connect-wordpress.zip"
output.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(plugin.rglob("*")):
        if path.is_file():
            archive.write(path, path.relative_to(plugin.parent))
print(output)

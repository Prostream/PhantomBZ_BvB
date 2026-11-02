"""Source-based developer package. No game resources, logs, saves, runtime or binary dependencies."""
from pathlib import Path
import zipfile

root = Path(__file__).resolve().parents[1]
output = root / 'dist/PhantomBZ_BvB-0.1.0-dev.zip'
output.parent.mkdir(exist_ok=True)
files = [root / name for name in ('README.md', 'LICENSE', 'UPSTREAM.md', 'Install-BvB.ps1', 'Start-BvB.ps1')]
files += list((root / 'Mods/PhantomGladiator/Scripts').glob('*.lua'))
files += list((root / 'panel').glob('*.py'))
files += [p for p in (root / 'panel/static').rglob('*') if p.is_file() and p.suffix in {'.js','.html','.css','.json','.svg'}]
files += [root/'panel/unit_validation.json', root/'docs/BVB_REQUIREMENTS.md', root/'docs/BVB_DEVELOPMENT.md']
with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
    for path in files:
        archive.write(path, 'PhantomBZ_BvB/' + path.relative_to(root).as_posix())
print(output)

#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output="${1:-dist}"
python3 - "$output" <<'PY'
import hashlib, json, pathlib, subprocess, sys
output = pathlib.Path(sys.argv[1]).resolve()
info = json.loads((output / 'build-info.json').read_text())
if info['signing'] == 'none':
    raise SystemExit('Refusing to package an unsigned build; use adhoc or developer-id.')
app = output / 'MenuPocket.app'
subprocess.run(['codesign', '--verify', '--strict', str(app)], check=True)
arch = 'universal' if len(info['architectures']) > 1 else info['architectures'][0]
name = f"MenuPocket-{info['version']}-macOS-{arch}.zip"
archive = output / name
if archive.exists():
    raise SystemExit(f'Refusing to overwrite {archive.name}; choose a fresh output directory.')
subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(app), str(archive)], check=True)
digest = hashlib.sha256(archive.read_bytes()).hexdigest()
(output / 'SHA256SUMS').write_text(f'{digest}  {name}\n')
print(archive)
PY

#!/usr/bin/env python3
"""Package a verified app as a ZIP and a drag-to-install DMG."""
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent

def run(*args, capture=False):
    result = subprocess.run(args, check=True, stdout=subprocess.PIPE if capture else None)
    return result.stdout if capture else None

def main():
    output = Path(sys.argv[1] if len(sys.argv) > 1 else ROOT / 'dist').resolve()
    info = json.loads((output / 'build-info.json').read_text())
    if info['signing'] == 'none':
        raise SystemExit('Refusing to package an unsigned build; use adhoc or developer-id.')
    app = output / 'MenuPocket.app'
    run('codesign', '--verify', '--strict', str(app))
    with (app / 'Contents/Info.plist').open('rb') as handle:
        assert plistlib.load(handle)['MenuPocketVersion'] == info['version'], 'Bundle version does not match build-info.json'
    arch = 'universal' if len(info['architectures']) > 1 else info['architectures'][0]
    base = f"MenuPocket-{info['version']}-macOS-{arch}"
    archive, disk = (output / f'{base}.{extension}' for extension in ('zip', 'dmg'))
    for path in (archive, disk):
        if path.exists():
            raise SystemExit(f'Refusing to overwrite {path.name}; choose a fresh output directory.')
    # Publish the package set only after image integrity and mounted app verification.
    with tempfile.TemporaryDirectory(prefix='.package-', dir=output) as temporary:
        temporary = Path(temporary)
        staging = temporary / 'install'
        staging.mkdir()
        run('ditto', str(app), str(staging / 'MenuPocket.app'))
        (staging / 'Applications').symlink_to('/Applications', target_is_directory=True)
        (staging / '安装说明.txt').write_text((ROOT / 'docs/INSTALL.txt').read_text())
        (staging / 'LICENSE.txt').write_text((ROOT / 'LICENSE').read_text())
        staged_disk, staged_archive = temporary / disk.name, temporary / archive.name
        run('hdiutil', 'create', '-volname', 'MenuPocket', '-srcfolder', str(staging),
            '-fs', 'HFS+', '-format', 'UDZO', str(staged_disk))
        run('hdiutil', 'verify', str(staged_disk))
        mount = temporary / 'mounted'
        mount.mkdir()
        run('hdiutil', 'attach', '-readonly', '-nobrowse', '-mountpoint', str(mount), str(staged_disk))
        try:
            run('codesign', '--verify', '--strict', str(mount / 'MenuPocket.app'))
            assert (mount / 'Applications').readlink() == Path('/Applications')
            assert (mount / '安装说明.txt').is_file()
        finally:
            run('hdiutil', 'detach', str(mount))
        run('ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(app), str(staged_archive))
        staged_archive.replace(archive)
        staged_disk.replace(disk)
    checksums = ''.join(f'{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}\n' for path in (disk, archive))
    (output / 'SHA256SUMS').write_text(checksums)
    print(f'Created and verified: {disk}\nZIP alternative: {archive}')

if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Build a macOS bundle without requiring an Xcode project."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent

def run(*args, capture=False):
    result = subprocess.run(args, cwd=ROOT, check=True, text=True,
                            stdout=subprocess.PIPE if capture else None)
    return result.stdout.strip() if capture else None

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--arch', choices=['native', 'arm64', 'x86_64', 'universal'], default='native')
    parser.add_argument('--configuration', choices=['debug', 'release'], default='release')
    parser.add_argument('--sign', choices=['local', 'adhoc', 'developer-id', 'none'], default='local')
    parser.add_argument('--output', type=Path, default=ROOT / 'dist')
    parser.add_argument('--build-number', default=os.environ.get('GITHUB_RUN_NUMBER', '2'))
    args = parser.parse_args()
    if sys.platform != 'darwin':
        parser.error('building MenuPocket requires macOS')
    version = (ROOT / 'VERSION').read_text().strip()
    if not re.fullmatch(r'\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?', version):
        parser.error('VERSION must contain a semantic version')
    if not args.build_number.isdigit():
        parser.error('--build-number must be numeric')
    identity = os.environ.get('CODESIGN_IDENTITY')
    if args.sign == 'developer-id' and not identity:
        parser.error('developer-id signing requires CODESIGN_IDENTITY in an unlocked keychain')
    architectures = ['arm64', 'x86_64'] if args.arch == 'universal' else [args.arch]
    binaries = []
    for arch in architectures:
        arch_args = [] if arch == 'native' else ['--arch', arch]
        command = ['swift', 'build', '-c', args.configuration, *arch_args]
        run(*command)
        binary_dir = Path(run(*command, '--show-bin-path', capture=True))
        binaries.append(binary_dir / 'MenuPocket')
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    # Stage first. A failed signing step must not replace a working local installation.
    with tempfile.TemporaryDirectory(prefix='.bundle-', dir=output) as temporary:
        staged = Path(temporary) / 'MenuPocket.app'
        contents = staged / 'Contents'
        (contents / 'MacOS').mkdir(parents=True)
        executable = contents / 'MacOS/MenuPocket'
        if len(binaries) > 1:
            run('lipo', '-create', *(str(p) for p in binaries), '-output', str(executable))
        else:
            shutil.copy2(binaries[0], executable)
        info = {
            'CFBundleExecutable': 'MenuPocket', 'CFBundleIdentifier': 'local.codeleep.MenuPocket',
            'CFBundleName': 'MenuPocket', 'CFBundleDisplayName': 'MenuPocket',
            'CFBundlePackageType': 'APPL', 'CFBundleShortVersionString': version.split('-')[0],
            'CFBundleVersion': args.build_number, 'MenuPocketVersion': version,
            'LSMinimumSystemVersion': '13.0', 'LSUIElement': True, 'NSHighResolutionCapable': True,
        }
        with (contents / 'Info.plist').open('wb') as handle:
            plistlib.dump(info, handle)
        if args.sign == 'local':
            run(sys.executable, 'scripts/sign-local.py', str(staged))
        elif args.sign == 'adhoc':
            run('codesign', '--force', '--sign', '-', '--timestamp=none', str(staged))
        elif args.sign == 'developer-id':
            run('codesign', '--force', '--sign', identity, '--options', 'runtime', '--timestamp', str(staged))
        if args.sign != 'none':
            run('codesign', '--verify', '--strict', str(staged))
        target = output / 'MenuPocket.app'
        if target.exists():
            # Atomic file replacement preserves a running process's executable inode.
            for source in staged.rglob('*'):
                relative = source.relative_to(staged)
                dest = target / relative
                if source.is_dir():
                    dest.mkdir(parents=True, exist_ok=True)
                else:
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    os.replace(source, dest)
            if args.sign == 'none' and (target / 'Contents/_CodeSignature').exists():
                shutil.rmtree(target / 'Contents/_CodeSignature')
        else:
            os.replace(staged, target)
    if args.sign != 'none':
        run('codesign', '--verify', '--strict', str(target))
    actual_arch = run('lipo', '-archs', str(target / 'Contents/MacOS/MenuPocket'), capture=True)
    metadata = {'version': version, 'buildNumber': args.build_number, 'architectures': actual_arch.split(),
                'signing': args.sign, 'configuration': args.configuration,
                'swift': run('swift', '--version', capture=True),
                'commit': run('git', 'rev-parse', 'HEAD', capture=True) if (ROOT / '.git/HEAD').exists() and subprocess.run(['git', 'rev-parse', '--verify', 'HEAD'], cwd=ROOT, capture_output=True).returncode == 0 else 'uncommitted'}
    (output / 'build-info.json').write_text(json.dumps(metadata, indent=2) + '\n')
    print(f'Built: {target} ({version}; {actual_arch}; {args.sign})')

if __name__ == '__main__':
    main()

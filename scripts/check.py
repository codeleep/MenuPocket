#!/usr/bin/env python3
"""Offline repository hygiene and documentation checks (Python standard library)."""
from pathlib import Path
import ast
import re
import subprocess
from urllib.parse import unquote

root = Path(__file__).resolve().parent.parent
errors = []
version = (root / 'VERSION').read_text().strip()
if not re.fullmatch(r'\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?', version):
    errors.append('Invalid VERSION')
for path in [*root.glob('*.md'), *root.glob('docs/**/*.md')]:
    for link in re.findall(r'\]\(([^\s)]+)(?:\s+"[^"]*")?\)', path.read_text()):
        if '://' in link or link.startswith('#') or link.startswith('mailto:'):
            continue
        target = unquote(link.split('#')[0])
        if not (path.parent / target).exists():
            errors.append(f'{path.relative_to(root)}: missing local link {target}')
for path in (root / 'scripts').glob('*.py'):
    ast.parse(path.read_text(), filename=str(path))
tracked = subprocess.check_output(['git', 'ls-files', '-z'], cwd=root).decode().split('\0')
for name in filter(None, tracked):
    path = Path(name)
    if any(part in {'.local-signing', '.build', 'dist', '__pycache__'} for part in path.parts) or path.suffix in {'.p12', '.p8', '.key', '.pem', '.keychain-db'} or path.name.startswith('.env'):
        errors.append(f'Private/generated file tracked: {name}')
    full = root / path
    if full.suffix not in {'.png', '.jpg', '.zip'} and full.is_file():
        data = full.read_text(errors='replace')
        if re.search(r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----', data):
            errors.append(f'Private key material in {name}')
if errors:
    raise SystemExit('\n'.join(errors))
print('Version, documentation links, Python syntax and tracked-file hygiene passed.')

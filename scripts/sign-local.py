#!/usr/bin/env python3
"""Stable development signing in a project-only keychain; no system trust changes."""
from pathlib import Path
import os
import secrets
import shutil
import shlex
import subprocess
import sys

openssl = os.environ.get("OPENSSL_BIN") or next((p for p in ("/opt/homebrew/opt/openssl@3/bin/openssl", "/usr/local/opt/openssl@3/bin/openssl") if Path(p).exists()), shutil.which("openssl") or "openssl")

root = Path(__file__).resolve().parent.parent
directory = root / ".local-signing"
directory.mkdir(mode=0o700, exist_ok=True)
os.chmod(directory, 0o700)
keychain = directory / "MenuPocket.keychain-db"
password_file = directory / "keychain-password"
identity = "MenuPocket Local Development"

def run(*args, output=False):
    return subprocess.run(args, check=True, text=True,
                          stdout=subprocess.PIPE if output else subprocess.DEVNULL,
                          stderr=subprocess.PIPE)

try:
    if not password_file.exists():
        password_file.write_text(secrets.token_urlsafe(40))
        os.chmod(password_file, 0o600)
    password = password_file.read_text()
    if not keychain.exists():
        old_search = shlex.split(run("security", "list-keychains", "-d", "user", output=True).stdout)
        try:
            run("security", "create-keychain", "-p", password, str(keychain))
        finally:
            run("security", "list-keychains", "-d", "user", "-s", *old_search)
        run("security", "set-keychain-settings", "-lut", "21600", str(keychain))
    run("security", "unlock-keychain", "-p", password, str(keychain))
    cert = directory / "certificate.pem"
    if not cert.exists():
        key = directory / "private-key.pem"
        p12 = directory / "identity.p12"
        env_password = directory / "export-password"
        env_password.write_text(secrets.token_urlsafe(40))
        os.chmod(env_password, 0o600)
        try:
            run(openssl, "req", "-x509", "-newkey", "rsa:3072", "-nodes", "-days", "3650",
                "-subj", f"/CN={identity}", "-addext", "basicConstraints=critical,CA:false",
                "-addext", "keyUsage=critical,digitalSignature", "-addext", "extendedKeyUsage=critical,codeSigning",
                "-keyout", str(key), "-out", str(cert))
            os.chmod(key, 0o600)
            run(openssl, "pkcs12", "-export", "-legacy", "-inkey", str(key), "-in", str(cert),
                "-out", str(p12), "-passout", f"file:{env_password}")
            os.chmod(p12, 0o600)
            run("security", "import", str(p12), "-k", str(keychain), "-P", env_password.read_text(), "-T", "/usr/bin/codesign")
            run("security", "set-key-partition-list", "-S", "apple-tool:,apple:,codesign:", "-s", "-k", password, str(keychain))
        finally:
            for path in (key, p12, env_password):
                path.unlink(missing_ok=True)
    app = sys.argv[1]
    fingerprint = run(openssl, "x509", "-in", str(cert), "-noout", "-fingerprint", "-sha1", output=True).stdout.strip().split("=")[-1].replace(":", "")
    old_search = shlex.split(run("security", "list-keychains", "-d", "user", output=True).stdout)
    try:
        run("security", "list-keychains", "-d", "user", "-s", *old_search, str(keychain))
        run("codesign", "--force", "--sign", fingerprint, "--keychain", str(keychain), "--timestamp=none", app)
    finally:
        run("security", "list-keychains", "-d", "user", "-s", *old_search)
    run("codesign", "--verify", "--strict", app)
    print("Signed with stable project-local development identity (not notarized).")
except subprocess.CalledProcessError as error:
    print(f"Local signing failed at {error.cmd[0]} (exit {error.returncode}).", file=sys.stderr)
    if error.stderr:
        print(error.stderr.strip(), file=sys.stderr)
    sys.exit(1)

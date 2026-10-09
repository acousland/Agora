"""Sign locally through Sparkle's key generator's existing Keychain access.

The private key stays out of stdout, source control, release assets and logs.
TemporaryDirectory removes the owner-only key file on success and failure.
"""
import pathlib
import re
import subprocess
import sys
import tempfile

archive = pathlib.Path(sys.argv[1]).resolve()
root = pathlib.Path(__file__).resolve().parent.parent
tools = root / ".build/artifacts/sparkle/Sparkle/bin"
with tempfile.TemporaryDirectory(prefix="agora-sparkle-sign-") as directory:
    key = pathlib.Path(directory) / "signing-key"
    export = subprocess.run([str(tools / "generate_keys"), "--account", "agora", "-x", str(key)], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
    if export.returncode:
        raise SystemExit("Could not access the Agora signing key. Check the Keychain prompt.")
    key.chmod(0o600)
    signed = subprocess.run([str(tools / "sign_update"), "--ed-key-file", str(key), str(archive)], capture_output=True, text=True, check=True)
    signature = re.search(r'sparkle:edSignature="([^"]+)"', signed.stdout)
    if not signature:
        raise SystemExit("Sparkle did not produce a signature.")
    subprocess.run([str(tools / "sign_update"), "--ed-key-file", str(key), "--verify", str(archive), signature.group(1)], check=True, stdout=subprocess.DEVNULL)
    print(signed.stdout.strip())

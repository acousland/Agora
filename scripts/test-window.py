"""Exercise the native app's own window lifecycle with an isolated selected profile."""
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import uuid

app = pathlib.Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory(prefix="agora-window-test-") as name:
    root = pathlib.Path(name)
    university_id = str(uuid.uuid4())
    settings = {"schemaVersion": 1, "activeID": university_id, "profiles": [{"id": "default", "name": "Work"}, {"id": university_id, "name": "University"}]}
    (root / "profiles.json").write_text(json.dumps(settings))
    (root / "profiles.json").chmod(0o600)
    env = dict(os.environ, AGORA_DATA_DIR=name)
    env.pop("AGORA_PROFILE_ROOT", None)
    env.pop("AGORA_TEST_OUTLOOK_PORT", None)
    process = subprocess.Popen([str(app / "Contents/MacOS/Agora"), "--smoke-window-reopen"], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        stdout, stderr = process.communicate(timeout=15)
    except subprocess.TimeoutExpired:
        process.terminate()
        try: process.wait(timeout=5)
        except subprocess.TimeoutExpired: process.kill(); process.wait()
        raise
    assert process.returncode == 0, stderr or stdout
    assert "Native window smoke passed" in stdout, stdout
    assert json.loads((root / "profiles.json").read_text())["activeID"] == university_id
    assert (root / "Profiles" / university_id / "agora.sqlite").exists()
    assert not (root / "agora.sqlite").exists(), "The inactive Work library must not be opened by mistake"
    print(stdout.strip())

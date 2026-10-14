"""Launch a packaged app and test Outlook without touching the user's library."""
import http.client
import os
import pathlib
import socket
import ssl
import subprocess
import sys
import tempfile
import time
import xml.etree.ElementTree as ET

root = pathlib.Path(__file__).resolve().parent.parent
app = pathlib.Path(sys.argv[1]).resolve()
executable = app / "Contents/MacOS/Agora"
manifest = app / "Contents/Resources/Agora_AgoraMac.bundle/Contents/Resources/Outlook/manifest.xml"
ET.parse(manifest)
try:
    with socket.create_connection(("127.0.0.1", 3848), timeout=1):
        raise RuntimeError("Port 3848 is in use. Refusing to test a running user's receiver.")
except ConnectionRefusedError:
    pass

with tempfile.TemporaryDirectory(prefix="agora-outlook-test-") as name, tempfile.TemporaryFile() as log:
    directory = pathlib.Path(name)
    env = dict(os.environ, AGORA_DATA_DIR=name, AGORA_SKIP_CERT_TRUST="1")
    subprocess.run([str(root / "scripts/setup-outlook.sh"), name], env=env, check=True)
    context = ssl.create_default_context(cafile=str(directory / "localhost.crt"))
    process = subprocess.Popen([str(executable)], env=env, stdin=subprocess.DEVNULL, stdout=log, stderr=log)
    try:
        ready = False
        for _ in range(80):
            if process.poll() is not None:
                break
            connection = http.client.HTTPSConnection("localhost", 3848, context=context, timeout=1)
            try:
                connection.request("GET", "/health")
                response = connection.getresponse()
                ready = response.status == 200
                response.read()
            except OSError:
                pass
            finally:
                connection.close()
            if ready:
                break
            time.sleep(0.25)
        if not ready:
            raise RuntimeError("The isolated app did not start its HTTPS receiver.")
        subprocess.run([sys.executable, str(root / "scripts/smoke-outlook.py"), name], check=True)
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()

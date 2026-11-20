import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


class CatalogPublicationTest(unittest.TestCase):
    def test_failed_signing_preserves_existing_outputs(self):
        with tempfile.TemporaryDirectory() as directory:
            db = Path(directory) / "catalog.db"
            manifest = Path(directory) / "manifest.json"
            db.write_bytes(b"previous-db")
            manifest.write_bytes(b"previous-manifest")
            command = [
                sys.executable, str(Path(__file__).with_name("build_catalog.py")),
                "--seed", "--out-db", str(db), "--out-manifest", str(manifest),
                "--report", "",
            ]
            result = subprocess.run(
                [*command, "--key", str(Path(directory) / "missing-key"), "--production"],
                capture_output=True, check=False,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(db.read_bytes(), b"previous-db")
            self.assertEqual(manifest.read_bytes(), b"previous-manifest")

            key = Path(__file__).with_name("publisher_test_key.ed25519")
            subprocess.run([*command, "--key", str(key)], capture_output=True, check=True)
            signed = json.loads(manifest.read_text())
            self.assertEqual(signed["artifact"], db.name)
            self.assertEqual(signed["sha256"], hashlib.sha256(db.read_bytes()).hexdigest())


if __name__ == "__main__":
    unittest.main()

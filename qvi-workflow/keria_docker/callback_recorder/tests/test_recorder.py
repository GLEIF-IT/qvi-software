import json
import tempfile
import threading
import unittest
from pathlib import Path
from urllib.request import Request, urlopen

from callback_recorder import recorder


class RecorderTest(unittest.TestCase):
    def test_appends_callback_as_jsonl(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            callbacks_path = Path(directory) / "callbacks.jsonl"

            recorder.record_callback(
                {
                    "action": "iss",
                    "data": {"credential": "ECredential"},
                },
                callbacks_path,
            )

            record = json.loads(callbacks_path.read_text())
            self.assertEqual(record["action"], "iss")
            self.assertEqual(
                record["data"]["credential"],
                "ECredential",
            )
            self.assertIn("receivedAt", record)

    def test_rejects_non_object_callback(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            callbacks_path = Path(directory) / "callbacks.jsonl"

            with self.assertRaisesRegex(
                ValueError,
                "JSON object",
            ):
                recorder.record_callback(
                    ["not", "an", "object"],
                    callbacks_path,
                )

            self.assertFalse(callbacks_path.exists())

    def test_health_and_callback_endpoints(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            callbacks_path = Path(directory) / "callbacks.jsonl"
            original_path = recorder.CALLBACKS_PATH
            recorder.CALLBACKS_PATH = callbacks_path
            server = recorder.ThreadingHTTPServer(
                ("127.0.0.1", 0),
                recorder.CallbackHandler,
            )
            thread = threading.Thread(
                target=server.serve_forever,
                daemon=True,
            )
            thread.start()
            base_url = f"http://127.0.0.1:{server.server_port}"

            try:
                with urlopen(f"{base_url}/health") as response:
                    self.assertEqual(response.status, 200)

                request = Request(
                    f"{base_url}/",
                    data=json.dumps(
                        {
                            "action": "iss",
                            "data": {"credential": "ECredential"},
                        }
                    ).encode(),
                    headers={"Content-Type": "application/json"},
                    method="POST",
                )
                with urlopen(request) as response:
                    self.assertEqual(response.status, 202)

                record = json.loads(callbacks_path.read_text())
                self.assertEqual(record["action"], "iss")
            finally:
                server.shutdown()
                server.server_close()
                thread.join()
                recorder.CALLBACKS_PATH = original_path


if __name__ == "__main__":
    unittest.main()

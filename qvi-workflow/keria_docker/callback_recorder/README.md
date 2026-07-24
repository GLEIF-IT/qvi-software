# Sally callback recorder

`recorder.py` is the small webhook used by the local QVI story. It accepts a
JSON object at `POST /`, adds a `receivedAt` timestamp, and appends the result
to `runtime/sally-callbacks.jsonl`. `GET /health` supports the Compose health
check.

The driver starts with an empty runtime directory and waits for the expected
credential SAID and Sally action to appear in this file.

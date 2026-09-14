"""Canary writer: inserts (seq, ts) into Postgres once a second.

Why it exists: after a recovery, the highest seq still present in the database,
compared with the highest seq written before the fault, is the data loss (RPO),
measured in seconds because one row is written per second.

Standard library plus psycopg only, on purpose: nothing else to patch.
Connection settings come from the standard PG* environment variables.
"""
import json
import os
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import psycopg

INTERVAL = float(os.environ.get("WRITE_INTERVAL_SECONDS", "1.0"))
HTTP_PORT = int(os.environ.get("HTTP_PORT", "8080"))
# /healthz fails if no write succeeded recently, so "healthy" means writes really resume.
HEALTH_MAX_AGE = float(os.environ.get("HEALTH_MAX_AGE_SECONDS", "5"))

SCHEMA = "CREATE TABLE IF NOT EXISTS canary (seq BIGINT PRIMARY KEY, ts TIMESTAMPTZ NOT NULL DEFAULT now())"

_lock = threading.Lock()
_state = {"last_seq": 0, "last_ok": 0.0, "errors": 0}


def connect():
    # connect_timeout keeps a dead database from freezing the loop for minutes.
    return psycopg.connect(autocommit=True, connect_timeout=3)


def next_seq(conn):
    """Continue from whatever the database holds, so a restored database resumes cleanly."""
    row = conn.execute("SELECT COALESCE(MAX(seq), 0) FROM canary").fetchone()
    return int(row[0]) + 1


def writer_loop(stop):
    conn = None
    seq = 0
    due = time.monotonic()
    while not stop.is_set():
        try:
            if conn is None:
                conn = connect()
                conn.execute(SCHEMA)
                seq = next_seq(conn)
            conn.execute("INSERT INTO canary (seq) VALUES (%s)", (seq,))
            with _lock:
                _state["last_seq"] = seq
                _state["last_ok"] = time.time()
            seq += 1
        except Exception:  # noqa: BLE001 - any failure means: count it, reconnect, retry
            with _lock:
                _state["errors"] += 1
            if conn is not None:
                try:
                    conn.close()
                except Exception:  # noqa: BLE001
                    pass
            conn = None  # re-read MAX(seq) on reconnect: the insert may or may not have landed
        due += INTERVAL
        # If we fell behind (outage), do not fire a burst of catch-up writes.
        due = max(due, time.monotonic())
        stop.wait(max(0.0, due - time.monotonic()))


def db_last_seq():
    with connect() as conn:
        row = conn.execute("SELECT seq, extract(epoch FROM ts) FROM canary ORDER BY seq DESC LIMIT 1").fetchone()
    return (int(row[0]), float(row[1])) if row else (0, 0.0)


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body, ctype="application/json"):
        data = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):  # noqa: N802 - name required by BaseHTTPRequestHandler
        if self.path == "/livez":
            self._send(200, '{"alive":true}')
        elif self.path == "/healthz":
            with _lock:
                age = time.time() - _state["last_ok"] if _state["last_ok"] else None
                seq = _state["last_seq"]
            ok = age is not None and age <= HEALTH_MAX_AGE
            self._send(200 if ok else 503, json.dumps({"healthy": ok, "last_seq": seq, "last_write_age_seconds": age}))
        elif self.path == "/last-seq":
            # Reads the database, not memory: after a restore this is the truth about what survived.
            try:
                seq, ts = db_last_seq()
                self._send(200, json.dumps({"seq": seq, "ts": ts}))
            except Exception as exc:  # noqa: BLE001
                self._send(503, json.dumps({"error": type(exc).__name__}))
        elif self.path == "/metrics":
            with _lock:
                s = dict(_state)
            body = (
                "# HELP canary_last_seq Highest sequence number written by this process.\n"
                "# TYPE canary_last_seq gauge\n"
                f"canary_last_seq {s['last_seq']}\n"
                "# HELP canary_last_write_timestamp_seconds Unix time of the last successful write.\n"
                "# TYPE canary_last_write_timestamp_seconds gauge\n"
                f"canary_last_write_timestamp_seconds {s['last_ok']}\n"
                "# HELP canary_write_errors_total Failed write attempts since start.\n"
                "# TYPE canary_write_errors_total counter\n"
                f"canary_write_errors_total {s['errors']}\n"
            )
            self._send(200, body, "text/plain; version=0.0.4")
        else:
            self._send(404, '{"error":"not found"}')

    def log_message(self, fmt, *args):  # keep probe traffic out of the logs
        pass


def main():
    stop = threading.Event()
    threading.Thread(target=writer_loop, args=(stop,), daemon=True).start()
    server = ThreadingHTTPServer(("0.0.0.0", HTTP_PORT), Handler)  # noqa: S104 - pod network only
    try:
        server.serve_forever()
    finally:
        stop.set()


if __name__ == "__main__":
    main()

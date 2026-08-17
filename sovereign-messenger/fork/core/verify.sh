#!/bin/sh
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
EXPECTED_COMMIT=e11128ce5b0df538c57a0d0b6911de0e88fdb652

sh -n "$HERE/apply.sh"
sh -n "$HERE/verify.sh"
test -f "$HERE/integration.patch"
test -f "$HERE/overlay/src/Simplex/Chat/Sovereign/Types.hs"
test -f "$HERE/overlay/src/Simplex/Chat/Store/Sovereign.hs"

python3 - "$HERE/vectors/sovereign-v1.json" <<'PY'
import hashlib
import json
import struct
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    v = json.load(f)

scope = bytes.fromhex(v["scope_id"])
policy = bytes.fromhex(v["policy_hash"])
pub = bytes.fromhex(v["public_key_raw"])
genesis = (b"SOVEREIGN-GENESIS-V1\0" + scope + bytes([v["scope_kind"]])
           + struct.pack(">I", v["epoch"]) + policy + pub)
assert genesis.hex() == v["genesis_preimage"]
assert hashlib.sha256(genesis).hexdigest() == v["genesis_hash"]

evidence = bytes.fromhex(v["evidence_hash"])
payload = (bytes([v["event_kind"], v["state"]])
           + struct.pack(">H", v["flags"]) + b"\x01" + evidence)
assert payload.hex() == v["event_payload"]
event = (b"SOVEREIGN-EVENT-V1\0" + scope
         + struct.pack(">I", v["epoch"])
         + struct.pack(">Q", v["sequence"])
         + bytes.fromhex(v["previous_hash"]) + payload
         + struct.pack(">Q", v["time_bucket"])
         + bytes.fromhex(v["nonce"]))
assert event.hex() == v["event_preimage"]
event_hash = hashlib.sha256(event).digest()
assert event_hash.hex() == v["event_hash"]

checkpoint = (b"SOVEREIGN-CHECKPOINT-V1\0" + scope
              + struct.pack(">I", v["epoch"])
              + struct.pack(">Q", v["checkpoint_event_count"])
              + event_hash)
assert checkpoint.hex() == v["checkpoint_preimage"]
assert hashlib.sha256(checkpoint).hexdigest() == v["checkpoint_digest"]
print("deterministic v1 vectors: OK")
PY

python3 - "$HERE/overlay/src/Simplex/Chat/Store/SQLite/Migrations/M20260817_sovereign_registry.hs" <<'PY'
import pathlib
import re
import sqlite3
import sys

source = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
match = re.search(r"\[sql\|(.*?)\|\]", source, re.S)
assert match is not None
db = sqlite3.connect(":memory:")
db.execute("PRAGMA foreign_keys = ON")
db.executescript("CREATE TABLE users(user_id INTEGER PRIMARY KEY) STRICT;"
                 "CREATE TABLE contacts(contact_id INTEGER PRIMARY KEY) STRICT;")
db.executescript(match.group(1))
strict = dict(db.execute(
    "SELECT name, strict FROM pragma_table_list WHERE name LIKE 'sovereign_%'"
))
assert strict == {
    "sovereign_scopes": 1,
    "sovereign_events": 1,
    "sovereign_checkpoints": 1,
}
db.execute("INSERT INTO users VALUES (1)")
scope = bytes(range(32))
head = bytes(range(32, 64))
db.execute(
    "INSERT INTO sovereign_scopes VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)",
    (scope, 1, None, 1, 0, head, b'p' * 44, b's' * 48, 0, head, 1,
     "2026-08-17T00:00:00Z", "2026-08-17T00:00:00Z"),
)
try:
    db.execute(
        "INSERT INTO sovereign_events VALUES (?,?,?,?,?,?,?,?,?)",
        (scope, 0, 0, b'x' * 36, b'n' * 16, 0, head, head,
         "2026-08-17T00:00:00Z"),
    )
except sqlite3.IntegrityError:
    pass
else:
    raise AssertionError("event payload length constraint not enforced")
db.execute(
    "INSERT INTO sovereign_events VALUES (?,?,?,?,?,?,?,?,?)",
    (scope, 0, 0, b'x' * 37, b'n' * 16, 0, head, head,
     "2026-08-17T00:00:00Z"),
)
db.execute(
    "INSERT INTO sovereign_checkpoints VALUES (?,?,?,?,?,?,?,?)",
    (scope, 0, 1, head, b'z' * 64, None, None,
     "2026-08-17T00:00:00Z"),
)
db.execute("DELETE FROM users WHERE user_id = 1")
for table in ("sovereign_scopes", "sovereign_events", "sovereign_checkpoints"):
    assert db.execute(f"SELECT count(*) FROM {table}").fetchone()[0] == 0
print("SQLite migration constraints/cascade: OK")
PY

if [ "$#" -gt 0 ]; then
  target=$1
  actual=$(git -C "$target" rev-parse HEAD)
  test "$actual" = "$EXPECTED_COMMIT"
  if git -C "$target" apply --reverse --check "$HERE/integration.patch" >/dev/null 2>&1; then
    echo "integration patch: already applied"
  else
    git -C "$target" apply --check "$HERE/integration.patch"
    echo "integration patch: applies cleanly"
  fi
fi

echo "patch kit: OK"

# Sovereign registry patch kit for SimpleX Chat v7.0.0

This directory contains a reproducible, narrowly scoped patch kit for the
official `simplex-chat` tag `v7.0.0` (commit
`e11128ce5b0df538c57a0d0b6911de0e88fdb652`). It adds a local, per-device or
per-contact append-only registry to the Haskell core.

## Security boundary

Implemented:

- fixed-size, canonical v1 preimages with domain separation;
- SHA-256 hash chaining and Ed25519-signed checkpoints;
- an allow-listed event vocabulary with no message text, names, addresses,
  attachment data, URLs, or free-form metadata;
- SQLite and PostgreSQL migrations with length/range/FK constraints;
- transaction-wrapped create, append, checkpoint, and bounded read commands;
- PostgreSQL row locking and SQLite transaction/uniqueness conflict safety;
- corruption checks on every decoded row, page, and checkpoint;
- deterministic vectors and Hspec tests, including concurrent append.

Not implemented:

- no automatic send/receive hook;
- no registry frame in `ChatMsgEvent` and no peer checkpoint receipt;
- no synchronization, transparency log, remote witness, rollback-resistant
  hardware counter, or Android UI;
- private checkpoint keys remain protected only by the existing encrypted chat
  database and process boundary.

The Cabal flag `sovereign-peer-anchor` defaults to `False`. Enabling it makes
the build fail with `#error`, deliberately: a partial protocol hook would
create a false security claim. A later audited patch must define the signed
wire frame, replay/epoch rules, capability negotiation, downgrade behavior,
and atomic receive/send hooks before removing that guard.

This is an unaudited engineering prototype. It is not evidence that a device,
conversation, or APK is “totally secure”.

## Apply

From this directory:

```sh
sh ./apply.sh /path/to/simplex-chat-v7.0.0
```

`apply.sh` checks the exact upstream commit, refuses conflicting overlay files,
and is idempotent. It does not reset, clean, or commit the target checkout.

Then build both backends and run the focused tests, for example:

```sh
cabal test simplex-chat-test --test-options='--match Sovereign registry'
cabal test simplex-chat-test -fclient_postgres --test-options='--match Sovereign registry'
```

To statically verify this kit and its vectors without GHC:

```sh
sh ./verify.sh
sh ./verify.sh /path/to/simplex-chat-v7.0.0
```

## Verification status and mandatory CI gate

In the preparation environment, the integration diff passes `git apply
--check`, repeated application is idempotent, `git diff --check` is clean, and
the independent Python implementation reproduces every normative v1 vector.

GHC, Cabal, SQLite CLI, and PostgreSQL were not available there. Therefore this
kit is **not claimed to be compile-verified**. Before merging, CI must:

1. build the SQLite and `-fclient_postgres` variants with the exact dependency
   revisions in upstream `cabal.project`;
2. run the focused Hspec tests for both variants, including the concurrent
   append test;
3. regenerate and review upstream's SQLite and PostgreSQL `chat_schema.sql`
   snapshots, then run the complete schema/down-migration/lint suite;
4. run the entire upstream test suite and a migration test from a real v7.0.0
   database copy.

The schema snapshots are deliberately not fabricated in this kit: they must be
produced by upstream's own SQLite/`pg_dump` test machinery. Until that CI gate
is green, this is a fail-closed patch candidate, not a releasable registry.

## Format v1

All integers are unsigned big-endian values after range validation. Scope IDs
and hashes are 32 bytes; nonces are 16 bytes. Event payloads are always 37
bytes: kind (1), state (1), flags (2), evidence-present (1), and evidence hash
(32, all zero when absent). Domains include the final NUL byte.

The JSON file in `vectors/` is normative for v1. Changing any field order,
domain, size, or canonical-absence rule requires a new format version and a
migration, never an in-place reinterpretation.

{-# LANGUAGE QuasiQuotes #-}

module Simplex.Chat.Store.SQLite.Migrations.M20260817_sovereign_registry where

import Database.SQLite.Simple (Query)
import Database.SQLite.Simple.QQ (sql)

m20260817_sovereign_registry :: Query
m20260817_sovereign_registry =
  [sql|
CREATE TABLE sovereign_scopes (
  scope_id BLOB PRIMARY KEY CHECK (length(scope_id) = 32),
  user_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  contact_id INTEGER REFERENCES contacts(contact_id) ON DELETE CASCADE,
  scope_kind INTEGER NOT NULL CHECK (scope_kind IN (1, 2)),
  epoch INTEGER NOT NULL CHECK (epoch >= 0 AND epoch <= 4294967295),
  policy_hash BLOB NOT NULL CHECK (length(policy_hash) = 32),
  public_key BLOB NOT NULL CHECK (length(public_key) BETWEEN 32 AND 128),
  private_key BLOB NOT NULL CHECK (length(private_key) BETWEEN 32 AND 160),
  next_sequence INTEGER NOT NULL CHECK (next_sequence >= 0),
  head_hash BLOB NOT NULL CHECK (length(head_hash) = 32),
  active INTEGER NOT NULL CHECK (active IN (0, 1)),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE (scope_id, epoch),
  CHECK ((scope_kind = 1 AND contact_id IS NULL) OR (scope_kind = 2 AND contact_id IS NOT NULL))
) STRICT;

CREATE UNIQUE INDEX idx_sovereign_active_contact
  ON sovereign_scopes(user_id, contact_id)
  WHERE contact_id IS NOT NULL AND active = 1;
CREATE INDEX idx_sovereign_scopes_user_updated
  ON sovereign_scopes(user_id, updated_at DESC);
CREATE INDEX idx_sovereign_scopes_contact
  ON sovereign_scopes(contact_id);

CREATE TABLE sovereign_events (
  scope_id BLOB NOT NULL,
  epoch INTEGER NOT NULL CHECK (epoch >= 0 AND epoch <= 4294967295),
  sequence_no INTEGER NOT NULL CHECK (sequence_no >= 0),
  event_payload BLOB NOT NULL CHECK (length(event_payload) = 37),
  nonce BLOB NOT NULL CHECK (length(nonce) = 16),
  time_bucket INTEGER NOT NULL CHECK (time_bucket >= 0),
  previous_hash BLOB NOT NULL CHECK (length(previous_hash) = 32),
  event_hash BLOB NOT NULL CHECK (length(event_hash) = 32),
  created_at TEXT NOT NULL,
  PRIMARY KEY (scope_id, epoch, sequence_no),
  UNIQUE (scope_id, epoch, nonce),
  FOREIGN KEY (scope_id, epoch) REFERENCES sovereign_scopes(scope_id, epoch) ON DELETE CASCADE
) STRICT, WITHOUT ROWID;

CREATE INDEX idx_sovereign_events_created
  ON sovereign_events(scope_id, epoch, created_at);

CREATE TABLE sovereign_checkpoints (
  scope_id BLOB NOT NULL,
  epoch INTEGER NOT NULL CHECK (epoch >= 0 AND epoch <= 4294967295),
  event_count INTEGER NOT NULL CHECK (event_count >= 0),
  head_hash BLOB NOT NULL CHECK (length(head_hash) = 32),
  signature BLOB NOT NULL CHECK (length(signature) = 64),
  peer_key BLOB,
  peer_signature BLOB,
  created_at TEXT NOT NULL,
  PRIMARY KEY (scope_id, epoch, event_count),
  FOREIGN KEY (scope_id, epoch) REFERENCES sovereign_scopes(scope_id, epoch) ON DELETE CASCADE,
  CHECK ((peer_key IS NULL AND peer_signature IS NULL) OR
         (peer_key IS NOT NULL AND peer_signature IS NOT NULL AND
          length(peer_key) BETWEEN 32 AND 128 AND length(peer_signature) = 64))
) STRICT, WITHOUT ROWID;
|]

down_m20260817_sovereign_registry :: Query
down_m20260817_sovereign_registry =
  [sql|
DROP TABLE sovereign_checkpoints;
DROP TABLE sovereign_events;
DROP TABLE sovereign_scopes;
|]

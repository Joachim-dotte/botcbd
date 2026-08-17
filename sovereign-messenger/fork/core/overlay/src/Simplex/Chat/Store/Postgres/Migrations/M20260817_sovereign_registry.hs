{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

module Simplex.Chat.Store.Postgres.Migrations.M20260817_sovereign_registry where

import Data.Text (Text)
import Text.RawString.QQ (r)

m20260817_sovereign_registry :: Text
m20260817_sovereign_registry =
  [r|
CREATE TABLE sovereign_scopes (
  scope_id BYTEA PRIMARY KEY CHECK (octet_length(scope_id) = 32),
  user_id BIGINT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  contact_id BIGINT REFERENCES contacts(contact_id) ON DELETE CASCADE,
  scope_kind SMALLINT NOT NULL CHECK (scope_kind IN (1, 2)),
  epoch BIGINT NOT NULL CHECK (epoch >= 0 AND epoch <= 4294967295),
  policy_hash BYTEA NOT NULL CHECK (octet_length(policy_hash) = 32),
  public_key BYTEA NOT NULL CHECK (octet_length(public_key) BETWEEN 32 AND 128),
  private_key BYTEA NOT NULL CHECK (octet_length(private_key) BETWEEN 32 AND 160),
  next_sequence BIGINT NOT NULL CHECK (next_sequence >= 0),
  head_hash BYTEA NOT NULL CHECK (octet_length(head_hash) = 32),
  active SMALLINT NOT NULL CHECK (active IN (0, 1)),
  created_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL,
  UNIQUE (scope_id, epoch),
  CHECK ((scope_kind = 1 AND contact_id IS NULL) OR (scope_kind = 2 AND contact_id IS NOT NULL))
);

CREATE UNIQUE INDEX idx_sovereign_active_contact
  ON sovereign_scopes(user_id, contact_id)
  WHERE contact_id IS NOT NULL AND active = 1;
CREATE INDEX idx_sovereign_scopes_user_updated
  ON sovereign_scopes(user_id, updated_at DESC);
CREATE INDEX idx_sovereign_scopes_contact
  ON sovereign_scopes(contact_id);

CREATE TABLE sovereign_events (
  scope_id BYTEA NOT NULL,
  epoch BIGINT NOT NULL CHECK (epoch >= 0 AND epoch <= 4294967295),
  sequence_no BIGINT NOT NULL CHECK (sequence_no >= 0),
  event_payload BYTEA NOT NULL CHECK (octet_length(event_payload) = 37),
  nonce BYTEA NOT NULL CHECK (octet_length(nonce) = 16),
  time_bucket BIGINT NOT NULL CHECK (time_bucket >= 0),
  previous_hash BYTEA NOT NULL CHECK (octet_length(previous_hash) = 32),
  event_hash BYTEA NOT NULL CHECK (octet_length(event_hash) = 32),
  created_at TIMESTAMPTZ NOT NULL,
  PRIMARY KEY (scope_id, epoch, sequence_no),
  UNIQUE (scope_id, epoch, nonce),
  FOREIGN KEY (scope_id, epoch) REFERENCES sovereign_scopes(scope_id, epoch) ON DELETE CASCADE
);

CREATE INDEX idx_sovereign_events_created
  ON sovereign_events(scope_id, epoch, created_at);

CREATE TABLE sovereign_checkpoints (
  scope_id BYTEA NOT NULL,
  epoch BIGINT NOT NULL CHECK (epoch >= 0 AND epoch <= 4294967295),
  event_count BIGINT NOT NULL CHECK (event_count >= 0),
  head_hash BYTEA NOT NULL CHECK (octet_length(head_hash) = 32),
  signature BYTEA NOT NULL CHECK (octet_length(signature) = 64),
  peer_key BYTEA,
  peer_signature BYTEA,
  created_at TIMESTAMPTZ NOT NULL,
  PRIMARY KEY (scope_id, epoch, event_count),
  FOREIGN KEY (scope_id, epoch) REFERENCES sovereign_scopes(scope_id, epoch) ON DELETE CASCADE,
  CHECK ((peer_key IS NULL AND peer_signature IS NULL) OR
         (peer_key IS NOT NULL AND peer_signature IS NOT NULL AND
          octet_length(peer_key) BETWEEN 32 AND 128 AND octet_length(peer_signature) = 64))
);
|]

down_m20260817_sovereign_registry :: Text
down_m20260817_sovereign_registry =
  [r|
DROP TABLE sovereign_checkpoints;
DROP TABLE sovereign_events;
DROP TABLE sovereign_scopes;
|]

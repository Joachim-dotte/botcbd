{-# LANGUAGE CPP #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TupleSections #-}

module Simplex.Chat.Store.Sovereign
  ( sovereignCreateScope,
    sovereignCreateScopeTx,
    sovereignAppend,
    sovereignAppendTx,
    sovereignCreateCheckpoint,
    sovereignCreateCheckpointTx,
    sovereignReadScope,
    sovereignReadEvents,
    sovereignReadCheckpoints,
    sovereignListScopes,
  )
where

import qualified Control.Exception as E
import Control.Monad (unless, when)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Except
import qualified Data.ByteString as B
import Data.ByteString (ByteString)
import Data.Int (Int64)
import Data.List (sortOn)
import Data.Time.Clock (UTCTime, getCurrentTime)
import Simplex.Chat.Sovereign.Types
import Simplex.Messaging.Agent.Store.Common (DBStore, withTransaction)
import Simplex.Messaging.Agent.Store.DB (Binary (..), BoolInt (..))
import qualified Simplex.Messaging.Agent.Store.DB as DB
import qualified Simplex.Messaging.Crypto as C
#if defined(dbPostgres)
import Database.PostgreSQL.Simple (Only (..), Query, (:.) (..))
#else
import Database.SQLite.Simple (Only (..), Query, (:.) (..))
#endif

data ScopeState = ScopeState
  { publicScope :: SovereignScope,
    privateCheckpointKey :: C.PrivateKeyEd25519
  }

newtype SovereignRollback = SovereignRollback SovereignError
  deriving (Show)

instance E.Exception SovereignRollback

type ScopeRow =
  (Binary ByteString, Int64, Maybe Int64, Int64, Int64, Binary ByteString, C.PublicKeyEd25519, C.PrivateKeyEd25519)
    :. (Int64, Binary ByteString, BoolInt, UTCTime, UTCTime)

type EventRow = (Int64, Binary ByteString, Binary ByteString, Int64, Binary ByteString, Binary ByteString, UTCTime)

type CheckpointRow = (Int64, Binary ByteString, Binary ByteString, Maybe (Binary ByteString), Maybe (Binary ByteString), UTCTime)

scopeColumns :: Query
scopeColumns =
  "scope_id, user_id, contact_id, scope_kind, epoch, policy_hash, public_key, private_key, next_sequence, head_hash, active, created_at, updated_at"

scopeSelect :: Query
scopeSelect = "SELECT " <> scopeColumns <> " FROM sovereign_scopes"

sovereignCreateScope :: DBStore -> SovereignScopeId -> Int64 -> Maybe Int64 -> SovereignScopeKind -> Int64 -> SovereignHash -> C.PublicKeyEd25519 -> C.PrivateKeyEd25519 -> IO (Either SovereignError SovereignScope)
sovereignCreateScope store scopeId userId contactId scopeKind epoch policyHash publicKey privateKey =
  runWrite store $ \db -> sovereignCreateScopeTx db scopeId userId contactId scopeKind epoch policyHash publicKey privateKey

sovereignCreateScopeTx :: DB.Connection -> SovereignScopeId -> Int64 -> Maybe Int64 -> SovereignScopeKind -> Int64 -> SovereignHash -> C.PublicKeyEd25519 -> C.PrivateKeyEd25519 -> ExceptT SovereignError IO SovereignScope
sovereignCreateScopeTx db scopeId userId contactId scopeKind epoch policyHash publicKey privateKey = do
  when (userId < 0) $ throwE $ SERInvalidRange "user_id" userId
  when (scopeKind == SSKDevice && contactId /= Nothing) $ throwE $ SERCorruptStore "device scope cannot reference a contact"
  when (scopeKind == SSKContact && maybe True (< 0) contactId) $ throwE $ SERCorruptStore "contact scope requires a contact"
  unless (C.publicKey privateKey == publicKey) $ throwE $ SERCorruptStore "checkpoint key pair mismatch"
  headHash <- liftEither $ sovereignGenesisHash scopeId scopeKind epoch policyHash publicKey
  now <- liftIO getCurrentTime
  liftIO $
    DB.execute
      db
      "INSERT INTO sovereign_scopes (scope_id, user_id, contact_id, scope_kind, epoch, policy_hash, public_key, private_key, next_sequence, head_hash, active, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?, 1, ?, ?)"
      ( Binary (sovereignScopeIdBytes scopeId),
        userId,
        contactId,
        fromIntegral (sovereignScopeKindTag scopeKind) :: Int64,
        epoch,
        Binary (sovereignHashBytes policyHash),
        publicKey,
        privateKey
      )
        :. (Binary (sovereignHashBytes headHash), now, now)
  pure
    SovereignScope
      { sovereignScopeId = scopeId,
        sovereignScopeUserId = userId,
        sovereignScopeContactId = contactId,
        sovereignScopeKind = scopeKind,
        sovereignScopeEpoch = epoch,
        sovereignScopePolicyHash = policyHash,
        sovereignScopePublicKey = publicKey,
        sovereignScopeNextSequence = 0,
        sovereignScopeHeadHash = headHash,
        sovereignScopeActive = True,
        sovereignScopeCreatedAt = now,
        sovereignScopeUpdatedAt = now
      }

sovereignAppend :: DBStore -> SovereignScopeId -> SovereignEventData -> SovereignNonce -> Int64 -> IO (Either SovereignError SovereignEvent)
sovereignAppend store scopeId eventData nonce timeBucket =
  runWrite store $ \db -> sovereignAppendTx db scopeId eventData nonce timeBucket

-- Atomicity contract: this Tx function must run inside the caller's database
-- transaction. Prefer sovereignAppend, which supplies that boundary.
sovereignAppendTx :: DB.Connection -> SovereignScopeId -> SovereignEventData -> SovereignNonce -> Int64 -> ExceptT SovereignError IO SovereignEvent
sovereignAppendTx db scopeId eventData nonce timeBucket = do
  ScopeState {publicScope = SovereignScope {sovereignScopeEpoch = epoch, sovereignScopeNextSequence = nextSequence, sovereignScopeHeadHash = previousHead, sovereignScopeActive = active}} <- getScopeStateTx db True scopeId
  unless active $ throwE SERScopeInactive
  eventHash <- liftEither $ sovereignEventHash scopeId epoch nextSequence previousHead eventData timeBucket nonce
  now <- liftIO getCurrentTime
  liftIO $ do
    DB.execute
      db
      "INSERT INTO sovereign_events (scope_id, epoch, sequence_no, event_payload, nonce, time_bucket, previous_hash, event_hash, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"
      ( Binary $ sovereignScopeIdBytes scopeId,
        epoch,
        nextSequence,
        Binary $ encodeSovereignEventData eventData,
        Binary $ sovereignNonceBytes nonce,
        timeBucket,
        Binary $ sovereignHashBytes previousHead,
        Binary $ sovereignHashBytes eventHash,
        now
      )
    DB.execute
      db
      "UPDATE sovereign_scopes SET next_sequence = ?, head_hash = ?, updated_at = ? WHERE scope_id = ? AND epoch = ? AND next_sequence = ? AND head_hash = ? AND active = 1"
      ( nextSequence + 1,
        Binary $ sovereignHashBytes eventHash,
        now,
        Binary $ sovereignScopeIdBytes scopeId,
        epoch,
        nextSequence,
        Binary $ sovereignHashBytes previousHead
      )
  -- A locked row on PostgreSQL and uniqueness/transaction rollback on SQLite
  -- prevent two successful records with the same sequence. Re-read makes any
  -- future DB wrapper that silently loses the CAS fail closed.
  ScopeState {publicScope = updated} <- getScopeStateTx db False scopeId
  unless (sovereignScopeNextSequence updated == nextSequence + 1 && sovereignScopeHeadHash updated == eventHash) $
    rollback $ SERCorruptStore "scope head compare-and-swap failed"
  pure
    SovereignEvent
      { sovereignEventScopeId = scopeId,
        sovereignEventEpoch = epoch,
        sovereignEventSequence = nextSequence,
        sovereignEventData = eventData,
        sovereignEventNonce = nonce,
        sovereignEventTimeBucket = timeBucket,
        sovereignEventPreviousHash = previousHead,
        sovereignEventHashValue = eventHash,
        sovereignEventCreatedAt = now
      }

sovereignCreateCheckpoint :: DBStore -> SovereignScopeId -> IO (Either SovereignError SovereignCheckpoint)
sovereignCreateCheckpoint store scopeId =
  runWrite store $ \db -> sovereignCreateCheckpointTx db scopeId

sovereignCreateCheckpointTx :: DB.Connection -> SovereignScopeId -> ExceptT SovereignError IO SovereignCheckpoint
sovereignCreateCheckpointTx db scopeId = do
  ScopeState {publicScope = scope@SovereignScope {sovereignScopeEpoch, sovereignScopeNextSequence, sovereignScopeHeadHash, sovereignScopePublicKey, sovereignScopeActive}, privateCheckpointKey} <- getScopeStateTx db True scopeId
  unless sovereignScopeActive $ throwE SERScopeInactive
  existing <- checkpointAtTx db scope sovereignScopeNextSequence
  case existing of
    Just checkpoint -> checkpoint <$ verifyCheckpointOrThrow scope checkpoint
    Nothing -> do
      signature <- liftEither $ signSovereignCheckpoint privateCheckpointKey scopeId sovereignScopeEpoch sovereignScopeNextSequence sovereignScopeHeadHash
      now <- liftIO getCurrentTime
      liftIO $
        DB.execute
          db
          "INSERT INTO sovereign_checkpoints (scope_id, epoch, event_count, head_hash, signature, peer_key, peer_signature, created_at) VALUES (?, ?, ?, ?, ?, NULL, NULL, ?)"
          ( Binary $ sovereignScopeIdBytes scopeId,
            sovereignScopeEpoch,
            sovereignScopeNextSequence,
            Binary $ sovereignHashBytes sovereignScopeHeadHash,
            Binary signature,
            now
          )
      let checkpoint =
            SovereignCheckpoint
              { sovereignCheckpointScopeId = scopeId,
                sovereignCheckpointEpoch = sovereignScopeEpoch,
                sovereignCheckpointEventCount = sovereignScopeNextSequence,
                sovereignCheckpointHeadHash = sovereignScopeHeadHash,
                sovereignCheckpointSignature = signature,
                sovereignCheckpointPeerKey = Nothing,
                sovereignCheckpointPeerSignature = Nothing,
                sovereignCheckpointCreatedAt = now
              }
      unless (verifySovereignCheckpoint sovereignScopePublicKey scopeId sovereignScopeEpoch sovereignScopeNextSequence sovereignScopeHeadHash signature) $
        rollback $ SERCorruptStore "new checkpoint signature did not verify"
      pure checkpoint
  where
    verifyCheckpointOrThrow SovereignScope {sovereignScopePublicKey} SovereignCheckpoint {sovereignCheckpointScopeId, sovereignCheckpointEpoch, sovereignCheckpointEventCount, sovereignCheckpointHeadHash, sovereignCheckpointSignature} =
      unless (verifySovereignCheckpoint sovereignScopePublicKey sovereignCheckpointScopeId sovereignCheckpointEpoch sovereignCheckpointEventCount sovereignCheckpointHeadHash sovereignCheckpointSignature) $
        throwE $ SERCorruptStore "invalid local checkpoint signature"

sovereignReadScope :: DBStore -> SovereignScopeId -> IO (Either SovereignError SovereignScope)
sovereignReadScope store scopeId = withTransaction store $ \db -> runExceptT $ publicScope <$> getScopeStateTx db False scopeId

sovereignListScopes :: DBStore -> Int64 -> Int -> IO (Either SovereignError [SovereignScope])
sovereignListScopes store userId limit = withTransaction store $ \db -> runExceptT $ do
  checkLimit limit
  rows <- liftIO $ DB.query db (scopeSelect <> " WHERE user_id = ? ORDER BY updated_at DESC, scope_id LIMIT ?") (userId, limit)
  mapM (fmap publicScope . decodeScopeRow) rows

sovereignReadEvents :: DBStore -> SovereignScopeId -> Int64 -> Int -> IO (Either SovereignError [SovereignEvent])
sovereignReadEvents store scopeId startSequence limit = withTransaction store $ \db -> runExceptT $ do
  checkLimit limit
  when (startSequence < 0) $ throwE $ SERInvalidRange "start_sequence" startSequence
  ScopeState {publicScope = scope@SovereignScope {sovereignScopeEpoch, sovereignScopeKind, sovereignScopePolicyHash, sovereignScopePublicKey}} <- getScopeStateTx db False scopeId
  expectedPreviousHash <-
    if startSequence == 0
      then liftEither $ sovereignGenesisHash scopeId sovereignScopeKind sovereignScopeEpoch sovereignScopePolicyHash sovereignScopePublicKey
      else do
        prior :: [Only (Binary ByteString)] <- liftIO $ DB.query db "SELECT event_hash FROM sovereign_events WHERE scope_id = ? AND epoch = ? AND sequence_no = ?" (Binary $ sovereignScopeIdBytes scopeId, sovereignScopeEpoch, startSequence - 1)
        case prior of
          [Only (Binary bs)] -> liftEither $ mkSovereignHash bs
          _ -> throwE $ SERMissingPreviousEvent $ startSequence - 1
  rows :: [EventRow] <-
    liftIO $
      DB.query
        db
        "SELECT sequence_no, event_payload, nonce, time_bucket, previous_hash, event_hash, created_at FROM sovereign_events WHERE scope_id = ? AND epoch = ? AND sequence_no >= ? ORDER BY sequence_no LIMIT ?"
        (Binary $ sovereignScopeIdBytes scopeId, sovereignScopeEpoch, startSequence, limit)
  events <- mapM (decodeEventRow scopeId sovereignScopeEpoch) rows
  _ <- liftEither $ verifySovereignChain expectedPreviousHash startSequence events
  pure events

sovereignReadCheckpoints :: DBStore -> SovereignScopeId -> Int -> IO (Either SovereignError [SovereignCheckpoint])
sovereignReadCheckpoints store scopeId limit = withTransaction store $ \db -> runExceptT $ do
  checkLimit limit
  ScopeState {publicScope = scope@SovereignScope {sovereignScopeEpoch}} <- getScopeStateTx db False scopeId
  rows :: [CheckpointRow] <-
    liftIO $
      DB.query
        db
        "SELECT event_count, head_hash, signature, peer_key, peer_signature, created_at FROM sovereign_checkpoints WHERE scope_id = ? AND epoch = ? ORDER BY event_count DESC LIMIT ?"
        (Binary $ sovereignScopeIdBytes scopeId, sovereignScopeEpoch, limit)
  checkpoints <- mapM (decodeCheckpointRow scopeId sovereignScopeEpoch) rows
  mapM_ (verifyReadCheckpoint scope) checkpoints
  pure $ sortOn sovereignCheckpointEventCount checkpoints
  where
    verifyReadCheckpoint SovereignScope {sovereignScopePublicKey} SovereignCheckpoint {sovereignCheckpointScopeId, sovereignCheckpointEpoch, sovereignCheckpointEventCount, sovereignCheckpointHeadHash, sovereignCheckpointSignature} =
      unless (verifySovereignCheckpoint sovereignScopePublicKey sovereignCheckpointScopeId sovereignCheckpointEpoch sovereignCheckpointEventCount sovereignCheckpointHeadHash sovereignCheckpointSignature) $
        throwE $ SERCorruptStore "invalid checkpoint signature"

getScopeStateTx :: DB.Connection -> Bool -> SovereignScopeId -> ExceptT SovereignError IO ScopeState
getScopeStateTx db lock scopeId = do
  rows :: [ScopeRow] <- liftIO $ DB.query db query (Only $ Binary $ sovereignScopeIdBytes scopeId)
  case rows of
    [row] -> liftEither $ decodeScopeRow row
    [] -> throwE SERScopeNotFound
    _ -> throwE $ SERCorruptStore "duplicate scope row"
  where
    query = scopeSelect <> " WHERE scope_id = ?" <> lockSuffix lock

lockSuffix :: Bool -> Query
#if defined(dbPostgres)
lockSuffix True = " FOR UPDATE"
#else
lockSuffix True = ""
#endif
lockSuffix False = ""

decodeScopeRow :: ScopeRow -> Either SovereignError ScopeState
decodeScopeRow ((Binary scopeIdBytes, userId, contactId, kindTag, epoch, Binary policyHashBytes, publicKey, privateKey) :. (nextSequence, Binary headHashBytes, BI active, createdAt, updatedAt)) = do
  scopeId <- mkSovereignScopeId scopeIdBytes
  scopeKind <- sovereignScopeKindFromTag kindTag
  policyHash <- mkSovereignHash policyHashBytes
  headHash <- mkSovereignHash headHashBytes
  when (epoch < 0 || epoch > 0xffffffff) $ Left $ SERCorruptStore "invalid epoch"
  when (nextSequence < 0) $ Left $ SERCorruptStore "negative next sequence"
  when (C.publicKey privateKey /= publicKey) $ Left $ SERCorruptStore "checkpoint key pair mismatch"
  when (scopeKind == SSKDevice && contactId /= Nothing) $ Left $ SERCorruptStore "device scope has contact"
  when (scopeKind == SSKContact && contactId == Nothing) $ Left $ SERCorruptStore "contact scope has no contact"
  let publicScope =
        SovereignScope
          { sovereignScopeId = scopeId,
            sovereignScopeUserId = userId,
            sovereignScopeContactId = contactId,
            sovereignScopeKind = scopeKind,
            sovereignScopeEpoch = epoch,
            sovereignScopePolicyHash = policyHash,
            sovereignScopePublicKey = publicKey,
            sovereignScopeNextSequence = nextSequence,
            sovereignScopeHeadHash = headHash,
            sovereignScopeActive = active,
            sovereignScopeCreatedAt = createdAt,
            sovereignScopeUpdatedAt = updatedAt
          }
  pure ScopeState {publicScope, privateCheckpointKey = privateKey}

decodeEventRow :: SovereignScopeId -> Int64 -> EventRow -> ExceptT SovereignError IO SovereignEvent
decodeEventRow scopeId epoch (sequenceNo, Binary payload, Binary nonceBytes, timeBucket, Binary previousHashBytes, Binary eventHashBytes, createdAt) = do
  eventData <- liftEither $ decodeSovereignEventData payload
  nonce <- liftEither $ mkSovereignNonce nonceBytes
  previousHash <- liftEither $ mkSovereignHash previousHashBytes
  eventHash <- liftEither $ mkSovereignHash eventHashBytes
  pure
    SovereignEvent
      { sovereignEventScopeId = scopeId,
        sovereignEventEpoch = epoch,
        sovereignEventSequence = sequenceNo,
        sovereignEventData = eventData,
        sovereignEventNonce = nonce,
        sovereignEventTimeBucket = timeBucket,
        sovereignEventPreviousHash = previousHash,
        sovereignEventHashValue = eventHash,
        sovereignEventCreatedAt = createdAt
      }

decodeCheckpointRow :: SovereignScopeId -> Int64 -> CheckpointRow -> ExceptT SovereignError IO SovereignCheckpoint
decodeCheckpointRow scopeId epoch (eventCount, Binary headHashBytes, Binary signature, peerKey, peerSignature, createdAt) = do
  headHash <- liftEither $ mkSovereignHash headHashBytes
  unless (B.length signature == 64) $ throwE $ SERCorruptStore "invalid checkpoint signature size"
  pure
    SovereignCheckpoint
      { sovereignCheckpointScopeId = scopeId,
        sovereignCheckpointEpoch = epoch,
        sovereignCheckpointEventCount = eventCount,
        sovereignCheckpointHeadHash = headHash,
        sovereignCheckpointSignature = signature,
        sovereignCheckpointPeerKey = fromBinary <$> peerKey,
        sovereignCheckpointPeerSignature = fromBinary <$> peerSignature,
        sovereignCheckpointCreatedAt = createdAt
      }

checkpointAtTx :: DB.Connection -> SovereignScope -> Int64 -> ExceptT SovereignError IO (Maybe SovereignCheckpoint)
checkpointAtTx db SovereignScope {sovereignScopeId, sovereignScopeEpoch} eventCount = do
  rows :: [CheckpointRow] <-
    liftIO $
      DB.query
        db
        "SELECT event_count, head_hash, signature, peer_key, peer_signature, created_at FROM sovereign_checkpoints WHERE scope_id = ? AND epoch = ? AND event_count = ?"
        (Binary $ sovereignScopeIdBytes sovereignScopeId, sovereignScopeEpoch, eventCount)
  case rows of
    [] -> pure Nothing
    [row] -> Just <$> decodeCheckpointRow sovereignScopeId sovereignScopeEpoch row
    _ -> throwE $ SERCorruptStore "duplicate checkpoint row"

checkLimit :: Int -> ExceptT SovereignError IO ()
checkLimit n
  | n >= 1 && n <= 1000 = pure ()
  | otherwise = throwE $ SERInvalidReadLimit n

runWrite :: DBStore -> (DB.Connection -> ExceptT SovereignError IO a) -> IO (Either SovereignError a)
runWrite store action =
  E.catch
    (withTransaction store $ \db -> runExceptT $ action db)
    (\(SovereignRollback e) -> pure $ Left e)

-- `throwE` is safe before the first mutation. After a mutation this exception
-- must be used so both sqlite-simple and postgresql-simple roll back rather
-- than commit an `ExceptT Left` value.
rollback :: SovereignError -> ExceptT SovereignError IO a
rollback = liftIO . E.throwIO . SovereignRollback

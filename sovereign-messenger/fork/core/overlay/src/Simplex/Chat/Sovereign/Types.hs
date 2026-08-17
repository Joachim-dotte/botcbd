{-# LANGUAGE CPP #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}

#if defined(SOVEREIGN_PEER_ANCHOR_UNIMPLEMENTED)
#error "sovereign-peer-anchor is intentionally unavailable: implement and audit the complete peer protocol before enabling it"
#endif

module Simplex.Chat.Sovereign.Types
  ( SovereignScopeId,
    SovereignHash,
    SovereignNonce,
    SovereignScopeKind (..),
    SovereignEventKind (..),
    SovereignEventData (..),
    SovereignEvent (..),
    SovereignCheckpoint (..),
    SovereignScope (..),
    SovereignError (..),
    mkSovereignScopeId,
    mkSovereignHash,
    mkSovereignNonce,
    sovereignScopeIdBytes,
    sovereignHashBytes,
    sovereignNonceBytes,
    sovereignScopeKindTag,
    sovereignScopeKindFromTag,
    encodeSovereignEventData,
    decodeSovereignEventData,
    sovereignGenesisPreimage,
    sovereignGenesisHash,
    sovereignEventPreimage,
    sovereignEventHash,
    sovereignCheckpointPreimage,
    signSovereignCheckpoint,
    verifySovereignCheckpoint,
    verifySovereignChain,
  )
where

import Control.Monad (foldM, unless, when)
import qualified Data.ByteString as B
import Data.ByteString (ByteString)
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy as LB
import Data.Int (Int64)
import Data.Time.Clock (UTCTime)
import Data.Word (Word16, Word32, Word64, Word8)
import qualified Simplex.Messaging.Crypto as C

newtype SovereignScopeId = SovereignScopeId ByteString
  deriving (Eq, Ord, Show)

newtype SovereignHash = SovereignHash ByteString
  deriving (Eq, Ord, Show)

newtype SovereignNonce = SovereignNonce ByteString
  deriving (Eq, Ord, Show)

data SovereignScopeKind = SSKDevice | SSKContact
  deriving (Bounded, Enum, Eq, Ord, Show)

-- Keep this vocabulary closed. New cases require a new format version or a
-- backwards-compatible tag allocation; never add a free-form constructor.
data SovereignEventKind
  = SEKScopeCreated
  | SEKContactPaired
  | SEKAttestationAccepted
  | SEKSafetyNumberVerified
  | SEKPolicyChanged
  | SEKSessionReset
  | SEKContactRevoked
  deriving (Bounded, Enum, Eq, Ord, Show)

data SovereignEventData = SovereignEventData
  { sovereignEventKind :: SovereignEventKind,
    sovereignEventState :: Word8,
    sovereignEventFlags :: Word16,
    sovereignEvidenceHash :: Maybe SovereignHash
  }
  deriving (Eq, Show)

data SovereignEvent = SovereignEvent
  { sovereignEventScopeId :: SovereignScopeId,
    sovereignEventEpoch :: Int64,
    sovereignEventSequence :: Int64,
    sovereignEventData :: SovereignEventData,
    sovereignEventNonce :: SovereignNonce,
    sovereignEventTimeBucket :: Int64,
    sovereignEventPreviousHash :: SovereignHash,
    sovereignEventHashValue :: SovereignHash,
    sovereignEventCreatedAt :: UTCTime
  }
  deriving (Eq, Show)

data SovereignCheckpoint = SovereignCheckpoint
  { sovereignCheckpointScopeId :: SovereignScopeId,
    sovereignCheckpointEpoch :: Int64,
    sovereignCheckpointEventCount :: Int64,
    sovereignCheckpointHeadHash :: SovereignHash,
    sovereignCheckpointSignature :: ByteString,
    sovereignCheckpointPeerKey :: Maybe ByteString,
    sovereignCheckpointPeerSignature :: Maybe ByteString,
    sovereignCheckpointCreatedAt :: UTCTime
  }
  deriving (Eq, Show)

-- Deliberately excludes the private checkpoint key.
data SovereignScope = SovereignScope
  { sovereignScopeId :: SovereignScopeId,
    sovereignScopeUserId :: Int64,
    sovereignScopeContactId :: Maybe Int64,
    sovereignScopeKind :: SovereignScopeKind,
    sovereignScopeEpoch :: Int64,
    sovereignScopePolicyHash :: SovereignHash,
    sovereignScopePublicKey :: C.PublicKeyEd25519,
    sovereignScopeNextSequence :: Int64,
    sovereignScopeHeadHash :: SovereignHash,
    sovereignScopeActive :: Bool,
    sovereignScopeCreatedAt :: UTCTime,
    sovereignScopeUpdatedAt :: UTCTime
  }
  deriving (Eq, Show)

data SovereignError
  = SERInvalidLength String Int Int
  | SERInvalidRange String Int64
  | SERInvalidTag String Int
  | SERNonCanonicalPayload
  | SERScopeNotFound
  | SERScopeInactive
  | SERCorruptStore String
  | SERInvalidReadLimit Int
  | SERMissingPreviousEvent Int64
  deriving (Eq, Show)

mkSovereignScopeId :: ByteString -> Either SovereignError SovereignScopeId
mkSovereignScopeId = fixed "scope_id" 32 SovereignScopeId

mkSovereignHash :: ByteString -> Either SovereignError SovereignHash
mkSovereignHash = fixed "hash" 32 SovereignHash

mkSovereignNonce :: ByteString -> Either SovereignError SovereignNonce
mkSovereignNonce = fixed "nonce" 16 SovereignNonce

fixed :: String -> Int -> (ByteString -> a) -> ByteString -> Either SovereignError a
fixed label size wrap bs
  | B.length bs == size = Right $ wrap bs
  | otherwise = Left $ SERInvalidLength label size (B.length bs)

sovereignScopeIdBytes :: SovereignScopeId -> ByteString
sovereignScopeIdBytes (SovereignScopeId bs) = bs

sovereignHashBytes :: SovereignHash -> ByteString
sovereignHashBytes (SovereignHash bs) = bs

sovereignNonceBytes :: SovereignNonce -> ByteString
sovereignNonceBytes (SovereignNonce bs) = bs

sovereignScopeKindTag :: SovereignScopeKind -> Word8
sovereignScopeKindTag SSKDevice = 1
sovereignScopeKindTag SSKContact = 2

sovereignScopeKindFromTag :: Int64 -> Either SovereignError SovereignScopeKind
sovereignScopeKindFromTag 1 = Right SSKDevice
sovereignScopeKindFromTag 2 = Right SSKContact
sovereignScopeKindFromTag n = Left $ SERInvalidTag "scope_kind" (fromIntegral n)

eventKindTag :: SovereignEventKind -> Word8
eventKindTag k = fromIntegral (fromEnum k + 1)

eventKindFromTag :: Word8 -> Either SovereignError SovereignEventKind
eventKindFromTag n
  | n >= 1 && n <= fromIntegral (fromEnum (maxBound :: SovereignEventKind) + 1) = Right $ toEnum (fromIntegral n - 1)
  | otherwise = Left $ SERInvalidTag "event_kind" (fromIntegral n)

-- Exactly 37 bytes. An absent evidence hash has a zero presence byte and a
-- zero-filled hash slot; the decoder rejects all alternative encodings.
encodeSovereignEventData :: SovereignEventData -> ByteString
encodeSovereignEventData SovereignEventData {sovereignEventKind, sovereignEventState, sovereignEventFlags, sovereignEvidenceHash} =
  strictBuilder $
    BB.word8 (eventKindTag sovereignEventKind)
      <> BB.word8 sovereignEventState
      <> BB.word16BE sovereignEventFlags
      <> maybe (BB.word8 0 <> BB.byteString zeroHash) (\h -> BB.word8 1 <> BB.byteString (sovereignHashBytes h)) sovereignEvidenceHash

decodeSovereignEventData :: ByteString -> Either SovereignError SovereignEventData
decodeSovereignEventData bs = do
  unless (B.length bs == 37) $ Left $ SERInvalidLength "event_payload" 37 (B.length bs)
  sovereignEventKind <- eventKindFromTag $ B.index bs 0
  let sovereignEventState = B.index bs 1
      sovereignEventFlags = fromIntegral (B.index bs 2) * 256 + fromIntegral (B.index bs 3)
      present = B.index bs 4
      evidence = B.drop 5 bs
  sovereignEvidenceHash <- case present of
    0 -> Nothing <$ unless (evidence == zeroHash) (Left SERNonCanonicalPayload)
    1 -> Just <$> mkSovereignHash evidence
    n -> Left $ SERInvalidTag "evidence_present" (fromIntegral n)
  pure SovereignEventData {sovereignEventKind, sovereignEventState, sovereignEventFlags, sovereignEvidenceHash}

sovereignGenesisPreimage :: SovereignScopeId -> SovereignScopeKind -> Int64 -> SovereignHash -> C.PublicKeyEd25519 -> Either SovereignError ByteString
sovereignGenesisPreimage scopeId scopeKind epoch policyHash publicKey = do
  epoch' <- word32 "epoch" epoch
  pure . strictBuilder $
    BB.byteString "SOVEREIGN-GENESIS-V1\0"
      <> BB.byteString (sovereignScopeIdBytes scopeId)
      <> BB.word8 (sovereignScopeKindTag scopeKind)
      <> BB.word32BE epoch'
      <> BB.byteString (sovereignHashBytes policyHash)
      <> BB.byteString (C.pubKeyBytes publicKey)

sovereignGenesisHash :: SovereignScopeId -> SovereignScopeKind -> Int64 -> SovereignHash -> C.PublicKeyEd25519 -> Either SovereignError SovereignHash
sovereignGenesisHash scopeId scopeKind epoch policyHash publicKey =
  SovereignHash . C.sha256Hash <$> sovereignGenesisPreimage scopeId scopeKind epoch policyHash publicKey

sovereignEventPreimage :: SovereignScopeId -> Int64 -> Int64 -> SovereignHash -> SovereignEventData -> Int64 -> SovereignNonce -> Either SovereignError ByteString
sovereignEventPreimage scopeId epoch sequenceNo previousHash eventData timeBucket nonce = do
  epoch' <- word32 "epoch" epoch
  sequenceNo' <- word64 "sequence" sequenceNo
  timeBucket' <- word64 "time_bucket" timeBucket
  pure . strictBuilder $
    BB.byteString "SOVEREIGN-EVENT-V1\0"
      <> BB.byteString (sovereignScopeIdBytes scopeId)
      <> BB.word32BE epoch'
      <> BB.word64BE sequenceNo'
      <> BB.byteString (sovereignHashBytes previousHash)
      <> BB.byteString (encodeSovereignEventData eventData)
      <> BB.word64BE timeBucket'
      <> BB.byteString (sovereignNonceBytes nonce)

sovereignEventHash :: SovereignScopeId -> Int64 -> Int64 -> SovereignHash -> SovereignEventData -> Int64 -> SovereignNonce -> Either SovereignError SovereignHash
sovereignEventHash scopeId epoch sequenceNo previousHash eventData timeBucket nonce =
  SovereignHash . C.sha256Hash <$> sovereignEventPreimage scopeId epoch sequenceNo previousHash eventData timeBucket nonce

sovereignCheckpointPreimage :: SovereignScopeId -> Int64 -> Int64 -> SovereignHash -> Either SovereignError ByteString
sovereignCheckpointPreimage scopeId epoch eventCount headHash = do
  epoch' <- word32 "epoch" epoch
  eventCount' <- word64 "event_count" eventCount
  pure . strictBuilder $
    BB.byteString "SOVEREIGN-CHECKPOINT-V1\0"
      <> BB.byteString (sovereignScopeIdBytes scopeId)
      <> BB.word32BE epoch'
      <> BB.word64BE eventCount'
      <> BB.byteString (sovereignHashBytes headHash)

signSovereignCheckpoint :: C.PrivateKeyEd25519 -> SovereignScopeId -> Int64 -> Int64 -> SovereignHash -> Either SovereignError ByteString
signSovereignCheckpoint privateKey scopeId epoch eventCount headHash =
  C.signatureBytes . C.sign' privateKey <$> sovereignCheckpointPreimage scopeId epoch eventCount headHash

verifySovereignCheckpoint :: C.PublicKeyEd25519 -> SovereignScopeId -> Int64 -> Int64 -> SovereignHash -> ByteString -> Bool
verifySovereignCheckpoint publicKey scopeId epoch eventCount headHash signature =
  case (sovereignCheckpointPreimage scopeId epoch eventCount headHash, C.decodeSignature signature) of
    (Right preimage, Right sig) -> C.verify' publicKey sig preimage
    _ -> False

verifySovereignChain :: SovereignHash -> Int64 -> [SovereignEvent] -> Either SovereignError SovereignHash
verifySovereignChain initialHash initialSequence events = snd <$> foldM verifyOne (initialSequence, initialHash) events
  where
    verifyOne (expectedSequence, expectedPreviousHash) SovereignEvent {sovereignEventScopeId, sovereignEventEpoch, sovereignEventSequence, sovereignEventData, sovereignEventNonce, sovereignEventTimeBucket, sovereignEventPreviousHash, sovereignEventHashValue}
      | sovereignEventSequence /= expectedSequence = Left $ SERCorruptStore "non-contiguous event sequence"
      | sovereignEventPreviousHash /= expectedPreviousHash = Left $ SERCorruptStore "broken previous hash"
      | otherwise = do
          computed <- sovereignEventHash sovereignEventScopeId sovereignEventEpoch sovereignEventSequence sovereignEventPreviousHash sovereignEventData sovereignEventTimeBucket sovereignEventNonce
          when (computed /= sovereignEventHashValue) $ Left $ SERCorruptStore "event hash mismatch"
          pure (expectedSequence + 1, computed)

strictBuilder :: BB.Builder -> ByteString
strictBuilder = LB.toStrict . BB.toLazyByteString

word32 :: String -> Int64 -> Either SovereignError Word32
word32 label n
  | n >= 0 && n <= 0xffffffff = Right $ fromIntegral n
  | otherwise = Left $ SERInvalidRange label n

word64 :: String -> Int64 -> Either SovereignError Word64
word64 label n
  | n >= 0 = Right $ fromIntegral n
  | otherwise = Left $ SERInvalidRange label n

zeroHash :: ByteString
zeroHash = B.replicate 32 0

{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}

module SovereignRegistryTests
  ( sovereignRegistryTests,
    sovereignRegistryStoreTests,
  )
where

import ChatClient (TestCC (..), TestParams, withNewTestChat)
import qualified ChatTests.Utils as CTU
import Control.Concurrent.Async (concurrently)
import Control.Concurrent.STM (atomically)
import qualified Crypto.Error as CE
import qualified Crypto.PubKey.Ed25519 as Ed25519
import qualified Data.ByteString as B
import Data.Either (isLeft)
import Data.List (sort)
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime (..))
import Data.Word (Word8)
import Simplex.Chat.Controller (ChatController (..))
import Simplex.Chat.Sovereign.Types
import Simplex.Chat.Store.Sovereign
import Simplex.Chat.Types (User (..))
import qualified Simplex.Messaging.Crypto as C
import Test.Hspec

sovereignRegistryTests :: Spec
sovereignRegistryTests = do
  describe "deterministic v1 encoding" $ do
    it "matches the genesis vector" $ do
      scopeId <- mustRight $ mkSovereignScopeId $ B.pack [0 .. 31]
      policyHash <- mustRight $ mkSovereignHash $ B.pack [0x40 .. 0x5f]
      publicKey <- mustRight $ rawEd25519PublicKey rfc8032PublicKey
      genesisHash <- mustRight $ sovereignGenesisHash scopeId SSKContact 7 policyHash publicKey
      sovereignHashBytes genesisHash `shouldBe` hexBytes "6f6437f607ec6b1a2ee6c05b5454c0f53b5c70c50fd2a2f8f4882c57c9c768e9"
    it "matches the event and checkpoint vectors" $ do
      scopeId <- mustRight $ mkSovereignScopeId $ B.pack [0 .. 31]
      previousHash <- mustRight $ mkSovereignHash $ B.pack [0x20 .. 0x3f]
      evidenceHash <- mustRight $ mkSovereignHash $ B.pack [0xa0 .. 0xbf]
      nonce <- mustRight $ mkSovereignNonce $ B.pack [0xf0 .. 0xff]
      let eventData = SovereignEventData SEKAttestationAccepted 2 0x0102 (Just evidenceHash)
      eventHash <- mustRight $ sovereignEventHash scopeId 7 42 previousHash eventData 123456789 nonce
      sovereignHashBytes eventHash `shouldBe` hexBytes "79e9567bcf5c7ac3d1ef4f75e3ce3d7ca318fa5d597f80c4f2efee181db95d70"
      checkpoint <- mustRight $ sovereignCheckpointPreimage scopeId 7 43 eventHash
      C.sha256Hash checkpoint `shouldBe` hexBytes "fb30c3571cdb91e57687b76140cf8ace1a971fc7c0eaac5f5fce8ae2571c5fcc"
    it "rejects a non-canonical absent evidence slot" $ do
      let malformed = B.pack [1, 0, 0, 0, 0] <> B.replicate 31 0 <> B.singleton 1
      decodeSovereignEventData malformed `shouldBe` Left SERNonCanonicalPayload
  describe "chain and checkpoint verification" $ do
    it "detects event tampering" $ do
      scopeId <- mustRight $ mkSovereignScopeId $ B.replicate 32 1
      previousHash <- mustRight $ mkSovereignHash $ B.replicate 32 2
      nonce <- mustRight $ mkSovereignNonce $ B.replicate 16 3
      let eventData = SovereignEventData SEKPolicyChanged 1 0 Nothing
      eventHash <- mustRight $ sovereignEventHash scopeId 1 0 previousHash eventData 100 nonce
      let event = SovereignEvent scopeId 1 0 eventData nonce 100 previousHash eventHash epochTime
      verifySovereignChain previousHash 0 [event] `shouldBe` Right eventHash
      wrongHash <- mustRight $ mkSovereignHash $ B.replicate 32 9
      verifySovereignChain previousHash 0 [event {sovereignEventHashValue = wrongHash}] `shouldSatisfy` isLeft
    it "signs and verifies checkpoints with Ed25519" $ do
      random <- C.newRandom
      (publicKey, privateKey) <- atomically (C.generateKeyPair random) :: IO C.KeyPairEd25519
      scopeId <- mustRight $ mkSovereignScopeId $ B.replicate 32 4
      headHash <- mustRight $ mkSovereignHash $ B.replicate 32 5
      signature <- mustRight $ signSovereignCheckpoint privateKey scopeId 3 8 headHash
      verifySovereignCheckpoint publicKey scopeId 3 8 headHash signature `shouldBe` True
      verifySovereignCheckpoint publicKey scopeId 3 9 headHash signature `shouldBe` False

sovereignRegistryStoreTests :: SpecWith TestParams
sovereignRegistryStoreTests =
  CTU.it "commits concurrent appends and an idempotent checkpoint atomically" $ \params ->
    withNewTestChat params "sovereign_registry" CTU.aliceProfile $ \client ->
      CTU.withCCUser client $ \User {userId} -> do
        random <- C.newRandom
        (publicKey, privateKey) <- atomically (C.generateKeyPair random) :: IO C.KeyPairEd25519
        scopeId <- mustRight $ mkSovereignScopeId $ B.replicate 32 0x11
        policyHash <- mustRight $ mkSovereignHash $ B.replicate 32 0x22
        nonce1 <- mustRight $ mkSovereignNonce $ B.replicate 16 0x31
        nonce2 <- mustRight $ mkSovereignNonce $ B.replicate 16 0x32
        let store = chatStore $ chatController client
            eventData1 = SovereignEventData SEKContactPaired 1 0 Nothing
            eventData2 = SovereignEventData SEKSafetyNumberVerified 1 0 Nothing
        created <- sovereignCreateScope store scopeId userId Nothing SSKDevice 1 policyHash publicKey privateKey >>= mustRight
        sovereignScopeNextSequence created `shouldBe` 0
        (result1, result2) <- concurrently (sovereignAppend store scopeId eventData1 nonce1 100) (sovereignAppend store scopeId eventData2 nonce2 101)
        event1 <- mustRight result1
        event2 <- mustRight result2
        sort [sovereignEventSequence event1, sovereignEventSequence event2] `shouldBe` [0, 1]
        events <- sovereignReadEvents store scopeId 0 10 >>= mustRight
        map sovereignEventSequence events `shouldBe` [0, 1]
        checkpoint1 <- sovereignCreateCheckpoint store scopeId >>= mustRight
        checkpoint2 <- sovereignCreateCheckpoint store scopeId >>= mustRight
        checkpoint2 `shouldBe` checkpoint1
        sovereignCheckpointEventCount checkpoint1 `shouldBe` 2
        checkpoints <- sovereignReadCheckpoints store scopeId 10 >>= mustRight
        checkpoints `shouldBe` [checkpoint1]

mustRight :: Show e => Either e a -> IO a
mustRight = either (fail . show) pure

hexBytes :: String -> B.ByteString
hexBytes [] = B.empty
hexBytes (a : b : rest) = B.cons (hexByte a b) $ hexBytes rest
hexBytes _ = error "odd hex vector"

hexByte :: Char -> Char -> Word8
hexByte a b = 16 * digit a + digit b
  where
    digit c
      | c >= '0' && c <= '9' = fromIntegral $ fromEnum c - fromEnum '0'
      | c >= 'a' && c <= 'f' = fromIntegral $ fromEnum c - fromEnum 'a' + 10
      | otherwise = error "invalid hex vector"

rfc8032PublicKey :: B.ByteString
rfc8032PublicKey = hexBytes "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"

rawEd25519PublicKey :: B.ByteString -> Either String C.PublicKeyEd25519
rawEd25519PublicKey = fmap C.PublicKeyEd25519 . either (Left . show) Right . CE.eitherCryptoError . Ed25519.publicKey

epochTime :: UTCTime
epochTime = UTCTime (fromGregorian 1970 1 1) 0

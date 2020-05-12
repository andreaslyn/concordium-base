{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE DerivingVia #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE DerivingStrategies #-}
{-# OPTIONS_GHC -Wall #-}
module Concordium.Types (module Concordium.Types, AccountAddress(..), SchemeId, AccountVerificationKey) where

import GHC.Generics
import Data.Data(Typeable, Data)

import qualified Concordium.Crypto.BlockSignature as Sig
import qualified Concordium.Crypto.SHA256 as Hash
import qualified Concordium.Crypto.VRF as VRF
import qualified Concordium.Crypto.BlsSignature as Bls
import Concordium.ID.Types
import Concordium.Crypto.SignatureScheme(SchemeId)
import Concordium.Types.HashableTo
import Concordium.Types.Acorn.NumericTypes

import Control.Exception(assert)

import Data.Hashable(Hashable)
import Data.Word
import Data.ByteString.Char8(ByteString)
import qualified Data.ByteString.Short as BSS
import qualified Data.ByteString.Lazy.Char8 as BSL
import Data.ByteString.Builder(toLazyByteString, byteStringHex)
import Data.Bits
import Data.Ratio
import qualified Data.Set as Set
import Data.Set(Set)

import qualified Data.PQueue.Prio.Max as Queue

import Data.Aeson as AE
import Data.Aeson.TH

import Data.Time
import Data.Time.Clock.POSIX

import qualified Data.Serialize as S
import qualified Data.Serialize.Put as P
import qualified Data.Serialize.Get as G
import Database.Persist.Class
import Database.Persist.Sql

import Lens.Micro.Platform

data Hashed a = Hashed {unhashed :: a, hashed :: Hash.Hash}

instance HashableTo Hash.Hash (Hashed a) where
    getHash = hashed

makeHashed :: HashableTo Hash.Hash a => a -> Hashed a
makeHashed v = Hashed v (getHash v)

instance Eq (Hashed a) where
    a == b = hashed a == hashed b

instance Ord (Hashed a) where
    compare a b = compare (hashed a) (hashed b)

-- * Types releated to bakers.
newtype BakerId = BakerId Word64
    deriving (Eq, Ord, Num, Enum, Bounded, Real, Hashable, Read, Show, Integral, FromJSON, ToJSON) via Word64

instance S.Serialize BakerId where
    get = BakerId <$> G.getWord64be
    put (BakerId i) = P.putWord64be i

type LeadershipElectionNonce = Hash.Hash
type BakerSignVerifyKey = Sig.VerifyKey
type BakerSignPrivateKey = Sig.KeyPair
type BakerElectionVerifyKey = VRF.PublicKey
type BakerElectionPrivateKey = VRF.KeyPair
type BakerAggregationVerifyKey = Bls.PublicKey
type BakerAggregationPrivateKey = Bls.SecretKey
type BakerAggregationProof = Bls.Proof
type LotteryPower = Ratio Amount

-- | The type of the birk parameter "election difficulty".
-- The value must be in the range [0,1).
type ElectionDifficulty = Double
type FinalizationCommitteeSize = Word32

isValidElectionDifficulty :: ElectionDifficulty -> Bool
isValidElectionDifficulty d = d >= 0 && d < 1

type VoterId = Word64
type VoterVerificationKey = Sig.VerifyKey
type VoterVRFPublicKey = VRF.PublicKey
type VoterAggregationVerifyKey = Bls.PublicKey
type VoterSignKey = Sig.SignKey
type VoterAggregationPrivateKey = Bls.SecretKey
newtype VoterPower = VoterPower AmountUnit
    deriving newtype (Eq, Ord, Num, Enum, Bounded, Real, Show, Integral, S.Serialize)

-- * Blockchain specific types.
-- Eventually these will be replaced by types given by the global store.
-- For now they are placeholders

newtype ContractIndex = ContractIndex Word64
    deriving newtype (Eq, Ord, Num, Enum, Bounded, Real, Hashable, Show, Bits, Integral)
    deriving (Typeable, Data)

instance S.Serialize ContractIndex where
    get = ContractIndex <$> G.getWord64be
    put (ContractIndex i) = P.putWord64be i

newtype ContractSubindex = ContractSubindex Word64
    deriving newtype (Eq, Ord, Num, Enum, Bounded, Real, Hashable, Show, Integral)
    deriving (Typeable, Data)

instance S.Serialize ContractSubindex where
    get = ContractSubindex <$> G.getWord64be
    put (ContractSubindex i) = P.putWord64be i

data ContractAddress = ContractAddress { contractIndex :: !ContractIndex
                                       , contractSubindex :: !ContractSubindex}
    deriving(Eq, Ord, Generic, Typeable, Data)

instance FromJSON ContractAddress where
  parseJSON = withObject "ContractAddress" $ \v -> do
    i <- v .: "index"
    j <- v .: "subindex"
    return $ ContractAddress (fromIntegral (i :: Word64)) (fromIntegral (j :: Word64))

instance ToJSON ContractAddress where
  toJSON (ContractAddress i j) =
    object ["index" AE..= (fromIntegral i :: Word64), "subindex" AE..= (fromIntegral j :: Word64)]
  toEncoding (ContractAddress i j) =
    pairs ("index" AE..= (fromIntegral i :: Word64) <> "subindex" AE..= (fromIntegral j :: Word64))

instance Hashable ContractAddress

instance Show ContractAddress where
  show (ContractAddress i v) = "<" ++ show i ++ ", " ++ show v ++ ">"

instance S.Serialize ContractAddress where
  get = ContractAddress <$> S.get <*> S.get
  put (ContractAddress i v) = S.put i <> S.put v

-- |Unique module reference.
newtype ModuleRef = ModuleRef {moduleRef :: Hash.Hash}
    deriving(Eq, Ord, Hashable, Typeable, Data)
    deriving (FromJSON, ToJSON) via Hash.Hash

instance Show ModuleRef where
  show (ModuleRef m) = show m

instance S.Serialize ModuleRef where
  get = getModuleRef
  put = putModuleRef

getModuleRef :: G.Get ModuleRef
getModuleRef = ModuleRef <$> S.get

putModuleRef :: P.Putter ModuleRef
putModuleRef (ModuleRef mref) =
  S.put mref

-- |An address is either a contract or account.
data Address = AddressAccount !AccountAddress
             | AddressContract !ContractAddress
             deriving (Show, Eq)

instance S.Serialize Address where
  get = do
    h <- G.getWord8 -- FIXME: this is inefficient but ok for testing. The size
                    -- of the data should already tell what address it is.
    case h of
      0 -> AddressAccount <$> S.get
      1 -> AddressContract <$> S.get
      _ -> fail "Only two types of addresses are supported."

  put (AddressAccount acc) = P.putWord8 0 <> S.put acc
  put (AddressContract cnt) = P.putWord8 1 <> S.put cnt


-- | Time in milliseconds since the epoch
newtype Timestamp = Timestamp { tsMillis :: Word64 }
  deriving (Show, Read, Eq, Num, Ord, Real, Enum, S.Serialize, FromJSON, PersistField) via Word64

instance PersistFieldSql Timestamp where
    sqlType _ = SqlInt64

-- | Time duration in milliseconds
newtype Duration = Duration { durationMillis :: Word64 }
  deriving (Show, Read, Eq, Num, Ord, Real, Enum, S.Serialize, FromJSON) via Word64

-- | Convert a 'Timestamp' to a 'UTCTime'
timestampToUTCTime :: Timestamp -> UTCTime
timestampToUTCTime ts = posixSecondsToUTCTime $ fromIntegral (tsMillis ts) / 1000

-- | Covert a 'UTCTime' to a 'Timestamp'.
-- This rounds down to the nearest millisecond.
utcTimeToTimestamp :: UTCTime -> Timestamp
utcTimeToTimestamp = Timestamp . truncate . (*1000) . utcTimeToPOSIXSeconds

-- | Convert a 'Timestamp' to seconds since the epoch, rounding down
timestampToSeconds :: Timestamp -> Word64
timestampToSeconds ts = tsMillis ts `div` 1000

durationToNominalDiffTime :: Duration -> NominalDiffTime
durationToNominalDiffTime dur = fromIntegral (durationMillis dur) / 1000

addDuration :: Timestamp -> Duration -> Timestamp
addDuration (Timestamp ts) (Duration d) = Timestamp (ts + d)

-- | Expiry time of a transaction in seconds since the epoch
newtype TransactionExpiryTime = TransactionExpiryTime { expiry :: Word64 }
    deriving (Show, Read, Eq, Num, Ord, FromJSON, ToJSON) via Word64

instance S.Serialize TransactionExpiryTime where
  put = P.putWord64be . expiry
  get = TransactionExpiryTime <$> G.getWord64be

transactionExpired :: TransactionExpiryTime -> Timestamp -> Bool
transactionExpired (TransactionExpiryTime x) (Timestamp t) = 1000*x < t

-- |Check if whether the given timestamp is no greater than the end of the day
-- of the given year and month.
isTimestampBefore :: Timestamp -> YearMonth -> Bool
isTimestampBefore ts ym =
    utcTs < utcYearMonthExpiryTs
  where
    utcTs = timestampToUTCTime ts
    utcYearMonthExpiryTs = UTCTime expiryDay 0
      where
        year = toInteger (ymYear ym)
        month = fromIntegral (ymMonth ym)
        expiryYear = if month == 12 then year + 1 else year
        expiryMonth = if month == 12 then 1 else (month + 1) -- (month % 12) + 1
        expiryDay = fromGregorian expiryYear expiryMonth 1 -- unchecked, always valid


-- |Type representing the amount unit which is defined as the smallest
-- meaningful amount of GTUs.
-- Currently this unit is 10^-4 GTU and doesn't have a proper name.
-- FIXME: This likely needs to be Word128.
type AmountUnit = Word128
newtype Amount = Amount { _amount :: AmountUnit }
    deriving (Show, Read, Eq, Ord, Enum, Bounded, Num, Integral, Real, Hashable, FromJSON, ToJSON, S.Serialize) via AmountUnit

-- |Type representing a difference between amounts.
newtype AmountDelta = AmountDelta { amountDelta :: Integer }
    deriving (Eq, Ord, Enum, Num, Integral, Real)

amountToDelta :: Amount -> AmountDelta
amountToDelta = fromIntegral

amountDiff :: Amount -> Amount -> AmountDelta
amountDiff amt1 amt2 = fromIntegral amt1 - fromIntegral amt2

applyAmountDelta ::  AmountDelta -> Amount -> Amount
applyAmountDelta del amt =
        assert (amt' >= fromIntegral (minBound :: Amount)) $
        assert (amt' <= fromIntegral (maxBound :: Amount)) $
            fromIntegral amt'
    where
        amt' = fromIntegral amt + del

-- |The type used to count exact execution cost. This cost is then converted to
-- amounts in some way.
newtype Energy = Energy { _energy :: Word64 }
    deriving (Show, Read, Eq, Enum, Ord, Num, Real, Integral, Hashable, Bounded, FromJSON, ToJSON) via Word64

instance S.Serialize Energy where
  get = Energy <$> G.getWord64be
  put (Energy v) = P.putWord64be v

newtype Nonce = Nonce Word64
    deriving (Show, Read, Eq, Ord, Num, Enum, FromJSON, ToJSON) via Word64

instance S.Serialize Nonce where
  put (Nonce w) = P.putWord64be w
  get = Nonce <$> G.getWord64be

minNonce :: Nonce
minNonce = 1

newtype EncryptedAmount = EncryptedAmount ByteString
    deriving(Eq, S.Serialize)

instance Show EncryptedAmount where
  show (EncryptedAmount amnt) = BSL.unpack . toLazyByteString . byteStringHex $ amnt

data Account = Account {
  -- |Address of the account.
  _accountAddress :: !AccountAddress
  -- |Next available nonce for this account.
  ,_accountNonce :: !Nonce
  -- |Current public account balance.
  ,_accountAmount :: !Amount
  -- |List of encrypted amounts on the account.
  ,_accountEncryptedAmount :: ![EncryptedAmount]
  -- |Encryption key with which the encrypted amount on this account must be
  -- encrypted. Other accounts use it to send encrypted amounts to this account,
  -- if the key exists.
  ,_accountEncryptionKey :: !AccountEncryptionKey
  -- |The key used to verify transaction signatures, it records the signature scheme used as well.
  ,_accountVerificationKeys :: !AccountKeys
  -- |For now the only operation we need with a credential is to check whether
  -- there are any credentials that are valid, and validity only depends on expiry.
  -- A Max priority queue allows us to efficiently check for existence of such credentials,
  -- as well as listing of all valid credentials, and efficient insertion of new credentials.
  -- The priority is the expiry time of the credential.
  ,_accountCredentials :: !(Queue.MaxPQueue CredentialValidTo CredentialDeploymentValues)
  -- |The baker to which this account's stake is delegated (if any).
  ,_accountStakeDelegate :: !(Maybe BakerId)
  -- |The set of instances belonging to this account.
  -- TODO: Revisit choice of datastructure.  Additions and removals
  -- are expected to be rare.  The set is traversed when stake delegation
  -- changes.
  ,_accountInstances :: !(Set ContractAddress)
  } deriving(Show, Eq)

makeLenses ''Account

instance S.Serialize Account where
  put Account{..} = S.put _accountAddress <>
                    S.put _accountNonce <>
                    S.put _accountAmount <>
                    S.put _accountEncryptedAmount <>
                    S.put _accountEncryptionKey <>
                    S.put _accountVerificationKeys <>
                    S.put (Queue.elemsU _accountCredentials) <> -- we do not care whether the output is ordered or not
                    S.put _accountStakeDelegate <>
                    S.put (Set.toAscList _accountInstances)
  get = do
    _accountAddress <- S.get
    _accountNonce <- S.get
    _accountAmount <- S.get
    _accountEncryptedAmount <- S.get
    _accountEncryptionKey <- S.get
    _accountVerificationKeys <- S.get
    preAccountCredentials <- Queue.fromList . map (\cdv -> (pValidTo (cdvPolicy cdv), cdv)) <$> S.get
    let _accountCredentials = Queue.seqSpine preAccountCredentials preAccountCredentials
    _accountStakeDelegate <- S.get
    _accountInstances <- Set.fromList <$> S.get
    return Account{..}

instance HashableTo Hash.Hash Account where
  getHash = Hash.hash . S.runPut . S.put

-- |Create an empty account with the given public key.
newAccount :: AccountKeys -> AccountAddress -> CredentialRegistrationID -> Account
newAccount _accountVerificationKeys _accountAddress regId = Account {
        _accountNonce = minNonce,
        _accountAmount = 0,
        _accountEncryptedAmount = [],
        _accountEncryptionKey = makeEncryptionKey regId,
        _accountCredentials = Queue.empty,
        _accountStakeDelegate = Nothing,
        _accountInstances = Set.empty,
        ..
    }

-- |Size of the transaction payload.
newtype PayloadSize = PayloadSize Word32
    deriving (Eq, Show, Ord, Num, Real, Enum, Integral, FromJSON, ToJSON) via Word32

-- |Serialization format as specified
--
-- * @SPEC: <$DOCS/Transactions#transaction-header>
instance S.Serialize PayloadSize where
  put (PayloadSize n) = S.putWord32be n
  get = PayloadSize <$> S.getWord32be

-- |Serialized payload of the transaction
newtype EncodedPayload = EncodedPayload { _spayload :: BSS.ShortByteString }
    deriving(Eq, Show)

-- |There is no corresponding getter (to fit into the Serialize instance) since
-- encoded payload does not encode its own length. See 'getPayload' below.
putPayload :: P.Putter EncodedPayload
putPayload = P.putShortByteString . _spayload

-- |Get payload with given length.
getPayload :: PayloadSize -> G.Get EncodedPayload
getPayload (PayloadSize n) = EncodedPayload <$> G.getShortByteString (fromIntegral n)

payloadSize :: EncodedPayload -> PayloadSize
payloadSize = fromIntegral . BSS.length . _spayload

-- *Types that are morally part of the consensus, but need to be exposed in
-- other parts of the system as well, e.g., in smart contracts.

newtype Slot = Slot {theSlot :: Word64} deriving (Eq, Ord, Num, Real, Enum, Integral, Show, Read, S.Serialize) via Word64

-- |The slot number of the genesis block (0).
genesisSlot :: Slot
genesisSlot = 0

type EpochLength = Slot

newtype BlockHeight = BlockHeight {theBlockHeight :: Word64}
  deriving (Eq, Ord, Num, Real, Enum, Integral, Show, Hashable, FromJSON, ToJSON, PersistField) via Word64

instance PersistFieldSql BlockHeight where
  sqlType _ = SqlInt64


instance S.Serialize BlockHeight where
  put = S.putWord64be . theBlockHeight
  get = BlockHeight <$> S.getWord64be


-- |Blockchain metadata as needed by contract execution.
data ChainMetadata =
  ChainMetadata { slotNumber :: Slot
                -- |Height of the current block (the block which the transaction is going to be a part of).
                , blockHeight :: BlockHeight
                -- |Height of the last finalized block. NB: Each block has a
                -- pointer to the last finalized block, and this field is the
                -- height of that block. This information is stable with respect
                -- to time. In the future a block between that block and the
                -- current block might become finalized, so the distance
                -- blockHeight - finalizedHeight is an upper bound only.
                , finalizedHeight :: BlockHeight
                -- |Time at the beginning of the slot.
                , slotTime :: Timestamp
                }


type TransactionHash = Hash.Hash

-- * Types related to blocks

type BlockHash = Hash.Hash
type BlockProof = VRF.Proof
type BlockSignature = Sig.Signature
type BlockNonce = VRF.Proof


-- Template haskell derivations. At the end to get around staging restrictions.
$(deriveJSON defaultOptions{sumEncoding = TaggedObject{tagFieldName = "type", contentsFieldName = "address"}} ''Address)

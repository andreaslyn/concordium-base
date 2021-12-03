{-# LANGUAGE BangPatterns, DerivingStrategies, OverloadedStrings, ScopedTypeVariables, TemplateHaskell, StandaloneDeriving, DeriveTraversable, RankNTypes, DataKinds, KindSignatures, TypeFamilies, GADTs, TypeApplications #-}
-- |Types for chain update instructions, together with basic validation functions.
-- For specification, see: https://concordium.gitlab.io/whitepapers/update-mechanism/main.pdf
--
-- The specification defines the following update types:
--
--   - authorization updates
--   - parameter updates
--   - protocol updates
--   - emergency updates
--
-- Authorization updates alter the set of keys used to authorize chain updates.
-- (Practically, they are a type of parameter update.)
--
-- Parameter updates update a chain parameter.
-- Currently provided parameters are:
--
--   - election difficulty
--   - Energy to Euro exchange rate
--   - GTU to Euro exchange rate
--   - address of the foundation account
--   - parameters for distribution of newly minted tokens
--   - parameters controlling the transaction fee distribution
--   - parameters controlling the GAS account
--
-- Each parameter has an independent update queue.
-- Sequence numbers for each different parameter are thus independent.
-- (Note, where two parameters are tightly coupled, such that one should
-- not be changed independently of the other, then they should be combined
-- as a single parameter.)
--
-- Protocol updates specify a new protocol version.
-- The implementation should stop the current chain when a protocol update takes effect.
-- If it supports the new protocol version, it should begin a new chain according to that protocol,
-- and based on the state when the update took effect.
-- (Currently, this is not implemented.)
--
-- Emergency updates are inherently outside the scope of the chain implementation itself.
-- The chain only records the keys authorized for emergency updates, but does
-- not support any kind of emergency update messages.
module Concordium.Types.Updates where

import qualified Data.Aeson as AE
import qualified Data.Aeson.Types as AE
import Data.Aeson.Types
    ( (.:), FromJSON(..), ToJSON(..))
import Data.Aeson.TH
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Base16 as BS16
import Data.Hashable (Hashable)
import Data.Ix
import qualified Data.Map as Map
import Data.Serialize
import qualified Data.Set as Set
import Data.Text (Text, unpack)
import Data.Text.Encoding (encodeUtf8, decodeUtf8)
import qualified Data.Vector as Vec
import Data.Word
import Control.Monad

import Concordium.Crypto.SignatureScheme
import qualified Concordium.Crypto.SHA256 as SHA256

import Concordium.Utils
import Concordium.Utils.Serialization
import Concordium.Types
import Concordium.Types.HashableTo
import Concordium.Types.Parameters
import Concordium.ID.AnonymityRevoker (ArInfo)
import Concordium.ID.IdentityProvider (IpInfo)

----------------
-- * Parameter updates
----------------

--------------------
-- * Update Keys Types
--------------------

-- |Key type for update authorization.
type UpdatePublicKey = VerifyKey

-- |Index of a key in an 'Authorizations'.
type UpdateKeyIndex = Word16

-- |A wrapper over Word16 to ensure on Serialize.get and Aeson.parseJSON that it
-- is not zero and it doesn't exceed the max value.
newtype UpdateKeysThreshold = UpdateKeysThreshold { uktTheThreshold :: Word16 }
 deriving newtype (Show, Eq, Enum, Num, Real, Ord, Integral, AE.ToJSON, AE.FromJSON)

instance Serialize UpdateKeysThreshold where
  put = putWord16be . uktTheThreshold
  get = do
    r <- getWord16be
    when (r == 0) $ fail "UpdateKeysThreshold cannot be 0."
    return (UpdateKeysThreshold r)


--------------------
-- * Authorizations updates (Level 2 keys)
--------------------

-- |Access structure for level 2 update authorization.
data AccessStructure = AccessStructure {
        -- |Public keys
        accessPublicKeys :: !(Set.Set UpdateKeyIndex),
        -- |Number of keys required to authorize an update
        accessThreshold :: !UpdateKeysThreshold
    }
    deriving (Eq, Show)

instance Serialize AccessStructure where
    put AccessStructure{..} = do
        putWord16be (fromIntegral (Set.size accessPublicKeys))
        mapM_ putWord16be (Set.toAscList accessPublicKeys)
        put accessThreshold
    get = do
        keyCount <- getWord16be
        accessPublicKeys <- getSafeSizedSetOf keyCount getWord16be
        accessThreshold <- get
        when (accessThreshold > fromIntegral keyCount || accessThreshold < 1) $ fail "Invalid threshold"
        return AccessStructure{..}

-- type family AccessStructureForCPV1 (cpv :: ChainParametersVersion) where
--   AccessStructureForCPV1 'ChainParametersV0 = ()
--   AccessStructureForCPV1 'ChainParametersV1 = AccessStructure

data AccessStructureForCPV1 (cpv :: ChainParametersVersion) where
  AccessStructureForCPV1None :: AccessStructureForCPV1 'ChainParametersV0
  AccessStructureForCPV1Some :: !AccessStructure -> AccessStructureForCPV1 'ChainParametersV1

deriving instance Eq (AccessStructureForCPV1 cpv)
deriving instance Show (AccessStructureForCPV1 cpv)

putAccessStructureForCPV1 :: Putter (AccessStructureForCPV1 cpv)
putAccessStructureForCPV1 AccessStructureForCPV1None = return ()
putAccessStructureForCPV1 (AccessStructureForCPV1Some as) = put as

getAccessStructureForCPV1 :: SChainParametersVersion cpv -> Get (AccessStructureForCPV1 cpv)
getAccessStructureForCPV1 scpv = case scpv of
  SCPV0 -> return AccessStructureForCPV1None
  SCPV1 -> AccessStructureForCPV1Some <$> get

-- |The set of keys authorized for chain updates, together with
-- access structures determining which keys are authorized for
-- which update types. This is the payload of an update to authorization.
data Authorizations cpv = Authorizations {
        asKeys :: !(Vec.Vector UpdatePublicKey),
        -- |New emergency keys
        asEmergency :: !AccessStructure,
        -- |New protocol update keys
        asProtocol :: !AccessStructure,
        -- |Parameter keys: election difficulty
        asParamElectionDifficulty :: !AccessStructure,
        -- |Parameter keys: Euro:NRG
        asParamEuroPerEnergy :: !AccessStructure,
        -- |Parameter keys: microGTU:Euro
        asParamMicroGTUPerEuro :: !AccessStructure,
        -- |Parameter keys: foundation account
        asParamFoundationAccount :: !AccessStructure,
        -- |Parameter keys: mint distribution
        asParamMintDistribution :: !AccessStructure,
        -- |Parameter keys: transaction fee distribution
        asParamTransactionFeeDistribution :: !AccessStructure,
        -- |Parameter keys: GAS rewards
        asParamGASRewards :: !AccessStructure,
        -- |Parameter keys: Baker Minimum Threshold
        asBakerStakeThreshold :: !AccessStructure,
        -- |Parameter keys: ArIdentity and ArInfo
        asAddAnonymityRevoker :: !AccessStructure,
        -- |Parameter keys: IdentityProviderIdentity and IpInfo
        asAddIdentityProvider :: !AccessStructure,
        -- |Parameter keys: Cooldown periods for pool owners and delegators
        asCooldownParameters :: !(AccessStructureForCPV1 cpv),
        -- |Parameter keys: Length of reward period / payday
        asTimeParameters :: !(AccessStructureForCPV1 cpv)
    }

deriving instance Eq (Authorizations cpv)
deriving instance Show (Authorizations cpv)


putAuthorizations :: Putter (Authorizations cpv)
putAuthorizations Authorizations{..} = do
        putWord16be (fromIntegral (Vec.length asKeys))
        mapM_ put asKeys
        put asEmergency
        put asProtocol
        put asParamElectionDifficulty
        put asParamEuroPerEnergy
        put asParamMicroGTUPerEuro
        put asParamFoundationAccount
        put asParamMintDistribution
        put asParamTransactionFeeDistribution
        put asParamGASRewards
        put asBakerStakeThreshold
        put asAddAnonymityRevoker
        put asAddIdentityProvider
        putAccessStructureForCPV1 asCooldownParameters
        putAccessStructureForCPV1 asTimeParameters

getAuthorizations :: forall cpv. IsChainParametersVersion cpv => Get (Authorizations cpv)
getAuthorizations = label "deserialization update authorizations" $ do
        keyCount <- getWord16be
        asKeys <- Vec.replicateM (fromIntegral keyCount) get
        let getChecked = do
                r <- get
                case Set.lookupMax (accessPublicKeys r) of
                    Just v
                        | v < keyCount -> return r
                        | otherwise -> fail "invalid key index"
                    Nothing -> return r
        asEmergency <- getChecked
        asProtocol <- getChecked
        asParamElectionDifficulty <- getChecked
        asParamEuroPerEnergy <- getChecked
        asParamMicroGTUPerEuro <- getChecked
        asParamFoundationAccount <- getChecked
        asParamMintDistribution <- getChecked
        asParamTransactionFeeDistribution <- getChecked
        asParamGASRewards <- getChecked
        asBakerStakeThreshold <- getChecked
        asAddAnonymityRevoker <- getChecked
        asAddIdentityProvider <- getChecked
        (asCooldownParameters, asTimeParameters) <- case chainParametersVersion @cpv of 
          SCPV0 -> return (AccessStructureForCPV1None, AccessStructureForCPV1None)
          SCPV1 -> do 
            cp <- getChecked
            tp <- getChecked
            return (AccessStructureForCPV1Some cp, AccessStructureForCPV1Some tp)
        return Authorizations{..}

instance IsChainParametersVersion cpv => Serialize (Authorizations cpv) where
  put = putAuthorizations
  get = getAuthorizations

instance HashableTo SHA256.Hash (Authorizations cpv) where
    getHash a = SHA256.hash $ "Authorizations" <> runPut (putAuthorizations a)

instance Monad m => MHashableTo m SHA256.Hash (Authorizations cpv)

parseAuthorizationsJSON :: forall cpv. IsChainParametersVersion cpv => AE.Value -> AE.Parser (Authorizations cpv)
parseAuthorizationsJSON = AE.withObject "Authorizations" $ \v -> do
        asKeys <- Vec.fromList <$> v .: "keys"
        let
            parseAS x = v .: x >>= AE.withObject (unpack x) (\o -> do
                accessPublicKeys :: Set.Set UpdateKeyIndex <- o .: "authorizedKeys"
                accessThreshold <- o .: "threshold"
                when (accessThreshold > fromIntegral (Set.size accessPublicKeys) || accessThreshold < 1) $ fail "Invalid threshold"
                case Set.lookupMax accessPublicKeys of
                    Just maxKeyIndex
                        | fromIntegral maxKeyIndex >= Vec.length asKeys -> fail "invalid key index"
                    _ -> return AccessStructure{..}
                )
        asEmergency <- parseAS "emergency"
        asProtocol <- parseAS "protocol"
        asParamElectionDifficulty <- parseAS "electionDifficulty"
        asParamEuroPerEnergy <- parseAS "euroPerEnergy"
        asParamMicroGTUPerEuro <- parseAS "microGTUPerEuro"
        asParamFoundationAccount <- parseAS "foundationAccount"
        asParamMintDistribution <- parseAS "mintDistribution"
        asParamTransactionFeeDistribution <- parseAS "transactionFeeDistribution"
        asParamGASRewards <- parseAS "paramGASRewards"
        asBakerStakeThreshold <- parseAS "bakerStakeThreshold"
        asAddAnonymityRevoker <- parseAS "addAnonymityRevoker"
        asAddIdentityProvider <- parseAS "addIdentityProvider"
        (asCooldownParameters, asTimeParameters) <- case chainParametersVersion @cpv of 
          SCPV0 -> return (AccessStructureForCPV1None, AccessStructureForCPV1None)
          SCPV1 -> do 
            cp <- parseAS "cooldownParameters"
            tp <- parseAS "timeParameters"
            return (AccessStructureForCPV1Some cp, AccessStructureForCPV1Some tp)
        return Authorizations{..}

instance IsChainParametersVersion cpv => AE.FromJSON (Authorizations cpv) where
    parseJSON = parseAuthorizationsJSON

instance AE.ToJSON (Authorizations cpv) where
    toJSON Authorizations{..} = AE.object ([
                "keys" AE..= Vec.toList asKeys,
                "emergency" AE..= t asEmergency,
                "protocol" AE..= t asProtocol,
                "electionDifficulty" AE..= t asParamElectionDifficulty,
                "euroPerEnergy" AE..= t asParamEuroPerEnergy,
                "microGTUPerEuro" AE..= t asParamMicroGTUPerEuro,
                "foundationAccount" AE..= t asParamFoundationAccount,
                "mintDistribution" AE..= t asParamMintDistribution,
                "transactionFeeDistribution" AE..= t asParamTransactionFeeDistribution,
                "paramGASRewards" AE..= t asParamGASRewards,
                "bakerStakeThreshold" AE..= t asBakerStakeThreshold,
                "addAnonymityRevoker" AE..= t asAddAnonymityRevoker,
                "addIdentityProvider" AE..= t asAddIdentityProvider
                
            ] ++ cooldownParameters ++ timeParameters)
        where
            t AccessStructure{..} = AE.object [
                    "authorizedKeys" AE..= accessPublicKeys,
                    "threshold" AE..= accessThreshold
                ]
            cooldownParameters = case asCooldownParameters of 
                  AccessStructureForCPV1None -> []
                  AccessStructureForCPV1Some as -> ["cooldownParameters" AE..= t as]
            timeParameters = case asTimeParameters of 
                  AccessStructureForCPV1None -> []
                  AccessStructureForCPV1Some as -> ["timeParameters" AE..= t as]

-----------------
-- * Higher Level keys (Root and Level 1 keys)
-----------------

data RootKeysKind
data Level1KeysKind

-- |This data structure will be used for all the updates that update Root or
-- level 1 keys, and to store the authorized keys for those operations. The phantom
-- type has to be either RootKeysKind or Level1KeysKind.
data HigherLevelKeys keyKind = HigherLevelKeys {
  hlkKeys :: !(Vec.Vector UpdatePublicKey),
  hlkThreshold :: !UpdateKeysThreshold
  } deriving (Eq, Show)

instance Serialize (HigherLevelKeys a) where
  put HigherLevelKeys{..} = do
    putWord16be (fromIntegral (Vec.length hlkKeys))
    mapM_ put hlkKeys
    put hlkThreshold
  get = do
    keyCount <- getWord16be
    hlkKeys <- Vec.replicateM (fromIntegral keyCount) get
    hlkThreshold <- get
    when (hlkThreshold > fromIntegral keyCount || hlkThreshold < 1) $ fail "Invalid threshold"
    return HigherLevelKeys{..}

instance AE.FromJSON (HigherLevelKeys a) where
  parseJSON = AE.withObject "HigherLevelKeys" $ \v -> do
    hlkKeys <- Vec.fromList <$> v .: "keys"
    hlkThreshold <- (v .: "threshold")
    when (hlkThreshold > fromIntegral (Vec.length hlkKeys) || hlkThreshold < 1) $ fail "Invalid threshold"
    return HigherLevelKeys{..}

instance AE.ToJSON (HigherLevelKeys a) where
  toJSON HigherLevelKeys{..} = AE.object [
    "keys" AE..= Vec.toList hlkKeys,
    "threshold" AE..= hlkThreshold
    ]

instance HashableTo SHA256.Hash (HigherLevelKeys a) where
  getHash = SHA256.hash . encode

instance Monad m => MHashableTo m SHA256.Hash (HigherLevelKeys a) where

--------------------
-- * Root update
--------------------

-- |Root updates are the highest kind of updates. They can update every other
-- set of keys, even themselves. They can only be performed by Root level keys.
data RootUpdate cpv =
  RootKeysRootUpdate {
    rkruKeys :: !(HigherLevelKeys RootKeysKind)
  }
  -- ^Update the root keys
  | Level1KeysRootUpdate {
    l1kruKeys :: !(HigherLevelKeys Level1KeysKind)
  }
  -- ^Update the Level 1 keys
  | Level2KeysRootUpdate {
    l2kruAuthorizations :: !(Authorizations cpv)
  }
  -- ^Update the Level 1 keys
  -- | Level2KeysRootUpdateV1 {
  --   l2kruAuthorizationsV1 :: !(Authorizations 'ChainParametersV1)
  -- }
  -- ^Update the level 2 keys


-- data RootUpdate cpv where
--   RootKeysRootUpdate :: forall cpv. {
--     rkruKeys :: !(HigherLevelKeys RootKeysKind)
--   } -> RootUpdate cpv
--   -- ^Update the root keys
--   Level1KeysRootUpdate :: forall cpv. {
--     l1kruKeys :: !(HigherLevelKeys Level1KeysKind)
--   } -> RootUpdate cpv
--   -- ^Update the Level 1 keys
--   Level2KeysRootUpdateV0 :: {
--     l2kruAuthorizationsV0 :: !(Authorizations 'ChainParametersV0)
--   } -> RootUpdate 'ChainParametersV0
--   -- ^Update the Level 1 keys
--   Level2KeysRootUpdateV1 :: {
--     l2kruAuthorizationsV1 :: !(Authorizations 'ChainParametersV1)
--   } -> RootUpdate 'ChainParametersV1

deriving instance Eq (RootUpdate cpv)
deriving instance Show (RootUpdate cpv)

putRootUpdate :: Putter (RootUpdate cpv)
putRootUpdate RootKeysRootUpdate{..} = do
    putWord8 0
    put rkruKeys
putRootUpdate Level1KeysRootUpdate{..} = do
  putWord8 1
  put l1kruKeys
putRootUpdate Level2KeysRootUpdate{..} = do
  putWord8 2
  putAuthorizations l2kruAuthorizations

getRootUpdate :: IsChainParametersVersion cpv => Get (RootUpdate cpv)
getRootUpdate = label "RootUpdate" $ do
  variant <- getWord8
  case variant of
    0 -> RootKeysRootUpdate <$> get
    1 -> Level1KeysRootUpdate <$> get
    2 -> Level2KeysRootUpdate <$> get
    _ -> fail $ "Unknown variant: " ++ show variant

instance IsChainParametersVersion cpv => Serialize (RootUpdate cpv) where
  put = putRootUpdate
  get = getRootUpdate

instance AE.FromJSON (RootUpdate 'ChainParametersV0) where
  parseJSON = AE.withObject "RootUpdate" $ \o -> do
    variant :: Text <- o .: "typeOfUpdate"
    case variant of
         "rootKeysUpdate" -> RootKeysRootUpdate <$> o .: "updatePayload"
         "level1KeysUpdate" -> Level1KeysRootUpdate <$> o .: "updatePayload"
         "level2KeysUpdate" -> Level2KeysRootUpdate <$> o .: "updatePayload"
         _ -> fail $ "Unknown variant: " ++ show variant

instance AE.FromJSON (RootUpdate 'ChainParametersV1) where
  parseJSON = AE.withObject "RootUpdateV1" $ \o -> do
    variant :: Text <- o .: "typeOfUpdate"
    case variant of
         "rootKeysUpdate" -> RootKeysRootUpdate <$> o .: "updatePayload"
         "level1KeysUpdate" -> Level1KeysRootUpdate <$> o .: "updatePayload"
         "level2KeysUpdate" -> Level2KeysRootUpdate <$> o .: "updatePayload"
         _ -> fail $ "Unknown variant: " ++ show variant

instance AE.ToJSON (RootUpdate cpv) where
  toJSON RootKeysRootUpdate{..} =
    AE.object [ "typeOfUpdate" AE..= ("rootKeysUpdate" :: Text),
                "updatePayload" AE..= rkruKeys
              ]
  toJSON Level1KeysRootUpdate{..} =
    AE.object [ "typeOfUpdate" AE..= ("level1KeysUpdate" :: Text),
                "updatePayload" AE..= l1kruKeys
              ]
  toJSON Level2KeysRootUpdate{..} =
    AE.object [ "typeOfUpdate" AE..= ("level2KeysUpdate" :: Text),
                "updatePayload" AE..= l2kruAuthorizations
              ]

--------------------
-- * Level 1 updates
--------------------

-- |Level 1 updates are the intermediate update kind. They can update themselves
-- or level 2 keys. They can only be performed by Level 1 keys.
data Level1Update cpv =
  Level1KeysLevel1Update {
    l1kl1uKeys :: !(HigherLevelKeys Level1KeysKind)
  }
  | Level2KeysLevel1Update {
    l2kl1uAuthorizations :: !(Authorizations cpv)
  } 

deriving instance Eq (Level1Update cpv)
deriving instance Show (Level1Update cpv)

putLevel1Update :: Putter (Level1Update cpv)
putLevel1Update Level1KeysLevel1Update{..} = do
  putWord8 0
  put l1kl1uKeys
putLevel1Update Level2KeysLevel1Update{..} = do
  putWord8 1
  putAuthorizations l2kl1uAuthorizations

getLevel1Update :: IsChainParametersVersion cpv => Get (Level1Update cpv)
getLevel1Update = label "Level1Update" $ do
    variant <- getWord8
    case variant of
      0 -> Level1KeysLevel1Update <$> get
      1 -> Level2KeysLevel1Update <$> getAuthorizations
      _ -> fail $ "Unknown variant: " ++ show variant

instance AE.FromJSON (Level1Update 'ChainParametersV0) where
  parseJSON = AE.withObject "Level1Update" $ \o -> do
    variant :: Text <- o .: "typeOfUpdate"
    case variant of
      "level1KeysUpdate" -> Level1KeysLevel1Update <$> o .: "updatePayload"
      "level2KeysUpdate" -> Level2KeysLevel1Update <$> o .: "updatePayload"
      _ -> fail $ "Unknown variant: " ++ show variant
instance AE.FromJSON (Level1Update 'ChainParametersV1) where
  parseJSON = AE.withObject "Level1Update" $ \o -> do
    variant :: Text <- o .: "typeOfUpdate"
    case variant of
      "level1KeysUpdate" -> Level1KeysLevel1Update <$> o .: "updatePayload"
      "level2KeysUpdate" -> Level2KeysLevel1Update <$> o .: "updatePayload"
      _ -> fail $ "Unknown variant: " ++ show variant

instance AE.ToJSON (Level1Update cpv) where
  toJSON Level1KeysLevel1Update{..} =
    AE.object [ "typeOfUpdate" AE..= ("level1KeysUpdate" :: Text),
                "updatePayload" AE..= l1kl1uKeys
              ]
  toJSON Level2KeysLevel1Update{..} =
    AE.object [ "typeOfUpdate" AE..= ("level2KeysUpdate" :: Text),
                "updatePayload" AE..= l2kl1uAuthorizations
              ]

----------------------
-- * Protocol updates
----------------------

-- |Payload of a protocol update.
data ProtocolUpdate = ProtocolUpdate {
        -- |A brief message about the update
        puMessage :: !Text,
        -- |A URL of a document describing the update
        puSpecificationURL :: !Text,
        -- |SHA256 hash of the specification document
        puSpecificationHash :: !SHA256.Hash,
        -- |Auxiliary data whose interpretation is defined by the new specification
        puSpecificationAuxiliaryData :: !ByteString
    }
    deriving (Eq, Show)

-- |The serialization of a protocol update payload is as follows:
--
--      1. Length of the rest of the payload (Word64)
--      2. UTF-8 encoded textual description: length (Word64) + text (Bytes(length))
--      3. UTF-8 encoded URL of description document: length (Word64) + text (Bytes(length))
--      4. SHA-256 hash of description document
--      5. Uninterpreted bytes for the rest of the payload
instance Serialize ProtocolUpdate where
    put ProtocolUpdate{..} = putNested putLength $ do
            putUtf8 puMessage
            putUtf8 puSpecificationURL
            put puSpecificationHash
            putByteString puSpecificationAuxiliaryData
    get = label "deserializing a protocol update payload" $ do
        len <- getLength
        isolate len $ do
            puMessage <- getUtf8
            puSpecificationURL <- getUtf8
            puSpecificationHash <- get
            puSpecificationAuxiliaryData <- getByteString =<< remaining
            return ProtocolUpdate{..}

instance HashableTo SHA256.Hash ProtocolUpdate where
    getHash pu = SHA256.hash $ "ProtocolUpdate" <> encode pu

instance Monad m => MHashableTo m SHA256.Hash ProtocolUpdate

instance AE.ToJSON ProtocolUpdate where
    toJSON ProtocolUpdate{..} = AE.object [
            "message" AE..= puMessage,
            "specificationURL" AE..= puSpecificationURL,
            "specificationHash" AE..= puSpecificationHash,
            "specificationAuxiliaryData" AE..= decodeUtf8 (BS16.encode puSpecificationAuxiliaryData)
        ]

instance AE.FromJSON ProtocolUpdate where
    parseJSON = AE.withObject "ProtocolUpdate" $ \v -> do
            puMessage <- v AE..: "message"
            puSpecificationURL <- v AE..: "specificationURL"
            puSpecificationHash <- v AE..: "specificationHash"
            (puSpecificationAuxiliaryData, garbage) <- BS16.decode . encodeUtf8 <$> v AE..: "specificationAuxiliaryData"
            unless (BS.null garbage) $ fail "Unable to parse \"specificationAuxiliaryData\" as Base-16"
            return ProtocolUpdate{..}



-------------------------
-- * Keys collection
-------------------------

-- |A data structure that holds a complete set of update keys. It will be stored
-- in the BlockState.
data UpdateKeysCollection cpv = UpdateKeysCollection {
  rootKeys :: !(HigherLevelKeys RootKeysKind),
  level1Keys :: !(HigherLevelKeys Level1KeysKind),
  level2Keys :: !(Authorizations cpv)
  } deriving (Eq, Show)

putUpdateKeysCollection :: Putter (UpdateKeysCollection cpv)
putUpdateKeysCollection UpdateKeysCollection{..} = do
  put rootKeys
  put level1Keys
  putAuthorizations level2Keys

getUpdateKeysCollection :: IsChainParametersVersion cpv => Get (UpdateKeysCollection cpv)
getUpdateKeysCollection = UpdateKeysCollection <$> get <*> get <*> getAuthorizations

instance IsChainParametersVersion cpv => Serialize (UpdateKeysCollection cpv) where
  put = putUpdateKeysCollection
  get = getUpdateKeysCollection

instance HashableTo SHA256.Hash (UpdateKeysCollection cpv) where
  getHash = SHA256.hash . runPut . putUpdateKeysCollection

instance Monad m => MHashableTo m SHA256.Hash (UpdateKeysCollection cpv) where

instance IsChainParametersVersion cpv => AE.FromJSON (UpdateKeysCollection cpv) where
  parseJSON = AE.withObject "UpdateKeysCollection" $ \v -> do
    rootKeys <- v .: "rootKeys"
    level1Keys <- v .: "level1Keys"
    level2Keys <- v .: "level2Keys"
    return UpdateKeysCollection{..}
  
-- instance AE.FromJSON (UpdateKeysCollection 'ChainParametersV1) where
--   parseJSON = AE.withObject "UpdateKeysCollection" $ \v -> do
--     rootKeys <- v .: "rootKeys"
--     level1Keys <- v .: "level1Keys"
--     level2Keys <- v .: "level2Keys"
--     return UpdateKeysCollection{..}

instance AE.ToJSON (UpdateKeysCollection cpv) where
  toJSON UpdateKeysCollection{..} = AE.object [
    "rootKeys" AE..= rootKeys,
    "level1Keys" AE..= level1Keys,
    "level2Keys" AE..= level2Keys
    ]

-------------------------
-- * Update Instructions
-------------------------

-- |Types of updates to the chain. Used to disambiguate to which queue of updates should the value be pushed.
-- NB: This does not match exactly the update payload. Some update payloads can enqueue in different update queues.
data UpdateType
    = UpdateProtocol
    -- ^Update the chain protocol
    | UpdateElectionDifficulty
    -- ^Update the election difficulty
    | UpdateEuroPerEnergy
    -- ^Update the euro per energy exchange rate
    | UpdateMicroGTUPerEuro
    -- ^Update the microGTU per euro exchange rate
    | UpdateFoundationAccount
    -- ^Update the address of the foundation account
    | UpdateMintDistribution
    -- ^Update the distribution of newly minted GTU
    | UpdateTransactionFeeDistribution
    -- ^Update the distribution of transaction fees
    | UpdateGASRewards
    -- ^Update the GAS rewards
    | UpdateBakerStakeThreshold
    -- ^Minimum amount to register as a baker
    | UpdateAddAnonymityRevoker
    -- ^Add new anonymity revoker
    | UpdateAddIdentityProvider
    -- ^Add new identity provider
    | UpdateRootKeys
    -- ^Update the root keys with the root keys
    | UpdateLevel1Keys
    -- ^Update the level 1 keys
    | UpdateLevel2Keys
    | UpdateCooldownParametersCPV1
    | UpdatePoolParametersCPV1
    | UpdateTimeParametersCPV1
    deriving (Eq, Ord, Show, Ix, Bounded, Enum)

-- The JSON instance will encode all values as strings, lower-casing the first
-- character, so, e.g., `toJSON UpdateProtocol = String "updateProtocol"`.
$(deriveJSON defaultOptions{
    constructorTagModifier = firstLower,
    allNullaryToStringTag = True
    }
    ''UpdateType)

instance Serialize UpdateType where
    put UpdateProtocol = putWord8 1
    put UpdateElectionDifficulty = putWord8 2
    put UpdateEuroPerEnergy = putWord8 3
    put UpdateMicroGTUPerEuro = putWord8 4
    put UpdateFoundationAccount = putWord8 5
    put UpdateMintDistribution = putWord8 6
    put UpdateTransactionFeeDistribution = putWord8 7
    put UpdateGASRewards = putWord8 8
    put UpdateBakerStakeThreshold = putWord8 9
    put UpdateRootKeys = putWord8 10
    put UpdateLevel1Keys = putWord8 11
    put UpdateLevel2Keys = putWord8 12
    put UpdateAddAnonymityRevoker = putWord8 13
    put UpdateAddIdentityProvider = putWord8 14
    put UpdateCooldownParametersCPV1 = putWord8 15
    put UpdatePoolParametersCPV1 = putWord8 16
    put UpdateTimeParametersCPV1 = putWord8 17 
    get = getWord8 >>= \case
        1 -> return UpdateProtocol
        2 -> return UpdateElectionDifficulty
        3 -> return UpdateEuroPerEnergy
        4 -> return UpdateMicroGTUPerEuro
        5 -> return UpdateFoundationAccount
        6 -> return UpdateMintDistribution
        7 -> return UpdateTransactionFeeDistribution
        8 -> return UpdateGASRewards
        9 -> return UpdateBakerStakeThreshold
        10 -> return UpdateRootKeys
        11 -> return UpdateLevel1Keys
        12 -> return UpdateLevel2Keys
        13 -> return UpdateAddAnonymityRevoker
        14 -> return UpdateAddIdentityProvider
        15 -> return UpdateCooldownParametersCPV1
        16 -> return UpdatePoolParametersCPV1
        17 -> return UpdateTimeParametersCPV1
        n -> fail $ "invalid update type: " ++ show n

-- |Sequence number for updates of a given type.
type UpdateSequenceNumber = Nonce

-- |Lowest 'UpdateSequenceNumber'.
minUpdateSequenceNumber :: UpdateSequenceNumber
minUpdateSequenceNumber = minNonce

--------------------
-- * Update Header
--------------------

-- |The header for an update instruction, consisting of the
-- sequence number, effective time, expiry time (timeout),
-- and payload size. This structure is the same for all
-- update payload types.
data UpdateHeader = UpdateHeader {
        updateSeqNumber :: !UpdateSequenceNumber,
        updateEffectiveTime :: !TransactionTime,
        updateTimeout :: !TransactionExpiryTime,
        updatePayloadSize :: !PayloadSize
    }
    deriving (Eq, Show)

instance Serialize UpdateHeader where
    put UpdateHeader{..} = do
        put updateSeqNumber
        put updateEffectiveTime
        put updateTimeout
        put updatePayloadSize
    get = do
        updateSeqNumber <- get
        updateEffectiveTime <- get
        updateTimeout <- get
        updatePayloadSize <- get
        return UpdateHeader{..}

--------------------
-- * Update Payload
--------------------

-- |The payload of an update instruction.
data UpdatePayload
    = ProtocolUpdatePayload !ProtocolUpdate
    -- ^Update the protocol
    | ElectionDifficultyUpdatePayload !ElectionDifficulty
    -- ^Update the election difficulty parameter
    | EuroPerEnergyUpdatePayload !ExchangeRate
    -- ^Update the euro-per-energy parameter
    | MicroGTUPerEuroUpdatePayload !ExchangeRate
    -- ^Update the microGTU-per-euro parameter
    | FoundationAccountUpdatePayload !AccountAddress
    -- ^Update the address of the foundation account
    | MintDistributionUpdatePayload !MintDistribution
    -- ^Update the distribution of newly minted GTU
    | TransactionFeeDistributionUpdatePayload !TransactionFeeDistribution
    -- ^Update the distribution of transaction fees
    | GASRewardsUpdatePayload !GASRewards
    -- ^Update the GAS rewards
    | BakerStakeThresholdUpdatePayload !(PoolParameters 'ChainParametersV0)
    -- ^Update the minimum amount to register as a baker with chain parameter version 0
    | RootCPV0UpdatePayload !(RootUpdate 'ChainParametersV0)
    -- ^Update the minimum amount to register as a baker with chain parameter version 1
    | RootCPV1UpdatePayload !(RootUpdate 'ChainParametersV1)
    -- ^Root level updates
    | Level1CPV0UpdatePayload !(Level1Update 'ChainParametersV0)
    | Level1CPV1UpdatePayload !(Level1Update 'ChainParametersV1)
    -- ^Level 1 update
    | AddAnonymityRevokerUpdatePayload !ArInfo
    | AddIdentityProviderUpdatePayload !IpInfo
    | CooldownParametersCPV1UpdatePayload !(CooldownParameters 'ChainParametersV1)
    | PoolParametersCPV1UpdatePayload !(PoolParameters 'ChainParametersV1)
    | TimeParametersCPV1UpdatePayload !(TimeParameters 'ChainParametersV1)
    deriving (Eq, Show)


putUpdatePayload :: Putter UpdatePayload
putUpdatePayload (ProtocolUpdatePayload u) = putWord8 1 >> put u
putUpdatePayload (ElectionDifficultyUpdatePayload u) = putWord8 2 >> put u
putUpdatePayload (EuroPerEnergyUpdatePayload u) = putWord8 3 >> put u
putUpdatePayload (MicroGTUPerEuroUpdatePayload u) = putWord8 4 >> put u
putUpdatePayload (FoundationAccountUpdatePayload u) = putWord8 5 >> put u
putUpdatePayload (MintDistributionUpdatePayload u) = putWord8 6 >> put u
putUpdatePayload (TransactionFeeDistributionUpdatePayload u) = putWord8 7 >> put u
putUpdatePayload (GASRewardsUpdatePayload u) = putWord8 8 >> put u
putUpdatePayload (BakerStakeThresholdUpdatePayload u) = putWord8 9 >> putPoolParameters u
putUpdatePayload (RootCPV0UpdatePayload u) = putWord8 10 >> putRootUpdate u
putUpdatePayload (Level1CPV0UpdatePayload u) = putWord8 11 >> putLevel1Update u
putUpdatePayload (AddAnonymityRevokerUpdatePayload u) = putWord8 12 >> put u
putUpdatePayload (AddIdentityProviderUpdatePayload u) = putWord8 13 >> put u
putUpdatePayload (CooldownParametersCPV1UpdatePayload u) = putWord8 14 >> putCooldownParameters u
putUpdatePayload (PoolParametersCPV1UpdatePayload u) = putWord8 15 >> putPoolParameters u
putUpdatePayload (TimeParametersCPV1UpdatePayload u) = putWord8 16 >> putTimeParameters u 
putUpdatePayload (RootCPV1UpdatePayload u) = putWord8 17 >> putRootUpdate u
putUpdatePayload (Level1CPV1UpdatePayload u) = putWord8 18 >> putLevel1Update u

getUpdatePayload :: SProtocolVersion pv -> Get UpdatePayload
getUpdatePayload spv = 
  getWord8 >>= \case
    1 -> ProtocolUpdatePayload <$> get
    2 -> ElectionDifficultyUpdatePayload <$> get
    3 -> EuroPerEnergyUpdatePayload <$> get
    4 -> MicroGTUPerEuroUpdatePayload <$> get
    5 -> FoundationAccountUpdatePayload <$> get
    6 -> MintDistributionUpdatePayload <$> get
    7 -> TransactionFeeDistributionUpdatePayload <$> get
    8 -> GASRewardsUpdatePayload <$> get
    9 | isCPV ChainParametersV0 -> BakerStakeThresholdUpdatePayload <$> getPoolParameters 
    10 | isCPV ChainParametersV0 -> RootCPV0UpdatePayload <$> getRootUpdate
    11 | isCPV ChainParametersV0 -> Level1CPV0UpdatePayload <$> getLevel1Update
    12 -> AddAnonymityRevokerUpdatePayload <$> get
    13 -> AddIdentityProviderUpdatePayload <$> get
    14 | isCPV ChainParametersV1 -> CooldownParametersCPV1UpdatePayload <$> getCooldownParameters
    15 | isCPV ChainParametersV1 -> PoolParametersCPV1UpdatePayload <$> getPoolParameters
    16 | isCPV ChainParametersV1 -> TimeParametersCPV1UpdatePayload <$> getTimeParameters
    17 | isCPV ChainParametersV1 -> RootCPV1UpdatePayload <$> getRootUpdate
    18 | isCPV ChainParametersV1 -> Level1CPV1UpdatePayload <$> getLevel1Update
    x -> fail $ "Unknown update payload kind: " ++ show x
    where
      isCPV cpv = cpv == demoteChainParameterVersion scpv
      scpv = chainParametersVersionFor spv


$(deriveJSON defaultOptions{
    constructorTagModifier = firstLower . reverse . drop (length ("UpdatePayload" :: String)) . reverse,
    sumEncoding = TaggedObject {tagFieldName = "updateType", contentsFieldName = "update"}
    }
    ''UpdatePayload)

-- |Determine the 'UpdateType' associated with an 'UpdatePayload'.
updateType :: UpdatePayload -> UpdateType
updateType ProtocolUpdatePayload{} = UpdateProtocol
updateType ElectionDifficultyUpdatePayload{} = UpdateElectionDifficulty
updateType EuroPerEnergyUpdatePayload{} = UpdateEuroPerEnergy
updateType MicroGTUPerEuroUpdatePayload{} = UpdateMicroGTUPerEuro
updateType FoundationAccountUpdatePayload{} = UpdateFoundationAccount
updateType MintDistributionUpdatePayload{} = UpdateMintDistribution
updateType TransactionFeeDistributionUpdatePayload{} = UpdateTransactionFeeDistribution
updateType GASRewardsUpdatePayload{} = UpdateGASRewards
updateType BakerStakeThresholdUpdatePayload{} = UpdateBakerStakeThreshold
updateType AddAnonymityRevokerUpdatePayload{} = UpdateAddAnonymityRevoker
updateType AddIdentityProviderUpdatePayload{} = UpdateAddIdentityProvider
updateType CooldownParametersCPV1UpdatePayload{} = UpdateCooldownParametersCPV1
updateType PoolParametersCPV1UpdatePayload{} = UpdatePoolParametersCPV1
updateType TimeParametersCPV1UpdatePayload{} = UpdateTimeParametersCPV1
updateType (RootCPV0UpdatePayload RootKeysRootUpdate{}) = UpdateRootKeys
updateType (RootCPV1UpdatePayload RootKeysRootUpdate{}) = UpdateRootKeys
updateType (RootCPV0UpdatePayload Level1KeysRootUpdate{}) = UpdateLevel1Keys
updateType (RootCPV1UpdatePayload Level1KeysRootUpdate{}) = UpdateLevel1Keys
updateType (RootCPV0UpdatePayload Level2KeysRootUpdate{}) = UpdateLevel2Keys
updateType (RootCPV1UpdatePayload Level2KeysRootUpdate{}) = UpdateLevel2Keys
updateType (Level1CPV0UpdatePayload Level1KeysLevel1Update{}) = UpdateLevel1Keys
updateType (Level1CPV1UpdatePayload Level1KeysLevel1Update{}) = UpdateLevel1Keys
updateType (Level1CPV0UpdatePayload Level2KeysLevel1Update{}) = UpdateLevel2Keys
updateType (Level1CPV1UpdatePayload Level2KeysLevel1Update{}) = UpdateLevel2Keys

-- |Extract the relevant set of key indices and threshold authorized for the given update instruction.
extractKeysIndices :: UpdatePayload -> UpdateKeysCollection cpv -> (Set.Set UpdateKeyIndex, UpdateKeysThreshold)
extractKeysIndices p =
  case p of
    ProtocolUpdatePayload{} -> f asProtocol
    ElectionDifficultyUpdatePayload{} -> f asParamElectionDifficulty
    EuroPerEnergyUpdatePayload{} -> f asParamEuroPerEnergy
    MicroGTUPerEuroUpdatePayload{} -> f asParamMicroGTUPerEuro
    FoundationAccountUpdatePayload{} -> f asParamFoundationAccount
    MintDistributionUpdatePayload{} -> f asParamMintDistribution
    TransactionFeeDistributionUpdatePayload{} -> f asParamTransactionFeeDistribution
    GASRewardsUpdatePayload{} -> f asParamGASRewards
    BakerStakeThresholdUpdatePayload{} -> f asBakerStakeThreshold
    RootCPV0UpdatePayload{} -> g rootKeys
    RootCPV1UpdatePayload{} -> g rootKeys
    Level1CPV0UpdatePayload{} -> g level1Keys
    Level1CPV1UpdatePayload{} -> g level1Keys
    AddAnonymityRevokerUpdatePayload{} -> f asAddAnonymityRevoker
    AddIdentityProviderUpdatePayload{} -> f asAddIdentityProvider
    CooldownParametersCPV1UpdatePayload{} -> f' asCooldownParameters
    PoolParametersCPV1UpdatePayload{} -> f asBakerStakeThreshold
    TimeParametersCPV1UpdatePayload{} -> f' asTimeParameters
  where f v = (\AccessStructure{..} -> (accessPublicKeys, accessThreshold)) . v . level2Keys
        f' v = h . v . level2Keys
        g v = (\HigherLevelKeys{..} -> (Set.fromList $ [0..(fromIntegral $ Vec.length hlkKeys) - 1], hlkThreshold)) . v
        h :: AccessStructureForCPV1 cpv -> (Set.Set UpdateKeyIndex, UpdateKeysThreshold)
        h (AccessStructureForCPV1Some AccessStructure{..}) = (accessPublicKeys, accessThreshold)
        h AccessStructureForCPV1None = (Set.empty, 1) 
          -- The latter case happens if the UpdateKeysCollection is used with chain parameter version 0 but the update payload is
          -- is a cooldown paramater update or a time parameter update, which only exists in chain parameter version 1.
          -- Therefore, the empty set with threshold 1 is returned so that checkEnoughKeys will return false in this case.

-- |Extract the vector of public keys that are authorized for this kind of update. Note
-- that for a level 2 update it will return the whole set of level 2 keys.
extractPubKeys :: UpdatePayload -> UpdateKeysCollection cpv -> Vec.Vector UpdatePublicKey
extractPubKeys p =
  case p of
    RootCPV0UpdatePayload{} -> hlkKeys . rootKeys
    RootCPV1UpdatePayload{} -> hlkKeys . rootKeys
    Level1CPV0UpdatePayload{} -> hlkKeys . level1Keys
    Level1CPV1UpdatePayload{} -> hlkKeys . level1Keys
    _ -> asKeys . level2Keys

-- |Check that an access structure authorizes the given key set, this means particularly
-- that all the keys are authorized and the number of keys is above the threshold.
checkEnoughKeys ::
  -- |Set of known key indices.
  (Set.Set UpdateKeyIndex, UpdateKeysThreshold) ->
  -- |Set of key indices that signed the update.
  Set.Set UpdateKeyIndex ->
  Bool
checkEnoughKeys (knownIndices, thr) ks =
  let numOfAuthorizedKeysReceived = Set.size (ks `Set.intersection` knownIndices) in
    numOfAuthorizedKeysReceived >= fromIntegral thr
    && numOfAuthorizedKeysReceived == Set.size ks

--------------------
-- * Signatures
--------------------

-- |Hash of an update instruction, as used for signing.
newtype UpdateInstructionSignHashV0 = UpdateInstructionSignHashV0 {v0UpdateInstructionSignHash :: SHA256.Hash}
  deriving newtype (Eq, Ord, Show, Serialize, AE.ToJSON, AE.FromJSON, AE.FromJSONKey, AE.ToJSONKey, Read, Hashable)

-- |Alias for 'UpdateInstructionSignHashV0'.
type UpdateInstructionSignHash = UpdateInstructionSignHashV0

-- |Construct an 'UpdateInstructionSignHash' from the serialized header and payload of
-- an update instruction.
makeUpdateInstructionSignHash ::
    ByteString
    -- ^Serialized update instruction header and payload
    -> UpdateInstructionSignHash
makeUpdateInstructionSignHash body = UpdateInstructionSignHashV0 (SHA256.hash body)

-- |Signatures on an update instruction.
-- The serialization of 'UpdateInstructionSignatures' is uniquely determined.
-- It can't be empty and in that case will be rejected when parsing.
newtype UpdateInstructionSignatures = UpdateInstructionSignatures {
  signatures :: Map.Map UpdateKeyIndex Signature
  } deriving newtype (Eq, Show)

instance Serialize UpdateInstructionSignatures where
    put (UpdateInstructionSignatures m) = do
        putWord16be (fromIntegral (Map.size m))
        putSafeSizedMapOf put put m
    get = do
        sz <- getWord16be
        when (sz == 0) $ fail "signatures must not be empty"
        UpdateInstructionSignatures <$> getSafeSizedMapOf sz get get

-- |Check that a hash is correctly signed by the keys specified by the map indices.
checkCorrectSignatures ::
  UpdateInstructionSignHash ->
  Vec.Vector UpdatePublicKey ->
  UpdateInstructionSignatures ->
  Bool
checkCorrectSignatures signHash keyVec UpdateInstructionSignatures{..} =
  all checkSig $ Map.toList signatures
  where checkSig (i, sig) = case keyVec Vec.!? fromIntegral i of
                              Nothing -> False
                              Just verKey -> verify verKey (encode signHash) sig

--------------------
-- * Update instruction
--------------------

-- |An update instruction.
-- The header must have the correct length of the payload, and the
-- sign hash must be correctly computed (in the appropriate context).
data UpdateInstruction = UpdateInstruction {
        uiHeader :: !UpdateHeader,
        uiPayload :: !UpdatePayload,
        uiSignHash :: !UpdateInstructionSignHashV0,
        uiSignatures :: !UpdateInstructionSignatures
    }
    deriving (Eq, Show)


getUpdateInstruction :: SProtocolVersion pv -> Get UpdateInstruction
getUpdateInstruction spv = do
        ((uiHeader, uiPayload), body) <- getWithBytes $ do
            uiHeader <- get
            uiPayload <- isolate (fromIntegral (updatePayloadSize uiHeader)) $ getUpdatePayload spv
            return (uiHeader, uiPayload)
        let uiSignHash = makeUpdateInstructionSignHash body
        uiSignatures <- get
        return UpdateInstruction{..}

putUpdateInstruction :: Putter UpdateInstruction
putUpdateInstruction UpdateInstruction{..} = do
  put uiHeader
  putUpdatePayload uiPayload
  put uiSignatures

--------------------------------------
-- * Constructing Update Instructions
--------------------------------------

-- |An update instruction without signatures and payload length.
-- This is used for constructing an update instruction.
data RawUpdateInstruction = RawUpdateInstruction {
        ruiSeqNumber :: UpdateSequenceNumber,
        ruiEffectiveTime :: TransactionTime,
        ruiTimeout :: TransactionTime,
        ruiPayload :: UpdatePayload
    } deriving (Eq, Show)

$(deriveJSON defaultOptions{fieldLabelModifier = firstLower . drop 3} ''RawUpdateInstruction)

-- |Serialize a 'RawUpdateInstruction'; used for signing.
putRawUpdateInstruction :: Putter RawUpdateInstruction
putRawUpdateInstruction RawUpdateInstruction{..} = do
        put ruiSeqNumber
        put ruiEffectiveTime
        put ruiTimeout
        putNested putPayloadSize (putUpdatePayload ruiPayload)
    where
        putPayloadSize l = put (fromIntegral l :: PayloadSize)

-- |Produce a signature for an update instruction with the given 'UpdateInstructionSignHash'
-- using the supplied keys.
signUpdateInstruction ::
  -- |The hash to sign.
  UpdateInstructionSignHash ->
  -- |The map of keys to use for signing.
  Map.Map UpdateKeyIndex KeyPair ->
  UpdateInstructionSignatures
signUpdateInstruction sh =
  UpdateInstructionSignatures . fmap (\kp -> sign kp (encode sh))

-- |Make an 'UpdateInstruction' by signing a 'RawUpdateInstruction' with the given keys.
makeUpdateInstruction ::
  -- |The raw update instruction
  RawUpdateInstruction ->
  -- |The keys to be used to sign this instruction.
  Map.Map UpdateKeyIndex KeyPair ->
  UpdateInstruction
makeUpdateInstruction rui@RawUpdateInstruction{..} keys = UpdateInstruction {
            uiHeader = UpdateHeader {
                    updateSeqNumber = ruiSeqNumber,
                    updateEffectiveTime = ruiEffectiveTime,
                    updateTimeout = ruiTimeout,
                    updatePayloadSize = fromIntegral (BS.length (runPut $ putUpdatePayload ruiPayload))
                },
            uiPayload = ruiPayload,
            ..
        }
    where
      uiSignHash = makeUpdateInstructionSignHash (runPut $ putRawUpdateInstruction rui)
      uiSignatures = signUpdateInstruction uiSignHash keys

----------------
-- * Validation
----------------

-- |Check if an update is authorized by the given 'UpdateKeysCollection'.
-- That is, it must have signatures from at least the required threshold of
-- those authorized to perform the given update, and all signatures must be
-- valid and authorized.
checkAuthorizedUpdate
    :: UpdateKeysCollection cpv
    -- ^Current authorizations
    -> UpdateInstruction
    -- ^Instruction to verify
    -> Bool
checkAuthorizedUpdate ukc UpdateInstruction{uiSignatures=u@UpdateInstructionSignatures{..},..} =
      -- check number of authorized keys is above threshold
      checkEnoughKeys (extractKeysIndices uiPayload ukc) (Map.keysSet signatures)
      -- check signatures validate
      && checkCorrectSignatures uiSignHash (extractPubKeys uiPayload ukc) u

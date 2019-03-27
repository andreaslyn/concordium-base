{-# LANGUAGE DeriveGeneric, GeneralizedNewtypeDeriving, ForeignFunctionInterface #-}
{- | This module implements a dummy verifiable random function.
     The implementation is intended to immitate the behaviour of
     a real implementation, but does not provide any security.
-}
module Concordium.Crypto.VRF(
    PublicKey,
    PrivateKey,
    newPrivKey,
    pubKey,
    KeyPair(..),
    Hash,
    Proof,
    randomKeyPair,
    newKeyPair,
    --hash,
    prove,
    proofToHash,
    verify,
    verifyKey,
    hashToDouble,
    hashToInt,
    test
) where

import           Concordium.Crypto.ByteStringHelpers
import           Data.String.Builder
import           Data.ByteString.Builder
import           Data.ByteString            (ByteString)
import qualified Data.ByteString            as B
import qualified Data.ByteString.Lazy       as L
import           Data.ByteString.Internal   (create, toForeignPtr)
import           Foreign.Ptr
import           Foreign.ForeignPtr
import           Data.Word
import           System.IO.Unsafe
import           Control.Monad
import           Foreign.Marshal.Array
import           Foreign.Marshal.Alloc
import           Data.Serialize
import           Foreign.C.Types
import           Data.IORef
import           GHC.Generics
import           Data.Maybe
import           Numeric
import           Text.Printf
import           Concordium.Crypto.SHA256
import           System.Random

foreign import ccall "ec_vrf_ed25519-sha256.h priv_key" c_priv_key :: Ptr Word8 -> IO CInt
foreign import ccall "ec_vrf_ed25519-sha256.h public_key" c_public_key :: Ptr Word8 -> Ptr Word8 -> IO CInt
foreign import ccall "ec_vrf_ed25519-sha256.h ecvrf_prove" c_prove :: Ptr Word8 -> Ptr Word8 -> Ptr Word8 -> Ptr Word8 -> Word32-> IO () 
foreign import ccall "ec_vrf_ed25519-sha256.h ecvrf_proof_to_hash" c_proof_to_hash :: Ptr Word8 -> Ptr Word8 -> IO CInt
foreign import ccall "ec_vrf_ed25519-sha256.h ecvrf_verify_key" c_verify_key :: Ptr Word8 -> IO CInt
foreign import ccall "ec_vrf_ed25519-sha256.h ecvrf_verify" c_verify :: Ptr Word8 -> Ptr Word8 -> Ptr Word8 -> Word32-> IO CInt


privKeyToHex :: PrivateKey -> String
privKeyToHex (PrivateKey sk) = byteStringToHex sk

pubKeyToHex :: PublicKey -> String
pubKeyToHex (PublicKey pk) = byteStringToHex pk

-- PublicKey 32 bytes
data PublicKey = PublicKey ByteString
    deriving (Eq, Ord, Generic)
instance Serialize PublicKey where

-- PrivateKey 32 bytes
data PrivateKey = PrivateKey ByteString
    deriving (Eq, Generic)

instance Serialize PrivateKey where


newtype Proof = Proof Hash
    deriving (Eq, Generic, Serialize, Show)

data KeyPair = KeyPair {
    privateKey :: PrivateKey,
    publicKey :: PublicKey
} deriving (Eq, Generic)

instance Serialize KeyPair

randomKeyPair :: RandomGen g => g -> (KeyPair, g)
randomKeyPair gen = (key, gen')
        where
            (gen0, gen') = split gen
            privKey = PrivateKey $ B.pack $ take 32 $ randoms gen0
            key = KeyPair privKey (unsafePerformIO $ pubKey privKey)


    {-
newKeyPair :: IO (PrivateKey, PublicKey)
newKeyPair = do maybeSk <- newPrivKey 
                case maybeSk of
                  Nothing -> return Nothing
                  Just sk -> do maybePk <- pubKey sk
                                case maybePk of 
                                  Nothing -> return Nothing
                                  Just pk -> do _ <- putStrLn(privKeyToHex sk)
                                                _ <- putStrLn(pubKeyToHex pk) 
                                                return (Just (sk,  pk))

-}

newKeyPair :: IO KeyPair
newKeyPair = do sk <- newPrivKey 
                pk <- pubKey sk
                return (KeyPair sk pk)

newPrivKey :: IO PrivateKey
newPrivKey = 
    do suc <- newIORef (0::Int)
       sk <- create 32 $ \priv -> 
           do rc <-  c_priv_key priv 
              case rc of
                   1 ->  do writeIORef suc 1 
                   _ ->  do writeIORef suc 0 
       suc' <- readIORef suc
       case suc' of
           0 -> error "Private key generation failed"
           _ -> return (PrivateKey sk)

pubKey :: PrivateKey -> IO PublicKey
pubKey (PrivateKey sk) = do suc <- newIORef (0::Int)
                            pk  <- create 32 $ \pub -> 
                                 do pc <- withByteStringPtr sk $ \y -> c_public_key pub y
                                    if (pc == 1) 
                                       then writeIORef suc 1
                                       else writeIORef suc 0
                            suc' <- readIORef suc
                            case suc' of 
                                  1 -> return (PublicKey pk)
                                  _ -> error "Public key generation failed"
                                 

test :: IO () 
test = do kp@(KeyPair sk pk) <- newKeyPair
          _ <- putStrLn("SK: " ++ privKeyToHex sk)
          _ <- putStrLn("PK: " ++ pubKeyToHex pk)
          _ <- putStrLn("MESSAGE:") 
          alpha <- B.getLine 
          let prf@(Proof (Hash b)) = prove kp alpha  
              valid = verify pk alpha prf 
              Hash h' = proofToHash prf 
           in
              putStrLn ("Proof: " ++ byteStringToHex b) >>
              putStrLn ("PK IS " ++ if verifyKey pk then "OK" else "BAD") >>
              putStrLn ("Verification: " ++ if valid then "VALID" else "INVALID") >>
              putStrLn ("Proof hash: " ++ byteStringToHex h')


prove :: KeyPair -> ByteString -> Proof
prove (KeyPair (PrivateKey sk) (PublicKey pk)) b = Proof $ Hash $ unsafeDupablePerformIO $
                                        create 80 $ \prf -> 
                                           withByteStringPtr pk $ \pk' -> 
                                               withByteStringPtr sk $ \sk' -> 
                                                   withByteStringPtr b $ \b' -> 
                                                       c_prove prf pk' sk' b' (fromIntegral $ B.length b)

verify :: PublicKey -> ByteString -> Proof -> Bool
verify (PublicKey pk) alpha (Proof (Hash prf)) = cIntToBool $ unsafeDupablePerformIO $ 
                                                withByteStringPtr pk $ \pk' ->
                                                   withByteStringPtr prf $ \pi' ->
                                                     withByteStringPtr alpha $ \alpha'->
                                                       c_verify pk' pi' alpha' (fromIntegral $ B.length alpha)
              where
                  cIntToBool x =  x > 0
                                                           
                                                   


proofToHash :: Proof -> Hash
proofToHash (Proof (Hash p)) =  Hash $ unsafeDupablePerformIO $ 
    create 32 $ \x -> 
        withByteStringPtr p $ \p' -> c_proof_to_hash x p' >> return()

verifyKey :: PublicKey -> Bool
verifyKey (PublicKey pk) =  x > 0 
            where
               x = unsafeDupablePerformIO $  withByteStringPtr pk $ \pk' -> c_verify_key pk'

-- |Convert a 'Hash' into a 'Double' value in the range [0,1].
-- This implementation takes the first 64-bit word (big-endian) and uses it
-- as the significand, with an exponent of -64.  Since the precision of a
-- 'Double' is only 53 bits, there is inevitably some loss.  This also means
-- that the outcome 1 is not possible.
hashToDouble :: Hash -> Double
hashToDouble (Hash  h) = case runGet getWord64be h of
    Left e -> error e
    Right w -> encodeFloat (toInteger w) (-64)


hashToInt :: Hash -> Int
hashToInt (Hash h) = case runGet getInt64be h of
    Left e -> error e
    Right i -> fromIntegral i



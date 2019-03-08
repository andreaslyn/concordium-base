{-# LANGUAGE ScopedTypeVariables #-}
module Data.FixedByteString where

import Foreign.ForeignPtr
import Foreign.Ptr
import GHC.ForeignPtr
import Foreign.Storable
import Foreign.Marshal.Utils
import Data.Word
import Data.Bits
import System.IO.Unsafe
import Control.Monad



class FixedLength a where
    -- |Returns the length (in bytes) of a @FixedByteString a@.
    -- The argument must not be evaluated.
    fixedLength :: a -> Int

-- |A fixed-length byte string.  The length of the byte string
-- is determined by the type parameter @a@, which should be an
-- instance of 'FixedLength', as @fixedLength (undefined :: a)@.
newtype FixedByteString a = FixedByteString (ForeignPtr Word8)

mallocFixedByteString :: forall a. (FixedLength a) => IO (FixedByteString a)
mallocFixedByteString = FixedByteString <$> mallocPlainForeignPtrBytes (fixedLength (undefined :: a))

create :: FixedLength a => (Ptr Word8 -> IO ()) -> IO (FixedByteString a)
create f = do
        fbs@(FixedByteString fp) <- mallocFixedByteString
        withForeignPtr fp f
        return fbs

unsafeCreate :: FixedLength a => (Ptr Word8 -> IO ()) -> FixedByteString a
unsafeCreate = unsafeDupablePerformIO . create

-- |Create a 'FixedByteString' from a list of bytes.  If the list is too short,
-- the remaining bytes are filled with @0@.  If it is too long, only the first
-- @fixedLength (undefined :: a)@ bytes are used.
fromBytes :: forall a. (FixedLength a) => [Word8] -> FixedByteString a
fromBytes = unsafeCreate . fill 0
    where
        limit = fixedLength (undefined :: a)
        fill n l ptr = when (n < limit) $
                    case l of
                        [] -> do
                            fillBytes (plusPtr ptr n) 0x00 (limit - n)
                        (b : bs) -> do
                            pokeByteOff ptr n b
                            fill (n+1) bs ptr

-- |Convert a 'FixedByteString' to a list of bytes.
toBytes :: forall a. (FixedLength a) => FixedByteString a -> [Word8]
toBytes (FixedByteString fbs) = toB 0
    where
        len = fixedLength (undefined :: a)
        toB n
            | n >= len = []
            | otherwise = getB n : toB (n+1)
        getB n = unsafeDupablePerformIO $ withForeignPtr fbs (\p -> peekByteOff p n)


-- |Create a 'FixedByteString' from a list of bytes in reverse order.
-- If the list is too short, the remaining bytes are filled with @0@.
-- If it is too long, only the first @fixedLength (undefined :: a)@ 
-- bytes are used.
fromReversedBytes :: forall a. (FixedLength a) => [Word8] -> FixedByteString a
fromReversedBytes = unsafeCreate . fill (limit - 1)
    where
        limit = fixedLength (undefined :: a)
        fill n l ptr = when (n >= 0) $
                    case l of
                        [] -> do
                            fillBytes ptr 0x00 (n+1)
                        (b : bs) -> do
                            pokeByteOff ptr n b
                            fill (n-1) bs ptr

-- |Convert a 'FixedByteString' to a list of bytes in reverse order.
toReversedBytes :: forall a. (FixedLength a) => FixedByteString a -> [Word8]
toReversedBytes (FixedByteString fbs) = toB (len-1)
    where
        len = fixedLength (undefined :: a)
        toB n
            | n < 0 = []
            | otherwise = getB n : toB (n-1)
        getB n = unsafeDupablePerformIO $ withForeignPtr fbs (\p -> peekByteOff p n)

getByte :: forall a. (FixedLength a) => FixedByteString a -> Int -> Word8
getByte (FixedByteString fbs) n
    | n < 0 = error $ "getByte: cannot get a negative index (" ++ show n ++ ")"
    | n >= (fixedLength (undefined :: a)) = error $ "getByte: index (" ++ show n ++ ") out of bounds"
    | otherwise = unsafeDupablePerformIO $ withForeignPtr fbs (\p -> peekByteOff p n)

instance FixedLength a => Storable (FixedByteString a) where
    sizeOf _ = fixedLength (undefined :: a)
    alignment _ = 1
    peek ptr = create (\p' -> copyBytes p' (castPtr ptr) (fixedLength (undefined :: a)))
    poke ptr (FixedByteString fbs) = withForeignPtr fbs (\p' -> copyBytes ptr (castPtr p') (fixedLength (undefined :: a)))

-- |Convert an 'Integer' to a 'FixedByteString'.  The encoding is big endian and modulo @2 ^ (8 * fixedLength undefined)@.
encodeInteger :: forall a. (FixedLength a) => Integer -> FixedByteString a
encodeInteger z0 = unsafeCreate (initBytes z0 (fixedLength (undefined :: a) - 1))
    where
        initBytes z off ptr
            | off >= 0 = do
                pokeByteOff ptr off (fromInteger z :: Word8)
                initBytes (shiftR z 8) (off - 1) ptr
            | otherwise = return ()

decodeIntegerUnsigned :: forall a. (FixedLength a) => FixedByteString a -> Integer
decodeIntegerUnsigned (FixedByteString fbs) = unsafeDupablePerformIO $ withForeignPtr fbs (doDecode 0 0)
    where
        len = fixedLength (undefined :: a)
        doDecode i v ptr
            | i >= len = return v
            | otherwise = do
                (b :: Word8) <- peekByteOff ptr i
                doDecode (i+1) (shiftL v 8 .|. toInteger b) ptr

decodeIntegerSigned :: forall a. (FixedLength a) => FixedByteString a -> Integer
decodeIntegerSigned (FixedByteString fbs) = unsafeDupablePerformIO $ withForeignPtr fbs (doDecode 0 0)
    where
        len = fixedLength (undefined :: a)
        doDecode i v ptr
            | i >= len = return v
            | i == 0 = do
                (b :: Word8) <- peekByteOff ptr i
                if testBit b 8 then
                    doDecode 1 (shiftL (-1) 8 .|. toInteger b) ptr
                else
                    doDecode 1 (toInteger b) ptr
            | otherwise = do
                (b :: Word8) <- peekByteOff ptr i
                doDecode (i+1) (shiftL v 8 .|. toInteger b) ptr

instance (FixedLength a) => Eq (FixedByteString a) where
    f1 == f2 = toBytes f1 == toBytes f2

instance (FixedLength a) => Ord (FixedByteString a) where
    compare f1 f2 = compare (toBytes f1) (toBytes f2)

mapBytes :: forall a. (FixedLength a) => (Word8 -> Word8) -> FixedByteString a -> FixedByteString a
mapBytes f fbs = unsafeCreate (doMap (toBytes fbs))
    where
        doMap [] _ = return ()
        doMap (b : bs) ptr = poke ptr (f b) >> doMap bs (plusPtr ptr 1)

zipWithBytes :: forall a. (FixedLength a) => (Word8 -> Word8 -> Word8) -> FixedByteString a -> FixedByteString a -> FixedByteString a
zipWithBytes f fbs1 fbs2 = fromBytes $ zipWith f (toBytes fbs1) (toBytes fbs2)

instance (FixedLength a) => Bounded (FixedByteString a) where
    minBound = unsafeCreate $ \p -> fillBytes p 0x00 (fixedLength (undefined :: a))
    maxBound = unsafeCreate $ \p -> fillBytes p 0xff (fixedLength (undefined :: a))

instance (FixedLength a) => Enum (FixedByteString a) where
    succ fbs = if overflow then error "succ: overflow" else fromBytes newBytes
        where
            doSucc b (True, l) = (b == 0xff, (b+1) : l)
            doSucc b (False, l) = (False, b : l)
            (overflow, newBytes) = foldr doSucc (True, []) (toBytes fbs)
    pred fbs = if underflow then error "pred: underflow" else fromBytes newBytes
        where
            doPred b (True, l) = (b == 0x00, (b-1) : l)
            doPred b (False, l) = (False, b : l)
            (underflow, newBytes) = foldr doPred (True, []) (toBytes fbs)
    toEnum = encodeInteger . toInteger
    fromEnum = fromInteger . decodeIntegerSigned

instance (FixedLength a) => Bits (FixedByteString a) where
    (.&.) = zipWithBytes (.&.) 
    (.|.) = zipWithBytes (.|.)
    xor = zipWithBytes xor
    complement = mapBytes complement
    shiftL fbs n = fromReversedBytes $
        (take (n `div` 8) (repeat 0)) ++ fst (foldr (\b (r, carry) -> ((shiftL b (n `mod` 8) .|. carry) : r, shiftR b (8 - (n `mod` 8)))) ([], 0) (toReversedBytes fbs))
    -- We treat FixedByteStrings as unsigned, meaning shiftR does not do sign extension
    shiftR fbs n = fromBytes $
        (take (n `div` 8) (repeat 0)) ++ fst (foldr (\b (r, carry) -> ((shiftR b (n `mod` 8) .|. carry) : r, shiftL b (8 - (n `mod` 8)))) ([], 0) (toBytes fbs))
    rotateL fbs n0 = shiftL fbs n .|. shiftR fbs (bitLen - n)
        where
            bitLen = (8 * fixedLength (undefined :: a))
            n = n0 `mod` bitLen
    rotateR fbs n0 = shiftR fbs n .|. shiftL fbs (bitLen - n)
        where
            bitLen = (8 * fixedLength (undefined :: a))
            n = n0 `mod` bitLen
    isSigned _ = False
    bitSize _ = 8 * fixedLength (undefined :: a)
    bitSizeMaybe _ = Just (8 * fixedLength (undefined :: a))
    popCount fbs = sum (popCount <$> toBytes fbs)
    testBit fbs n
            | n >= 8 * fixedLength (undefined :: a) = False
            | otherwise = testBit (getByte fbs ((n `div` 8) `mod` (fixedLength (undefined :: a)))) (n `mod` 8)
    bit = fromReversedBytes . bitBytes
        where
            bitBytes n
                | n < 0 = []
                | n < 8 = [bit n]
                | otherwise = 0 : bitBytes (n - 8)

{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE DeriveGeneric #-}

module Distribution.Version (
  -- * Package versions
  Version,
  mkVersion,
  mkVersion1,
  mkVersion2,

  mkVersion',
  versionNumbers,
  versionNumbersLazy,
  nullVersion,
  alterVersion,

  cmpLazy,
  cmpOpt,
 ) where

import qualified Data.Version as Base
import Data.Data
import GHC.Generics
import Control.DeepSeq
import Data.Bits (shiftL, shiftR, (.|.), (.&.))
import Data.Word

-- -----------------------------------------------------------------------------
-- Versions


data Version = PV0 {-# UNPACK #-} !Word64
             | PV1 !Int [Int]
             deriving (Data,Eq,Generic,Show,Read,Typeable)

cmpOpt :: Version -> Version -> Ordering
cmpOpt (PV0 x)    (PV0 y) = compare x y
cmpOpt (PV1 x xs) (PV1 y ys) = case compare x y of
  EQ -> compare xs ys
  c  -> c
cmpOpt (PV0 w) (PV1 y ys) = case compare x y of
  EQ -> compare [x2,x3,x4] ys
  c  -> c
  where
    x  = fromIntegral ((w `shiftR` 48) .&. 0xffff) - 1
    x2 = fromIntegral ((w `shiftR` 32) .&. 0xffff) - 1
    x3 = fromIntegral ((w `shiftR` 16) .&. 0xffff) - 1
    x4 = fromIntegral               (w .&. 0xffff) - 1
cmpOpt (PV1 x xs) (PV0 w) = case compare x y of
  EQ -> compare xs [y2,y3,y4]
  c  -> c
  where
    y  = fromIntegral ((w `shiftR` 48) .&. 0xffff) - 1
    y2 = fromIntegral ((w `shiftR` 32) .&. 0xffff) - 1
    y3 = fromIntegral ((w `shiftR` 16) .&. 0xffff) - 1
    y4 = fromIntegral               (w .&. 0xffff) - 1

instance Ord Version where
    compare = cmpOpt
    -- compare (PV0 x) (PV0 y) = compare x y
    -- compare xv       yv     = compare (versionNumbers xv) (versionNumbers yv)

instance NFData Version where
    rnf (PV0 _) = ()
    rnf (PV1 _ ns) = rnf ns

cmpLazy (PV0 x) (PV0 y) = compare x y
cmpLazy xv       yv     = compare (versionNumbersLazy xv) (versionNumbersLazy yv)


{-
instance Binary Version

instance Text Version where
  disp ver
    = Disp.hcat (Disp.punctuate (Disp.char '.')
                                (map Disp.int $ versionNumbers ver))

  parse = do
      branch <- Parse.sepBy1 parseNat (Parse.char '.')
                -- allow but ignore tags:
      _tags  <- Parse.many (Parse.char '-' >> Parse.munch1 isAlphaNum)
      return (mkVersion branch)
    where
      parseNat = read `fmap` Parse.munch1 isDigit
-}

-- | original version
mkVersion :: [Int] -> Version
-- TODO: add validity check; disallow 'mkVersion []' (we have
-- 'nullVersion' for that)
mkVersion ns = case ns of
    [] -> nullVersion
    [v1]          | v1 <= 0xfffe
      -> PV0 (mkW64 (v1+1) 0 0 0)
    [v1,v2]       | v1 <= 0xfffe, v2 <= 0xfffe
      -> PV0 (mkW64 (v1+1) (v2+1) 0 0)
    [v1,v2,v3]    | v1 <= 0xfffe, v2 <= 0xfffe, v3 <= 0xfffe
      -> PV0 (mkW64 (v1+1) (v2+1) (v3+1)  0)
    [v1,v2,v3,v4] | v1 <= 0xfffe, v2 <= 0xfffe, v3 <= 0xfffe, v4 <= 0xfffe
      -> PV0 (mkW64 (v1+1) (v2+1) (v3+1) (v4+1))
    v1:vs -> PV1 v1 vs
  where
    {-# INLINABLE mkW64 #-}
    mkW64 :: Int -> Int -> Int -> Int -> Word64
    mkW64 v1 v2 v3 v4 =     (fromIntegral v1 `shiftL` 48)
                        .|. (fromIntegral v2 `shiftL` 32)
                        .|. (fromIntegral v3 `shiftL` 16)
                        .|.  fromIntegral v4

mkVersion1 :: [Int] -> Maybe Version
mkVersion1 ns = case ns of
    [] -> Nothing

    [v1]
      | v1 < 0 -> Nothing
      | v1 <= 0xfffe
        -> Just $! PV0 (mkW64 (v1+1) 0 0 0)
      | otherwise -> Just (PV1 v1 [])

    [v1,v2]
      | not (v1 >= 0 && v2 >= 0) -> Nothing
      | v1 <= 0xfffe, v2 <= 0xfffe
        -> Just $! PV0 (mkW64 (v1+1) (v2+1) 0 0)
      | otherwise -> Just (PV1 v1 [v2])

    [v1,v2,v3]
      | not (v1 >= 0 && v2 >= 0 && v3 >= 0) -> Nothing
      | v1 <= 0xfffe, v2 <= 0xfffe, v3 <= 0xfffe
        -> Just $! PV0 (mkW64 (v1+1) (v2+1) (v3+1) 0)
      | otherwise -> Just (PV1 v1 [v2,v3])

    [v1,v2,v3,v4]
      | not (v1 >= 0 && v2 >= 0 && v3 >= 0 && v4 >= 0) -> Nothing
      | v1 <= 0xfffe, v2 <= 0xfffe, v3 <= 0xfffe, v4 <= 0xfffe
        -> Just $! PV0 (mkW64 (v1+1) (v2+1) (v3+1) (v4+1))
      | otherwise -> Just (PV1 v1 [v2,v3,v4])

    v1:v2:v3:v4:v5:vs
      | (v1 .|. v2 .|. v3 .|. v4 .|. v5 < 0) || (any (<0) vs) -> Nothing
      | otherwise -> Just (PV1 v1 (v2:v3:v4:v5:vs))
  where
    {-# INLINE mkW64 #-}
    mkW64 :: Int -> Int -> Int -> Int -> Word64
    mkW64 v1 v2 v3 v4 =     (fromIntegral v1 `shiftL` 48)
                        .|. (fromIntegral v2 `shiftL` 32)
                        .|. (fromIntegral v3 `shiftL` 16)
                        .|.  fromIntegral v4


mkVersion2 :: [Int] -> Maybe Version
mkVersion2 ns = case ns of
    [] -> Nothing

    [v1]
      | v1 < 0 -> Nothing
      | v1 <= 0xfffe
        -> Just $! PV0 (mkW64 (v1+1) 0 0 0)
      | otherwise -> Just (PV1 v1 [])

    [v1,v2]
      | v1 .|. v2 < 0 -> Nothing
      | inW16 ((v1+1) .|. (v2+1))
        -> Just $! PV0 (mkW64 (v1+1) (v2+1) 0 0)
      | otherwise -> Just (PV1 v1 [v2])

    [v1,v2,v3]
      | v1 .|. v2 .|. v3 < 0 -> Nothing
      | inW16 ((v1+1) .|. (v2+1) .|. (v3+1))
        -> Just $! PV0 (mkW64 (v1+1) (v2+1) (v3+1) 0)
      | otherwise -> Just (PV1 v1 [v2,v3])

    [v1,v2,v3,v4]
      | v1 .|. v2 .|. v3 .|. v4 < 0 -> Nothing
      | inW16 ((v1+1) .|. (v2+1) .|. (v3+1) .|. (v4+1))
        -> Just $! PV0 (mkW64 (v1+1) (v2+1) (v3+1) (v4+1))
      | otherwise -> Just (PV1 v1 [v2,v3,v4])

    v1:v2:v3:v4:v5:vs
      | (v1 .|. v2 .|. v3 .|. v4 .|. v5 < 0) || (any (<0) vs) -> Nothing
      | otherwise -> Just (PV1 v1 (v2:v3:v4:v5:vs))
  where
    {-# INLINE mkW64 #-}
    mkW64 :: Int -> Int -> Int -> Int -> Word64
    mkW64 v1 v2 v3 v4 =     (fromIntegral v1 `shiftL` 48)
                        .|. (fromIntegral v2 `shiftL` 32)
                        .|. (fromIntegral v3 `shiftL` 16)
                        .|.  fromIntegral v4

    inW16 x = (fromIntegral x :: Word) <= 0xffff
    -- inW16 x = x <= 0xffff && x >= 0

-- | Variant of 'Version' which converts a "Data.Version" 'Version'
-- into Cabal's 'Version' type.
--
-- @since 2.0
mkVersion' :: Base.Version -> Version
mkVersion' = mkVersion . Base.versionBranch

-- | Unpack 'Version' into list of version number components.
--
-- This is the inverse to 'mkVersion', so the following holds:
--
-- > (versionNumbers . mkVersion) vs == vs
--
-- @since 2.0
versionNumbers :: Version -> [Int]
versionNumbers (PV1 n ns) = n:ns
versionNumbers (PV0 w)
  | v1 < 0    = []
  | v2 < 0    = [v1]
  | v3 < 0    = [v1,v2]
  | v4 < 0    = [v1,v2,v3]
  | otherwise = [v1,v2,v3,v4]
  where
    v1 = fromIntegral ((w `shiftR` 48) .&. 0xffff) - 1
    v2 = fromIntegral ((w `shiftR` 32) .&. 0xffff) - 1
    v3 = fromIntegral ((w `shiftR` 16) .&. 0xffff) - 1
    v4 = fromIntegral (w .&. 0xffff) - 1


versionNumbersLazy :: Version -> [Int]
versionNumbersLazy (PV1 n ns) = n:ns
versionNumbersLazy (PV0 w) = go1
  where
    go1 = if v1 < 0 then [] else v1 : go2
    go2 = if v2 < 0 then [] else v2 : go3
    go3 = if v3 < 0 then [] else v3 : go4
    go4 = if v4 < 0 then [] else [v4]

    v1 = fromIntegral ((w `shiftR` 48) .&. 0xffff) - 1
    v2 = fromIntegral ((w `shiftR` 32) .&. 0xffff) - 1
    v3 = fromIntegral ((w `shiftR` 16) .&. 0xffff) - 1
    v4 = fromIntegral (w .&. 0xffff) - 1


-- | Constant representing the special /null/ 'Version'
--
-- The 'nullVersion' compares (via 'Ord') as less than every proper
-- 'Version' value.
--
-- @since 2.0
nullVersion :: Version
-- TODO: at some point, 'mkVersion' may disallow creating /null/
-- 'Version's
nullVersion = PV0 0

-- | Apply function to list of version number components
--
-- > alterVersion f == mkVersion . f . versionNumbers
--
-- @since 2.0
alterVersion :: ([Int] -> [Int]) -> Version -> Version
alterVersion f = mkVersion . f . versionNumbers

-- internal helper
validVersion :: Version -> Bool
validVersion v = v /= nullVersion && all (>=0) (versionNumbers v)

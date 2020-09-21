module Åre where

import Prelude (sequence, (<$>), (.), (<), Maybe(..), (<>), ($), (||), (==), Bool(..), otherwise, not, Show, String)
import Numeric (showHex)
import Data.Word (Word8)
import Data.Maybe (fromMaybe)
import Data.List (intercalate)

type Identifier = String

data LC
  = Term Identifier
  | App LC LC
  | Abs Identifier LC
  deriving Show

data ExtLC
  = Term' Identifier
  | App' ExtLC ExtLC
  | Abs' Identifier ExtLC
  | I'
  | K'
  | S'
  deriving Show

isFree :: Identifier -> ExtLC -> Bool
isFree x (Term' t) = x == t
isFree x (App' e1 e2) = isFree x e1 || isFree x e2
isFree x (Abs' arg e) | x == arg  = False
                      | otherwise = isFree x e
isFree _ _ = False

bracket :: ExtLC -> ExtLC
bracket (Term' t)                          = Term' t
bracket (App' e1 e2)                       = App' (bracket e1) (bracket e2)
bracket (Abs' arg e) | not (isFree arg e)  = App' K' (bracket e)
bracket e@(Abs' arg (Term' t)) | arg == t  = I'
                               | otherwise = e -- impossible, (Term' t) is guaranteed to contain `arg`
bracket (Abs' arg (App' e1 e2))            = let l = bracket (Abs' arg e1)
                                                 r = bracket (Abs' arg e2)
                                              in App' (App' S' l) r

bracket (Abs' arg e@(Abs' _ _))            = bracket (Abs' arg (bracket e))
-- bracket t@(Abs' _ I') = t
-- bracket t@(Abs' _ K') = t
-- bracket t@(Abs' _ S') = t
-- bracket I' = I'
-- bracket K' = K'
-- bracket S' = S'
bracket x                                  = x

data SKITree
  = I
  | K
  | S
  | A SKITree SKITree
  deriving Show

data ExtSKITree
  = I''
  | K''
  | S''
  | AK ExtSKITree
  | AS1 ExtSKITree
  | AS2 ExtSKITree ExtSKITree
  | A'' ExtSKITree ExtSKITree
  deriving Show

toExtSKITree :: ExtLC -> ExtSKITree
toExtSKITree I' = I''
toExtSKITree K' = K''
toExtSKITree S' = S''
toExtSKITree (App' e1 e2) = A'' (toExtSKITree e1) (toExtSKITree e2)

evalSKITree :: ExtSKITree -> ExtSKITree
evalSKITree I''               = I''
evalSKITree K''               = K''
evalSKITree S''               = S''
evalSKITree closure@(AK _)    = closure
evalSKITree closure@(AS1 _)   = closure
evalSKITree closure@(AS2 _ _) = closure
evalSKITree (A'' I'' x)       = evalSKITree x
evalSKITree (A'' K'' x)       = AK (evalSKITree x)
evalSKITree (A'' S'' f)       = AS1 (evalSKITree f)
evalSKITree (A'' (AK x) _)    = evalSKITree x
evalSKITree (A'' (AS1 f) g)   = AS2 f g
evalSKITree (A'' (AS2 f g) x) = evalSKITree $ A'' (A'' f x) (A'' g x)
evalSKITree (A'' t u)         = evalSKITree (A'' (evalSKITree t) (evalSKITree u))

one :: ExtLC
one = Abs' "f" (Abs' "x" (App' (Term' "f") (Term' "x")))

succ :: ExtLC
succ = Abs' "n" (Abs' "f" (Abs' "x" (App' (Term' "f") (App' (App' (Term' "n") (Term' "f")) (Term' "x")))))

two :: ExtLC
two = Abs' "f" (Abs' "x" (App' (Term' "f") (App' (Term' "f") (Term' "x"))))

two' :: ExtLC
two' = App' succ one

i :: ExtLC
i = Abs' "x" (Term' "x")

k :: ExtLC
k = Abs' "x" (Abs' "y" (Term' "x"))

-- >>> evalSKITree $ toExtSKITree $ bracket (App' (App' two' K') I')
-- AK (AK I'')

toSKIList :: ExtSKITree -> [String]
toSKIList I''                     = ["I"]
toSKIList K''                     = ["K"]
toSKIList S''                     = ["S"]
-- toSKIList (A'' inner@(A'' _ _) v) = toSKIList inner <> toSKIList v <> ["A"]
toSKIList (A'' t u)               = toSKIList u <> toSKIList t <> ["A"]
toSKIList _                       = []

-- >>> toExtSKITree $ bracket (App' (App' k i) i)
-- A'' (A'' (A'' (A'' S'' (A'' K'' K'')) I'') I'') I''

toSKICmdSeq :: ExtLC -> [String]
toSKICmdSeq = toSKIList . toExtSKITree . bracket
-- >>> toSKICmdSeq (App' (App' k i) i)
-- ["I","I","I","K","K","A","S","A","A","A","A"]

-- >>> toSKICmdSeq (App' i (App' k i))
-- ["I","I","K","K","A","S","A","A","A","I","A"]


skiToCmdCode :: String -> Maybe Word8
skiToCmdCode "I" = Just 0
skiToCmdCode "K" = Just 1
skiToCmdCode "S" = Just 2
skiToCmdCode "A" = Just 3
skiToCmdCode _ = Nothing

-- >>> sequence $ skiToCmdCode <$> (toSKICmdSeq (App' (App' k i) i))
-- Just [0,0,0,1,1,3,2,3,3,3,3]

toHexCode :: Word8 -> String
toHexCode n | n < 0x10  = "0" <> hex
            | otherwise = hex
              where
                hex = showHex n ""

-- >>> toHexCode 5
-- "05"

-- >>> toHexCode 250
-- "fa"

toWASMDataSection :: ExtLC -> String
toWASMDataSection
  = ("\\" <>)
  . intercalate "\\"
  . (toHexCode <$>)
  . (fromMaybe [])
  . sequence
  . (skiToCmdCode <$>)
  . toSKICmdSeq

-- >>> toWASMDataSection (App' (App' k i) i)
-- "\\00\\00\\00\\01\\01\\03\\02\\03\\03\\03\\03"

-- >>> length $ toWASMDataSection (App' (App' k i) i)
-- 33

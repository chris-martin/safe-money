{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE MultiWayIf #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_HADDOCK hide #-}
{-# OPTIONS_GHC -Wno-redundant-constraints #-}

-- | This is an internal module. You may use stuff exported from here, but we
-- can't garantee their stability.
module Money.Internal
 ( -- * Dense monetary values
   Dense
 , denseCurrency
 , denseCurrency'
 , dense
 , dense'
 , denseFromDiscrete
 , denseFromDecimal
 , denseToDecimal
   -- * Discrete monetary values
 , Discrete
 , Discrete'
 , discrete
 , discreteCurrency
 , discreteCurrency'
 , discreteFromDense
 , discreteFromDecimal
 , discreteToDecimal
   -- * Currency scales
 , Scale
 , GoodScale
 , ErrScaleNonCanonical
 , scale
   -- * Currency exchange
 , ExchangeRate
 , exchangeRate
 , exchange
 , exchangeRateFromDecimal
 , exchangeRateToDecimal
 , exchangeRateToRational
 , exchangeRateRecip
   -- * Serializable representations
 , SomeDense
 , toSomeDense
 , mkSomeDense
 , mkSomeDense'
 , fromSomeDense
 , withSomeDense
 , someDenseCurrency
 , someDenseCurrency'
 , someDenseAmount
 , SomeDiscrete
 , toSomeDiscrete
 , mkSomeDiscrete
 , mkSomeDiscrete'
 , fromSomeDiscrete
 , withSomeDiscrete
 , someDiscreteCurrency
 , someDiscreteCurrency'
 , someDiscreteScale
 , someDiscreteAmount
 , SomeExchangeRate
 , toSomeExchangeRate
 , mkSomeExchangeRate
 , mkSomeExchangeRate'
 , fromSomeExchangeRate
 , withSomeExchangeRate
 , someExchangeRateSrcCurrency
 , someExchangeRateSrcCurrency'
 , someExchangeRateDstCurrency
 , someExchangeRateDstCurrency'
 , someExchangeRateRate
 -- * Misc
 , Approximation(Round, Floor, Ceiling, Truncate)
 , rationalToDecimal
 , rationalFromDecimal
 ) where

import Control.Applicative ((<|>), empty)
import Control.Category (Category((.), id))
import Control.DeepSeq (NFData)
import Control.Monad (guard, when)
import qualified Data.AdditiveGroup as AG
import qualified Data.Binary as Binary
import qualified Data.Char as Char
import Data.Constraint (Dict(Dict))
import Data.Functor (($>))
import Data.Foldable (for_)
import Data.Hashable (Hashable)
import qualified Data.List as List
import Data.Maybe (catMaybes, isJust, fromJust)
import Data.Monoid ((<>))
import Data.Proxy (Proxy(..))
import Data.Ratio ((%), numerator, denominator)
import qualified Data.Text as T
import qualified Data.VectorSpace as VS
import Data.Word (Word8)
import GHC.Exts (Constraint)
import qualified GHC.Generics as GHC
import GHC.TypeLits
  (Symbol, SomeSymbol(..), Nat, SomeNat(..), CmpNat, KnownSymbol, KnownNat,
   natVal, someNatVal, symbolVal, someSymbolVal)
import qualified GHC.TypeLits as GHC
import Numeric.Natural (Natural)
import Prelude hiding ((.), id)
import qualified Test.QuickCheck as QC
import qualified Text.ParserCombinators.ReadPrec as ReadPrec
import qualified Text.ParserCombinators.ReadP as ReadP
import qualified Text.Read as Read
import Unsafe.Coerce (unsafeCoerce)


--------------------------------------------------------------------------------
-- | 'Dense' represents a dense monetary value for @currency@ (usually a
-- ISO-4217 currency code, but not necessarily) as a rational number.
--
-- While monetary values associated with a particular currency are
-- discrete (e.g., an exact number of coins and bills), you can still treat
-- monetary values as dense while operating on them. For example, the half
-- of @USD 3.41@ is @USD 1.705@, which is not an amount that can't be
-- represented as a number of USD cents (the smallest unit that can
-- represent USD amounts). Nevertheless, if you do manage to represent @USD
-- 1.709@ somehow, and you eventually multiply @USD 1.705@ by @4@ for
-- example, then you end up with @USD 6.82@, which is again a value
-- representable as USD cents. In other words, 'Dense' monetary values
-- allow us to perform precise calculations deferring the conversion to a
-- 'Discrete' monetary values as much as posible. Once you are ready to
-- approximate a 'Dense' value to a 'Discrete' value you can use one
-- 'discreteFromDense'. Otherwise, using 'toRational' you can obtain a
-- precise 'Rational' representation.

-- Construct 'Dense' monetary values using 'dense', 'dense'',
-- 'denseFromDiscrete', 'denseFromDecimal'.
--
-- /WARNING/ if you want to treat a dense monetary value as a /Real/ number
-- like 'Float' or 'Double', then you are on your own. We can only
-- guarantee lossless manipulation of rational values, so you will need to
-- convert back and forth betwen the 'Rational' representation for 'Dense'
-- and your (likely lossy) representation for /Real/ numbers.
newtype Dense (currency :: Symbol) = Dense Rational
  deriving (Eq, Ord, Real, GHC.Generic)

-- | Notice that multiplication of 'Dense' values doesn't make sense:
--
-- @
-- ('*') :: 'Dense' currency -> 'Dense' currency -> 'Dense' currency
-- @
--
-- How is '*' implemented, then? It behaves as the /scalar multiplication/ of a
-- 'Dense' amount by a 'Rational' scalar. That is, you can think of '*' as
-- having one of the the following types:
--
-- @
-- ('*') :: 'Rational' -> 'Dense' currency -> 'Dense' currency
-- @
--
-- @
-- ('*') :: 'Dense' currency -> 'Rational' -> 'Dense' currency@
-- @
--
-- That is:
--
-- @
-- 'dense'' (1 '%' 4) '*' 'dense'' (1 '%' 2)  ==  'dense'' (1 '%' 8)
-- @
--
-- In fact, '*' functions exactly as 'Data.VectorSpace.*^' from the
-- 'Data.VectorSpace' instance.
--
-- @
-- ('*')  ==  ('Data.VectorSpace.*^')
-- @
--
-- @
-- ('*')  ==  'flip' ('Data.VectorSpace.*^')
-- @
deriving instance Num (Dense currency)

type family ErrFractionalDense :: Constraint where
  ErrFractionalDense
    = GHC.TypeError
      (('GHC.Text "The ") 'GHC.:<>:
       ('GHC.ShowType Dense) 'GHC.:<>:
       ('GHC.Text " type is deliberately not an instance of ") 'GHC.:<>:
       ('GHC.ShowType Fractional) 'GHC.:$$:
       ('GHC.Text "because functions like 'recip' and '/' can diverge.") 'GHC.:$$:
       ('GHC.Text "Temporarily convert the ") 'GHC.:<>:
       ('GHC.ShowType Dense) 'GHC.:<>:
       ('GHC.Text " value to a ") 'GHC.:<>:
       ('GHC.ShowType Rational) 'GHC.:$$:
       ('GHC.Text " if you know what you are doing."))

instance ErrFractionalDense => Fractional (Dense currency) where
  fromRational = undefined
  recip = undefined

-- |
-- @
-- > 'show' ('dense'' (1 '%' 3) :: 'Dense' \"USD\")
-- \"Dense \\\"USD\\\" 1%3\"
-- @
instance forall currency. KnownSymbol currency => Show (Dense currency) where
  showsPrec n = \(Dense r0) ->
    let c = symbolVal (Proxy :: Proxy currency)
    in showParen (n > 10) $
         showString "Dense " . showsPrec 0 c . showChar ' ' .
         showsPrec 0 (numerator r0) . showChar '%' .
         showsPrec 0 (denominator r0)

instance forall currency. KnownSymbol currency => Read (Dense currency) where
  readPrec = Read.parens $ do
    let c = symbolVal (Proxy :: Proxy currency)
    _ <- ReadPrec.lift (ReadP.string ("Dense " ++ show c ++ " "))
    maybe empty pure =<< fmap dense Read.readPrec

-- | Build a 'Dense' monetary value from a 'Rational' value.
--
-- For example, if you want to represent @USD 12.52316@, then you can use:
--
-- @
-- 'dense' (125316 '%' 10000)
-- @
--
-- Notice that 'dense' returns 'Nothing' in case the given 'Rational''s
-- denominator is zero, which although unlikely, it is possible if the
-- 'Rational' was unsafely constructed. When dealing with hardcoded or trusted
-- 'Rational' values, you can use 'dense'' instead of 'dense' which unsafely
-- constructs a 'Dense'.
dense :: Rational -> Maybe (Dense currency)
dense = \r ->
  if denominator r /= 0
  then Just (Dense r)
  else Nothing
{-# INLINE dense #-}

-- | Unsafely build a 'Dense' monetary value from a 'Rational' value. Contrary
-- to 'dense', this function *crashes* if the given 'Rational' has zero as a
-- denominator, which is something very unlikely to happen unless the given
-- 'Rational' was itself unsafely constructed. Other than that, 'dense' and
-- 'dense'' behave the same.
--
-- Prefer to use 'dense' when dealing with 'Rational' inputs from untrusted
-- sources.
--
-- @
-- 'denominator' x /= 0
--   ⇒ 'dense' x == 'Just' ('dense'' x)
-- @
--
-- @
-- 'denominator' x == 0
--   ⇒ 'undefined' == 'dense'' x
-- @
dense' :: Rational -> Dense currency
dense' = \r ->
  if denominator r /= 0
  then Dense r
  else error "dense': malformed Rational given (denominator is zero)."
{-# INLINABLE dense' #-}

-- | 'Dense' currency identifier.
--
-- @
-- > 'denseCurrency' ('dense'' 4 :: 'Dense' \"USD\")
-- \"USD\"
-- @
denseCurrency :: KnownSymbol currency => Dense currency -> T.Text
denseCurrency = T.pack . denseCurrency'
{-# INLINE denseCurrency #-}

-- | Like 'denseCurrency' but returns 'String'.
denseCurrency' :: KnownSymbol currency => Dense currency -> String
denseCurrency' = symbolVal
{-# INLINE denseCurrency' #-}

-- | 'Discrete' represents a discrete monetary value for a @currency@ expresed
-- as an integer amount of a particular @unit@. For example, with @currency ~
-- \"USD\"@ and @unit ~ \"cent\"@ you can represent United States Dollars to
-- their full extent.
--
-- @currency@ is usually a ISO-4217 currency code, but not necessarily.
--
-- Construct 'Discrete' values using 'discrete', 'fromIntegral', 'fromInteger',
-- 'discreteFromDense', 'discreteFromDecimal'.
--
-- For example, if you want to represent @GBP 21.05@, where the smallest
-- represetable unit for a GBP (United Kingdom Pound) is the /penny/, and 100
-- /pennies/ equal 1 GBP (i.e., @'Scale' \"GBP\" ~ '(100, 1)@), then you can
-- use:
--
-- @
-- 'discrete' 2105 :: 'Discrete' \"GBP\" \"penny\"
-- @
--
-- Because @2015 / 100 == 20.15@.
type Discrete (currency :: Symbol) (unit :: Symbol)
  = Discrete' currency (Scale currency unit)

-- | 'Discrete'' represents a discrete monetary value for a @currency@ expresed
-- as amount of @scale@, which is a rational number expressed as @(numerator,
-- denominator)@.
--
-- You'll be using 'Discrete' instead of 'Discrete'' most of the time, which
-- mentions the unit name (such as /cent/ or /centavo/) instead of explicitely
-- mentioning the unit scale.
newtype Discrete' (currency :: Symbol) (scale :: (Nat, Nat))
  = Discrete Integer

deriving instance GoodScale scale => Eq (Discrete' currency scale)
deriving instance GoodScale scale => Ord (Discrete' currency scale)
deriving instance GoodScale scale => Enum (Discrete' currency scale)
deriving instance GoodScale scale => Real (Discrete' currency scale)
deriving instance GoodScale scale => Integral (Discrete' currency scale)
deriving instance GoodScale scale => GHC.Generic (Discrete' currency scale)

-- | Notice that multiplication of 'Discrete'' values doesn't make sense:
--
-- @
-- ('*') :: 'Discrete'' currency scale -> 'Discrete'' currency scale -> 'Discrete'' currency scale
-- @
--
-- How is '*' implemented, then? It behaves as the /scalar multiplication/ of a
-- 'Discrete'' amount by an 'Integer' scalar. That is, you can think of '*' as
-- having one of the the following types:
--
-- @
-- ('*') :: 'Integer' -> 'Discrete'' currency scale -> 'Discrete'' currency scale
-- @
--
-- @
-- ('*') :: 'Discrete'' currency scale -> 'Integer' -> 'Discrete'' currency scale@
-- @
--
-- That is:
--
-- @
-- 'discrete' 2 '*' 'discrete' 4  ==  'discrete' 8
-- @
--
-- In fact, '*' functions exactly as 'Data.VectorSpace.*^' from the
-- 'Data.VectorSpace' instance.
--
-- @
-- ('*')  ==  ('Data.VectorSpace.*^')
-- @
--
-- @
-- ('*')  ==  'flip' ('Data.VectorSpace.*^')
-- @
deriving instance GoodScale scale => Num (Discrete' currency scale)

-- |
-- @
-- > 'show' ('discrete' 123 :: 'Discrete' \"USD\" \"cent\")
-- \"Discrete \\\"USD\\\" 100%1 123\"
-- @
instance forall currency scale.
  ( KnownSymbol currency, GoodScale scale
  ) => Show (Discrete' currency scale) where
  showsPrec n = \d0@(Discrete i0) ->
    let c = symbolVal (Proxy :: Proxy currency)
        s = scale d0
    in showParen (n > 10) $
         showString "Discrete " .  showsPrec 0 c . showChar ' ' .
         showsPrec 0 (numerator s) . showChar '%' .
         showsPrec 0 (denominator s) . showChar ' ' .
         showsPrec 0 i0

instance forall currency scale.
  ( KnownSymbol currency, GoodScale scale
  ) => Read (Discrete' currency scale) where
  readPrec = Read.parens $ do
    let c = symbolVal (Proxy :: Proxy currency)
        s = scale (Proxy :: Proxy scale)
    _ <- ReadPrec.lift (ReadP.string (concat
           [ "Discrete ", show c, " "
           , show (numerator s), "%"
           , show (denominator s), " "
           ]))
    fmap Discrete Read.readPrec

type family ErrFractionalDiscrete :: Constraint where
  ErrFractionalDiscrete
    = GHC.TypeError
        (('GHC.Text "The ") 'GHC.:<>:
         ('GHC.ShowType Discrete') 'GHC.:<>:
         ('GHC.Text " type is deliberately not a ") 'GHC.:<>:
         ('GHC.ShowType Fractional) 'GHC.:$$:
         ('GHC.Text "instance. Convert the ") 'GHC.:<>:
         ('GHC.ShowType Discrete') 'GHC.:<>:
         ('GHC.Text " value to a ") 'GHC.:<>:
         ('GHC.ShowType Dense) 'GHC.:$$:
         ('GHC.Text "value and use the ") 'GHC.:<>:
         ('GHC.ShowType Fractional) 'GHC.:<>:
         ('GHC.Text " features on it instead."))

instance
  ( ErrFractionalDiscrete
  , GoodScale scale
  ) => Fractional (Discrete' currency scale) where
  fromRational = undefined
  recip = undefined

-- | Construct a 'Discrete' value.
discrete :: GoodScale scale => Integer -> Discrete' currency scale
discrete = Discrete
{-# INLINE discrete #-}


-- | Convert currency 'Discrete' monetary value into a 'Dense' monetary
-- value.
denseFromDiscrete
  :: GoodScale scale
  => Discrete' currency scale
  -> Dense currency -- ^
denseFromDiscrete = \c@(Discrete i) -> Dense (fromInteger i / scale c)
{-# INLINE denseFromDiscrete #-}

-- | 'Discrete' currency identifier.
--
-- @
-- > 'discreteCurrency' ('discrete' 4 :: 'Discrete' \"USD\" \"cent\")
-- \"USD\"
-- @
discreteCurrency
  :: (KnownSymbol currency, GoodScale scale)
  => Discrete' currency scale
  -> T.Text -- ^
discreteCurrency = T.pack . discreteCurrency'
{-# INLINE discreteCurrency #-}

-- | Like 'discreteCurrency' but returns 'String'.
discreteCurrency'
  :: forall currency scale
  .  (KnownSymbol currency, GoodScale scale)
  => Discrete' currency scale
  -> String -- ^
discreteCurrency' = \_ -> symbolVal (Proxy @ currency)
{-# INLINE discreteCurrency' #-}

-- | Method for approximating a fractional number to an integer number.
data Approximation
  = Round
  -- ^ Approximate @x@ to the nearest integer, or to the nearest even integer if
  -- @x@ is equidistant between two integers.
  | Floor
  -- ^ Approximate @x@ to the nearest integer less than or equal to @x@.
  | Ceiling
  -- ^ Approximate @x@ to the nearest integer greater than or equal to @x@.
  | Truncate
  -- ^ Approximate @x@ to the nearest integer betwen @0@ and @x@, inclusive.
  deriving (Eq, Ord, Show, Read, GHC.Generic)


approximate :: Approximation -> Rational -> Integer
{-# INLINE approximate #-}
approximate = \case
  Round -> round
  Floor -> floor
  Ceiling -> ceiling
  Truncate -> truncate

-- | Approximate a 'Dense' value @x@ to the nearest value fully representable a
-- given @scale@.
--
-- If the given 'Dense' doesn't fit entirely in the @scale@, then a non-zero
-- 'Dense' reminder is returned alongside the 'Discrete' approximation.
--
-- Proof that 'discreteFromDense' doesn't lose money:
--
-- @
-- x == case 'discreteFromDense' a x of
--         (y, z) -> 'denseFromDiscrete' y + z
-- @
discreteFromDense
  :: forall currency scale
  .  GoodScale scale
  => Approximation
  -- ^ Approximation to use if necesary in order to fit the 'Dense' amount in
  -- the requested @scale@.
  -> Dense currency
  -> (Discrete' currency scale, Dense currency)
discreteFromDense a = \c0 ->
  let !r0 = toRational c0 :: Rational
      !r1 = scale (Proxy :: Proxy scale)
      !i2 = approximate a (r0 * r1) :: Integer
      !r2 = fromInteger i2 / r1 :: Rational
      !d2 = Discrete i2
      !rest = Dense (r0 - r2)
  in (d2, rest)
{-# INLINABLE discreteFromDense #-}

--------------------------------------------------------------------------------

-- | @'Scale' currency unit@ is an rational number (expressed as @'(numerator,
-- denominator)@) indicating how many pieces of @unit@ fit in @currency@.
--
-- @currency@ is usually a ISO-4217 currency code, but not necessarily.
--
-- The 'Scale' will determine how to convert a 'Dense' value into a
-- 'Discrete' value and vice-versa.
--
-- For example, there are 100 USD cents in 1 USD, so the scale for this
-- relationship is:
--
-- @
-- type instance 'Scale' \"USD\" \"cent\" = '(100, 1)
-- @
--
-- As another example, there is 1 dollar in USD, so the scale for this
-- relationship is:
--
-- @
-- type instance 'Scale' \"USD\" \"dollar\" = '(1, 1)
-- @
--
-- When using 'Discrete' values to represent money, it will be impossible to
-- represent an amount of @currency@ smaller than @unit@. So, if you decide to
-- use @Scale \"USD\" \"dollar\"@ as your scale, you will not be able to
-- represent values such as USD 3.50 or USD 21.87 becacuse they are not exact
-- multiples of a dollar.
--
-- If there exists a canonical smallest @unit@ that can fully represent the
-- currency in all its denominations, then an instance @'Scale' currency
-- currency@ exists.
--
-- @
-- type instance 'Scale' \"USD\" \"USD\" = 'Scale' \"USD\" \"cent\"
-- @
--
-- For some monetary values, such as precious metals, there is no smallest
-- representable unit, since you can repeatedly split the precious metal many
-- times before it stops being a precious metal. Nevertheless, for practical
-- purposes we can make a sane arbitrary choice of smallest unit. For example,
-- the base unit for XAU (Gold) is the /troy ounce/, which is too big to be
-- considered the smallest unit, but we can arbitrarily choose the /milligrain/
-- as our smallest unit, which is about as heavy as a single grain of table salt
-- and should be sufficiently precise for all monetary practical purposes. A
-- /troy ounce/ equals 480000 /milligrains/.
--
-- @
-- type instance 'Scale' \"XAU\" \"milligrain\" = '(480000, 1)
-- @
--
-- You can use other units such as /milligrams/ for measuring XAU, for example.
-- However, since the amount of /milligrams/ in a /troy ounce/ (31103.477) is
-- not integral, we need to use rational with a denominator different than 1 to
-- express it.
--
-- @
-- type instance 'Scale' \"XAU\" \"milligram\" = '(31103477, 1000)
-- @
--
-- If you try to obtain the 'Scale' of a @currency@ without an obvious smallest
-- representable @unit@, like XAU, you will get a compile error.
type family Scale (currency :: Symbol) (unit :: Symbol) :: (Nat, Nat)

-- | A friendly 'GHC.TypeError' to use for a @currency@ that doesn't have a
-- canonical small unit.
type family ErrScaleNonCanonical (currency :: Symbol) :: k where
  ErrScaleNonCanonical c = GHC.TypeError
    ( 'GHC.Text c 'GHC.:<>:
      'GHC.Text " is not a currency with a canonical smallest unit," 'GHC.:$$:
      'GHC.Text "be explicit about the currency unit you want to use." )

-- | Constraints to a scale (like the one returned by @'Scale' currency unit@)
-- expected to always be satisfied. In particular, the scale is always
-- guaranteed to be a positive rational number ('GHC.Real.infinity' and
-- 'GHC.Real.notANumber' are forbidden by 'GoodScale').
type GoodScale (scale :: (Nat, Nat))
   = ( CmpNat 0 (Fst scale) ~ 'LT
     , CmpNat 0 (Snd scale) ~ 'LT
     , KnownNat (Fst scale)
     , KnownNat (Snd scale)
     )

-- | If the specified @num@ and @den@ satisfy the expectations of 'GoodScale' at
-- the type level, then construct a proof for 'GoodScale'.
mkGoodScale
  :: forall num den
  .  (KnownNat num, KnownNat den)
  => Maybe (Dict (GoodScale '(num, den)))
mkGoodScale =
  let n = natVal (Proxy :: Proxy num)
      d = natVal (Proxy :: Proxy den)
  in if (n > 0) && (d > 0)
     then Just (unsafeCoerce (Dict :: Dict ('LT ~ 'LT, 'LT ~ 'LT,
                                            KnownNat num, KnownNat den)))
     else Nothing
{-# INLINABLE mkGoodScale #-}

-- | Term-level representation of a currrency @scale@.
--
-- For example, the 'Scale' for @\"USD\"@ in @\"cent\"@s is @100/1@.
--
-- @
-- > 'scale' ('Proxy' :: 'Proxy' ('Scale' \"USD\" \"cent\"))
-- 100 '%' 1
-- @
--
-- @
-- > 'scale' (x :: 'Discrete' \"USD\" \"cent\")
-- 100 '%' 1
-- @
--
-- The returned 'Rational' is statically guaranteed to be a positive number.
scale :: forall proxy scale. GoodScale scale => proxy scale -> Rational -- ^
scale = \_ -> natVal (Proxy :: Proxy (Fst scale)) %
              natVal (Proxy :: Proxy (Snd scale))
{-# INLINE scale #-}

--------------------------------------------------------------------------------

-- | Exchange rate for converting monetary values of currency @src@ into
-- monetary values of currency @dst@ by multiplying for it.
--
-- For example, if in order to convert USD to GBP we have to multiply by 1.2345,
-- then we can represent this situaion using:
--
-- @
-- 'exchangeRate' (12345 '%' 10000) :: 'Maybe' ('ExchangeRate' \"USD\" \"GBP\")
-- @
newtype ExchangeRate (src :: Symbol) (dst :: Symbol) = ExchangeRate Rational
  deriving (Eq, Ord, GHC.Generic)


-- | Composition of 'ExchangeRate's multiplies exchange rates together:
--
-- @
-- 'exchangeRateToRational' x * 'exchangeRateToRational' y  ==  'exchangeRateToRational' (x . y)
-- @
--
-- Identity:
--
-- @
-- x  ==  x . id  ==  id . x
-- @
--
-- Associativity:
--
-- @
-- x . y . z  ==  x . (y . z)  ==  (x . y) . z
-- @
--
-- Conmutativity (provided the types allow for composition):
--
-- @
-- x . y  ==  y . x
-- @
--
-- Reciprocal:
--
-- @
-- 1  ==  'exchangeRateToRational' (x . 'exchangeRateRecip' x)
-- @
instance Category ExchangeRate where
  id = ExchangeRate 1
  {-# INLINE id #-}
  ExchangeRate a . ExchangeRate b = ExchangeRate (a * b)
  {-# INLINE (.) #-}

-- |
-- @
-- > 'show' ('exchangeRate' (5 '%' 7) :: 'Maybe' ('ExchangeRate' \"USD\" \"JPY\"))@
-- Just \"ExchangeRate \\\"USD\\\" \\\"JPY\\\" 5%7\"
-- @
instance forall src dst.
  ( KnownSymbol src, KnownSymbol dst
  ) => Show (ExchangeRate src dst) where
  showsPrec n = \(ExchangeRate r0) ->
    let s = symbolVal (Proxy :: Proxy src)
        d = symbolVal (Proxy :: Proxy dst)
    in showParen (n > 10) $
         showString "ExchangeRate " . showsPrec 0 s . showChar ' ' .
         showsPrec 0 d . showChar ' ' .
         showsPrec 0 (numerator r0) . showChar '%' .
         showsPrec 0 (denominator r0)

instance forall src dst.
  ( KnownSymbol src, KnownSymbol dst
  ) => Read (ExchangeRate (src :: Symbol) (dst :: Symbol)) where
  readPrec = Read.parens $ do
    let s = symbolVal (Proxy :: Proxy src)
        d = symbolVal (Proxy :: Proxy dst)
    _ <- ReadPrec.lift (ReadP.string
            ("ExchangeRate " ++ show s ++ " " ++ show d ++ " "))
    maybe empty pure =<< fmap exchangeRate Read.readPrec


-- | Obtain a 'Rational' representation of the 'ExchangeRate'.
--
-- This 'Rational' is guaranteed to be a positive number.
exchangeRateToRational :: ExchangeRate src dst -> Rational
exchangeRateToRational = \(ExchangeRate r0) -> r0
{-# INLINE exchangeRateToRational #-}

-- | Safely construct an 'ExchangeRate' from a *positive* 'Rational' number.
exchangeRate :: Rational -> Maybe (ExchangeRate src dst)
exchangeRate = \r ->
  if denominator r /= 0 && r > 0
  then Just (ExchangeRate r)
  else Nothing
{-# INLINE exchangeRate #-}

-- | Reciprocal 'ExchangeRate'.
--
-- This function retuns the reciprocal or multiplicative inverse of the given
-- 'ExchangeRate', leading to the following identity law:
--
-- @
-- 'exchangeRateRecip' . 'exchangeRateRecip'   ==  'id'
-- @
--
-- Note: If 'ExchangeRate' had a 'Fractional' instance, then 'exchangeRateRecip'
-- would be the implementation of 'recip'.
exchangeRateRecip :: ExchangeRate a b -> ExchangeRate b a
exchangeRateRecip = \(ExchangeRate x) ->
   ExchangeRate (1 / x)   -- 'exchangeRate' guarantees that @x@ isn't zero.
{-# INLINE exchangeRateRecip #-}

-- | Apply the 'ExchangeRate' to the given @'Dense' src@ monetary value.
--
-- Identity law:
--
-- @
-- 'exchange' ('exchangeRateRecip' x) . 'exchange' x  ==  'id'
-- @
--
-- Use the /Identity law/ for reasoning about going back and forth between @src@
-- and @dst@ in order to manage any leftovers that might not be representable as
-- a 'Discrete' monetary value of @src@.
exchange :: ExchangeRate src dst -> Dense src -> Dense dst
exchange (ExchangeRate r) = \(Dense s) -> Dense (r * s)
{-# INLINE exchange #-}

--------------------------------------------------------------------------------
-- SomeDense

-- | A monomorphic representation of 'Dense' that is easier to serialize and
-- deserialize than 'Dense' in case you don't know the type indexes involved.
--
-- If you are trying to construct a value of this type from some raw input, then
-- you will need to use the 'mkSomeDense' function.
--
-- In order to be able to effectively serialize a 'SomeDense' value, you
-- need to serialize the following three values (which are the eventual
-- arguments to 'mkSomeDense'):
--
-- * 'someDenseCurrency'
-- * 'someDenseAmount'
data SomeDense = SomeDense
  { _someDenseCurrency          :: !String
    -- ^ This is a 'String' rather than 'T.Text' because it makes it easier for
    -- us to derive serialization instances maintaining backwards compatiblity
    -- with pre-0.6 versions of this library, when 'String' was the prefered
    -- string type, and not 'T.Text'.
  , _someDenseAmount            :: !Rational
  } deriving (Eq, Show, GHC.Generic)

-- | __WARNING__ This instance does not compare monetary amounts, it just helps
-- you sort 'SomeDense' values in case you need to put them in a 'Data.Set.Set'
-- or similar.
deriving instance Ord SomeDense

-- | Currency name.
someDenseCurrency :: SomeDense -> T.Text
someDenseCurrency = T.pack . someDenseCurrency'
{-# INLINE someDenseCurrency #-}

-- | Like 'someDenseCurrency' but returns 'String'.
someDenseCurrency' :: SomeDense -> String
someDenseCurrency' = _someDenseCurrency
{-# INLINE someDenseCurrency' #-}

-- | Currency unit amount.
someDenseAmount :: SomeDense -> Rational
someDenseAmount = _someDenseAmount
{-# INLINE someDenseAmount #-}

-- | Build a 'SomeDense' from raw values.
--
-- This function is intended for deserialization purposes. You need to convert
-- this 'SomeDense' value to a 'Dense' value in order to do any arithmetic
-- operation on the monetary value.
mkSomeDense
  :: T.Text   -- ^ Currency. ('someDenseCurrency')
  -> Rational -- ^ Scale. ('someDenseAmount')
  -> Maybe SomeDense
{-# INLINE mkSomeDense #-}
mkSomeDense = \c r -> mkSomeDense' (T.unpack c) r

-- | Like 'mkSomeDense' but takes 'String' rather than 'T.Text'.
mkSomeDense' :: String -> Rational -> Maybe SomeDense
{-# INLINABLE mkSomeDense' #-}
mkSomeDense' = \c r ->
  if (denominator r /= 0)
  then Just (SomeDense c r)
  else Nothing

-- | Convert a 'Dense' to a 'SomeDense' for ease of serialization.
toSomeDense :: KnownSymbol currency => Dense currency -> SomeDense
toSomeDense = \(Dense r0 :: Dense currency) ->
  SomeDense (symbolVal (Proxy @ currency)) r0
{-# INLINE toSomeDense #-}

-- | Attempt to convert a 'SomeDense' to a 'Dense', provided you know the target
-- @currency@.
fromSomeDense
  :: forall currency
  .  KnownSymbol currency
  => SomeDense
  -> Maybe (Dense currency)  -- ^
fromSomeDense = \dr ->
  if (_someDenseCurrency dr == symbolVal (Proxy :: Proxy currency))
  then Just (Dense (someDenseAmount dr))
  else Nothing
{-# INLINABLE fromSomeDense #-}

-- | Convert a 'SomeDense' to a 'Dense' without knowing the target @currency@.
--
-- Notice that @currency@ here can't leave its intended scope unless you can
-- prove equality with some other type at the outer scope, but in that case you
-- would be better off using 'fromSomeDense' directly.
withSomeDense
  :: SomeDense
  -> (forall currency. KnownSymbol currency => Dense currency -> r)
  -> r  -- ^
withSomeDense dr = \f ->
   case someSymbolVal (_someDenseCurrency dr) of
      SomeSymbol (Proxy :: Proxy currency) ->
         f (Dense (someDenseAmount dr) :: Dense currency)
{-# INLINABLE withSomeDense #-}

--------------------------------------------------------------------------------
-- SomeDiscrete

-- | A monomorphic representation of 'Discrete' that is easier to serialize and
-- deserialize than 'Discrete' in case you don't know the type indexes involved.
--
-- If you are trying to construct a value of this type from some raw input, then
-- you will need to use the 'mkSomeDiscrete' function.
--
-- In order to be able to effectively serialize a 'SomeDiscrete' value, you need
-- to serialize the following four values (which are the eventual arguments to
-- 'mkSomeDiscrete'):
--
-- * 'someDiscreteCurrency'
-- * 'someDiscreteScale'
-- * 'someDiscreteAmount'
data SomeDiscrete = SomeDiscrete
  { _someDiscreteCurrency :: !String
    -- ^ Currency name.
    --
    -- This is a 'String' rather than 'T.Text' because it makes it easier for
    -- us to derive serialization instances maintaining backwards compatiblity
    -- with pre-0.6 versions of this library, when 'String' was the prefered
    -- string type, and not 'T.Text'.
  , _someDiscreteScale    :: !Rational -- ^ Positive, non-zero.
  , _someDiscreteAmount   :: !Integer  -- ^ Amount of unit.
  } deriving (Eq, Show, GHC.Generic)

-- | __WARNING__ This instance does not compare monetary amounts, it just helps
-- you sort 'SomeDiscrete' values in case you need to put them in a
-- 'Data.Set.Set' or similar.
deriving instance Ord SomeDiscrete

-- | Currency name.
someDiscreteCurrency :: SomeDiscrete -> T.Text
someDiscreteCurrency = T.pack . someDiscreteCurrency'
{-# INLINE someDiscreteCurrency #-}

-- | Like 'someDiscreteCurrency' but returns 'String'.
someDiscreteCurrency' :: SomeDiscrete -> String
someDiscreteCurrency' = _someDiscreteCurrency
{-# INLINE someDiscreteCurrency' #-}

-- | Positive, non-zero.
someDiscreteScale :: SomeDiscrete -> Rational
someDiscreteScale = _someDiscreteScale
{-# INLINE someDiscreteScale #-}

-- | Amount of currency unit.
someDiscreteAmount :: SomeDiscrete -> Integer
someDiscreteAmount = _someDiscreteAmount
{-# INLINE someDiscreteAmount #-}

-- | Internal. Build a 'SomeDiscrete' from raw values.
--
-- This function is intended for deserialization purposes. You need to convert
-- this 'SomeDiscrete' value to a 'Discrete' vallue in order to do any arithmetic
-- operation on the monetary value.
mkSomeDiscrete
  :: T.Text   -- ^ Currency name. ('someDiscreteCurrency')
  -> Rational -- ^ Scale. Positive, non-zero. ('someDiscreteScale')
  -> Integer  -- ^ Amount of unit. ('someDiscreteAmount')
  -> Maybe SomeDiscrete
{-# INLINE mkSomeDiscrete #-}
mkSomeDiscrete = \c r a -> mkSomeDiscrete' (T.unpack c) r a

-- | Like 'mkSomeDiscrete' but takes 'String' rather than 'T.Text'.
mkSomeDiscrete' :: String -> Rational -> Integer -> Maybe SomeDiscrete
{-# INLINABLE mkSomeDiscrete' #-}
mkSomeDiscrete' = \c r a ->
  if (denominator r /= 0) && (r > 0)
  then Just (SomeDiscrete c r a)
  else Nothing

-- | Convert a 'Discrete' to a 'SomeDiscrete' for ease of serialization.
toSomeDiscrete
  :: (KnownSymbol currency, GoodScale scale)
  => Discrete' currency scale
  -> SomeDiscrete -- ^
toSomeDiscrete = \(Discrete i0 :: Discrete' currency scale) ->
  let c = symbolVal (Proxy :: Proxy currency)
      n = natVal (Proxy :: Proxy (Fst scale))
      d = natVal (Proxy :: Proxy (Snd scale))
  in SomeDiscrete c (n % d) i0
{-# INLINABLE toSomeDiscrete #-}

-- | Attempt to convert a 'SomeDiscrete' to a 'Discrete', provided you know the
-- target @currency@ and @unit@.
fromSomeDiscrete
  :: forall currency scale
  .  (KnownSymbol currency, GoodScale scale)
  => SomeDiscrete
  -> Maybe (Discrete' currency scale)  -- ^
fromSomeDiscrete = \dr ->
   if (_someDiscreteCurrency dr == symbolVal (Proxy @ currency)) &&
      (someDiscreteScale dr == scale (Proxy @ scale))
   then Just (Discrete (someDiscreteAmount dr))
   else Nothing
{-# INLINABLE fromSomeDiscrete #-}

-- | Convert a 'SomeDiscrete' to a 'Discrete' without knowing the target
-- @currency@ and @unit@.
--
-- Notice that @currency@ and @unit@ here can't leave its intended scope unless
-- you can prove equality with some other type at the outer scope, but in that
-- case you would be better off using 'fromSomeDiscrete' directly.
--
-- Notice that you may need to add an explicit type to the result of this
-- function in order to keep the compiler happy.
withSomeDiscrete
  :: forall r
  .  SomeDiscrete
  -> ( forall currency scale.
         ( KnownSymbol currency
         , GoodScale scale
         ) => Discrete' currency scale
           -> r )
  -> r  -- ^
withSomeDiscrete dr = \f ->
  case someSymbolVal (_someDiscreteCurrency dr) of
    SomeSymbol (Proxy :: Proxy currency) ->
      case someNatVal (numerator (someDiscreteScale dr)) of
        Nothing -> error "withSomeDiscrete: impossible: numerator < 0"
        Just (SomeNat (Proxy :: Proxy num)) ->
          case someNatVal (denominator (someDiscreteScale dr)) of
            Nothing -> error "withSomeDiscrete: impossible: denominator < 0"
            Just (SomeNat (Proxy :: Proxy den)) ->
              case mkGoodScale of
                Nothing -> error "withSomeDiscrete: impossible: mkGoodScale"
                Just (Dict :: Dict (GoodScale '(num, den))) ->
                  f (Discrete (someDiscreteAmount dr)
                       :: Discrete' currency '(num, den))
{-# INLINABLE withSomeDiscrete #-}

--------------------------------------------------------------------------------
-- SomeExchangeRate

-- | A monomorphic representation of 'ExchangeRate' that is easier to serialize
-- and deserialize than 'ExchangeRate' in case you don't know the type indexes
-- involved.
--
-- If you are trying to construct a value of this type from some raw input, then
-- you will need to use the 'mkSomeExchangeRate' function.
--
-- In order to be able to effectively serialize an 'SomeExchangeRate' value, you
-- need to serialize the following four values (which are the eventual arguments
-- to 'mkSomeExchangeRate'):
--
-- * 'someExchangeRateSrcCurrency'
-- * 'someExchangeRateDstCurrency'
-- * 'someExchangeRateRate'
data SomeExchangeRate = SomeExchangeRate
  { _someExchangeRateSrcCurrency     :: !String
    -- ^ This is a 'String' rather than 'T.Text' because it makes it easier for
    -- us to derive serialization instances maintaining backwards compatiblity
    -- with pre-0.6 versions of this library, when 'String' was the prefered
    -- string type, and not 'T.Text'.
  , _someExchangeRateDstCurrency     :: !String
    -- ^ This is a 'String' rather than 'T.Text' because it makes it easier for
    -- us to derive serialization instances maintaining backwards compatiblity
    -- with pre-0.6 versions of this library, when 'String' was the prefered
    -- string type, and not 'T.Text'.
  , _someExchangeRateRate            :: !Rational -- ^ Positive, non-zero.
  } deriving (Eq, Show, GHC.Generic)

-- | __WARNING__ This instance does not compare monetary amounts, it just helps
-- you sort 'SomeExchangeRate' values in case you need to put them in a
-- 'Data.Set.Set' or similar.
deriving instance Ord SomeExchangeRate

-- | Source currency name.
someExchangeRateSrcCurrency :: SomeExchangeRate -> T.Text
someExchangeRateSrcCurrency = T.pack . someExchangeRateSrcCurrency'
{-# INLINE someExchangeRateSrcCurrency #-}

-- | Like 'someExchangeRateSrcCurrency' but returns 'String'.
someExchangeRateSrcCurrency' :: SomeExchangeRate -> String
someExchangeRateSrcCurrency' = _someExchangeRateSrcCurrency
{-# INLINE someExchangeRateSrcCurrency' #-}

-- | Destination currency name.
someExchangeRateDstCurrency :: SomeExchangeRate -> T.Text
someExchangeRateDstCurrency = T.pack . _someExchangeRateDstCurrency
{-# INLINE someExchangeRateDstCurrency #-}

-- | Like 'someExchangeRateDstCurrency' but returns 'String'.
someExchangeRateDstCurrency' :: SomeExchangeRate -> String
someExchangeRateDstCurrency' = _someExchangeRateDstCurrency
{-# INLINE someExchangeRateDstCurrency' #-}

-- | Exchange rate. Positive, non-zero.
someExchangeRateRate :: SomeExchangeRate -> Rational
someExchangeRateRate = _someExchangeRateRate
{-# INLINE someExchangeRateRate #-}

-- | Internal. Build a 'SomeExchangeRate' from raw values.
--
-- This function is intended for deserialization purposes. You need to convert
-- this 'SomeExchangeRate' value to a 'ExchangeRate' value in order to do any
-- arithmetic operation with the exchange rate.
mkSomeExchangeRate
  :: T.Text   -- ^ Source currency name. ('someExchangeRateSrcCurrency')
  -> T.Text   -- ^ Destination currency name. ('someExchangeRateDstCurrency')
  -> Rational -- ^ Exchange rate . Positive, non-zero. ('someExchangeRateRate')
  -> Maybe SomeExchangeRate
{-# INLINE mkSomeExchangeRate #-}
mkSomeExchangeRate = \src dst r ->
  mkSomeExchangeRate' (T.unpack src) (T.unpack dst) r

-- | Like 'mkSomeExchangeRate' but takes 'String' rather than 'T.Text'.
mkSomeExchangeRate' :: String -> String -> Rational -> Maybe SomeExchangeRate
{-# INLINABLE mkSomeExchangeRate' #-}
mkSomeExchangeRate' = \src dst r ->
  if (denominator r /= 0) && (r > 0)
  then Just (SomeExchangeRate src dst r)
  else Nothing

-- | Convert a 'ExchangeRate' to a 'SomeDiscrete' for ease of serialization.
toSomeExchangeRate
  :: (KnownSymbol src, KnownSymbol dst)
  => ExchangeRate src dst
  -> SomeExchangeRate -- ^
toSomeExchangeRate = \(ExchangeRate r0 :: ExchangeRate src dst) ->
  let src = symbolVal (Proxy :: Proxy src)
      dst = symbolVal (Proxy :: Proxy dst)
  in SomeExchangeRate src dst r0
{-# INLINABLE toSomeExchangeRate #-}

-- | Attempt to convert a 'SomeExchangeRate' to a 'ExchangeRate', provided you
-- know the target @src@ and @dst@ types.
fromSomeExchangeRate
  :: forall src dst
  .  (KnownSymbol src, KnownSymbol dst)
  => SomeExchangeRate
  -> Maybe (ExchangeRate src dst)  -- ^
fromSomeExchangeRate = \x ->
   if (_someExchangeRateSrcCurrency x == symbolVal (Proxy @ src)) &&
      (_someExchangeRateDstCurrency x == symbolVal (Proxy @ dst))
   then Just (ExchangeRate (someExchangeRateRate x))
   else Nothing
{-# INLINABLE fromSomeExchangeRate #-}

-- | Convert a 'SomeExchangeRate' to a 'ExchangeRate' without knowing the target
-- @currency@ and @unit@.
--
-- Notice that @src@ and @dst@ here can't leave its intended scope unless
-- you can prove equality with some other type at the outer scope, but in that
-- case you would be better off using 'fromSomeExchangeRate' directly.
withSomeExchangeRate
  :: SomeExchangeRate
  -> ( forall src dst.
         ( KnownSymbol src
         , KnownSymbol dst
         ) => ExchangeRate src dst
           -> r )
  -> r  -- ^
withSomeExchangeRate x = \f ->
  case someSymbolVal (_someExchangeRateSrcCurrency x) of
    SomeSymbol (Proxy :: Proxy src) ->
      case someSymbolVal (_someExchangeRateDstCurrency x) of
        SomeSymbol (Proxy :: Proxy dst) ->
          f (ExchangeRate (someExchangeRateRate x) :: ExchangeRate src dst)
{-# INLINABLE withSomeExchangeRate #-}

--------------------------------------------------------------------------------
-- Miscellaneous

type family Fst (ab :: (ka, kb)) :: ka where Fst '(a,b) = a
type family Snd (ab :: (ka, kb)) :: ka where Snd '(a,b) = b

--------------------------------------------------------------------------------
-- vector-space instances

instance AG.AdditiveGroup (Dense currency) where
  zeroV = Dense AG.zeroV
  {-# INLINE zeroV #-}
  Dense a ^+^ Dense b = Dense $! (a AG.^+^ b)
  {-# INLINE (^+^) #-}
  negateV (Dense a) = Dense $! (AG.negateV a)
  {-# INLINE negateV #-}
  Dense a ^-^ Dense b = Dense $! (a AG.^-^ b)
  {-# INLINE (^-^) #-}

-- | __WARNING__ a scalar with a zero denominator will cause 'VS.*^' to crash.
instance VS.VectorSpace (Dense currency) where
  type Scalar (Dense currency) = Rational
  s *^ Dense a =
    if denominator s /= 0
    then Dense $! s VS.*^ a
    else error "(*^)': malformed Rational given (denominator is zero)."
  {-# INLINE (*^) #-}

instance GoodScale scale => AG.AdditiveGroup (Discrete' currency scale) where
  zeroV = Discrete AG.zeroV
  {-# INLINE zeroV #-}
  Discrete a ^+^ Discrete b = Discrete $! (a AG.^+^ b)
  {-# INLINE (^+^) #-}
  negateV (Discrete a) = Discrete $! (AG.negateV a)
  {-# INLINE negateV #-}
  Discrete a ^-^ Discrete b = Discrete $! (a AG.^-^ b)
  {-# INLINE (^-^) #-}

instance GoodScale scale => VS.VectorSpace (Discrete' currency scale) where
  type Scalar (Discrete' currency scale) = Integer
  s *^ Discrete a = Discrete $! (s VS.*^ a)
  {-# INLINE (*^) #-}

--------------------------------------------------------------------------------
-- Extra instances: hashable
instance Hashable Approximation
instance Hashable (Dense currency)
instance Hashable SomeDense
instance GoodScale scale => Hashable (Discrete' currency scale)
instance Hashable SomeDiscrete
instance Hashable (ExchangeRate src dst)
instance Hashable SomeExchangeRate

--------------------------------------------------------------------------------
-- Extra instances: deepseq
instance NFData Approximation
instance NFData (Dense currency)
instance NFData SomeDense
instance GoodScale scale => NFData (Discrete' currency scale)
instance NFData SomeDiscrete
instance NFData (ExchangeRate src dst)
instance NFData SomeExchangeRate

--------------------------------------------------------------------------------
-- Extra instances: binary

-- | Compatible with 'SomeDense'.
instance (KnownSymbol currency) => Binary.Binary (Dense currency) where
  put = Binary.put . toSomeDense
  get = maybe empty pure =<< fmap fromSomeDense Binary.get

-- | Compatible with 'SomeDiscrete'.
instance
  ( KnownSymbol currency, GoodScale scale
  ) => Binary.Binary (Discrete' currency scale) where
  put = Binary.put . toSomeDiscrete
  get = maybe empty pure =<< fmap fromSomeDiscrete Binary.get

-- | Compatible with 'SomeExchangeRate'.
instance
  ( KnownSymbol src, KnownSymbol dst
  ) => Binary.Binary (ExchangeRate src dst) where
  put = Binary.put . toSomeExchangeRate
  get = maybe empty pure =<< fmap fromSomeExchangeRate Binary.get

-- | Compatible with 'Dense'.
instance Binary.Binary SomeDense where
  put = \(SomeDense c r) -> do
    Binary.put c
    Binary.put (numerator r)
    Binary.put (denominator r)
  get = maybe empty pure =<< do
    c :: String <- Binary.get
    n :: Integer <- Binary.get
    d :: Integer <- Binary.get
    when (d == 0) (fail "denominator is zero")
    pure (mkSomeDense' c (n % d))

-- | Compatible with 'Discrete'.
instance Binary.Binary SomeDiscrete where
  put = \(SomeDiscrete c r a) ->
    -- We go through String for backwards compatibility.
    Binary.put c <>
    Binary.put (numerator r) <>
    Binary.put (denominator r) <>
    Binary.put a
  get = maybe empty pure =<< do
    c :: String <- Binary.get
    n :: Integer <- Binary.get
    d :: Integer <- Binary.get
    when (d == 0) (fail "denominator is zero")
    a :: Integer <- Binary.get
    pure (mkSomeDiscrete' c (n % d) a)

-- | Compatible with 'ExchangeRate'.
instance Binary.Binary SomeExchangeRate where
  put = \(SomeExchangeRate src dst r) -> do
    Binary.put src
    Binary.put dst
    Binary.put (numerator r)
    Binary.put (denominator r)
  get = maybe empty pure =<< do
    src :: String <- Binary.get
    dst :: String <- Binary.get
    n :: Integer <- Binary.get
    d :: Integer <- Binary.get
    when (d == 0) (fail "denominator is zero")
    pure (mkSomeExchangeRate' src dst (n % d))

--------------------------------------------------------------------------------
-- Decimal rendering

-- | Render a 'Dense' monetary amount as a decimal number in a potentially lossy
-- manner.
--
-- @
-- > 'denseToDecimal' 'Round' 'True' ('Just' \',\') \'.\' 2 (1 '%' 1)
--      ('dense'' (123456 '%' 100) :: 'Dense' \"USD\")
-- Just \"+1,234.56\"
-- @
--
-- @
-- > 'denseToDecimal' 'Round' 'True' ('Just' \',\') \'.\' 2 (100 '%' 1)
--      ('dense'' (123456 '%' 100) :: 'Dense' \"USD\")
-- Just \"+123,456.00\"
-- @
--
-- This function returns 'Nothing' if the scale is less than @1@, or if it's not
-- possible to reliably render the decimal string due to a bad choice of
-- separators. That is, if the separators are digits or equal among themselves,
-- this function returns 'Nothing'.
denseToDecimal
  :: Approximation
  -- ^ Approximation to use if necesary in order to fit the 'Dense' amount in
  -- as many decimal numbers as requested.
  -> Bool
  -- ^ Whether to render a leading @\'+\'@ sign in case the amount is positive.
  -> Maybe Char
  -- ^ Thousands separator for the integer part, if any (i.e., the @\',\'@ in
  -- @1,234.56789@).
  --
  -- If the given separator is a digit, or if it is equal to the decimal
  -- separator, then this functions returns 'Nothing'.
  -> Char
  -- ^ Decimal separator (i.e., the @\'.\'@ in @1,234.56789@).
  --
  -- If the given separator is a digit, or if it is equal to the thousands
  -- separator, then this functions returns 'Nothing'.
  -> Word8
  -- ^ Number of decimal numbers to render, if any.
  -> Rational
  -- ^ Scale used to when rendering the decimal number. This is useful if you
  -- want to render a “number of cents” rather than a “number of dollars” when
  -- rendering a USD amount, for example.
  --
  -- Set this to @1 '%' 1@ if you don't care.
  --
  -- For example, when rendering render @'dense'' (123 '%' 100) :: 'Dense'
  -- "USD"@ as a decimal number with three decimal places, a scale of @1 '%' 1@
  -- (analogous to  @'Scale' \"USD\" \"dollar\"@) would render @1@ as the
  -- integer part and @230@ as the fractional part, whereas a scale of @100 '%'
  -- 1@ (analogous @'Scale' \"USD\" \"cent\"@) would render @123@ as the integer
  -- part and @000@ as the fractional part.
  --
  -- You can easily obtain the scale for a particular currency and unit
  -- combination using the 'scale' function. Otherwise, you are free to pass in
  -- any other /positive/ 'Rational' number. If a non-positive scale is given,
  -- then this function returns 'Nothing'.
  --
  -- Specifying scales other than @1 '%' 1@ is particularly useful for
  -- currencies whose main unit is too big. For example, the main unit of gold
  -- (XAU) is the troy-ounce, which is too big for day to day accounting, so
  -- using the gram or the grain as the unit when rendering decimal amounts
  -- could be useful.
  --
  -- Be careful when using a scale smaller than @1 '%' 1@, since it may become
  -- impossible to parse back a meaningful amount from the rendered decimal
  -- representation unless a big number of fractional digits is used.
  -> Dense currency
  -- ^ The dense monetary amount to render.
  -> Maybe T.Text
  -- ^ Returns 'Nothing' is the given separators are not acceptable (i.e., they
  -- are digits, or they are equal).
{-# INLINABLE denseToDecimal #-}
denseToDecimal a plus ytsep dsep fdigs scal = \(Dense r0) -> do
  guard (scal > 0)
  rationalToDecimal a plus ytsep dsep fdigs (r0 * scal)

-- | Render a 'Discrete'' monetary amount as a decimal number in a potentially
-- lossy manner.
--
-- This is simply a convenient wrapper around 'denseToDecimal':
--
-- @
-- 'discreteToDecimal' a b c d e f (dis :: 'Discrete'' currency scale)
--     == 'denseToDecimal' a b c d e f ('denseFromDiscrete' dis :: 'Dense' currency)
-- @
--
-- In particular, the @scale@ in @'Discrete'' currency scale@ has no influence
-- over the scale in which the decimal number is rendered. Use the 'Rational'
-- parameter to this function for modifying that behavior.
--
-- Please refer to 'denseToDecimal' for further documentation.
--
-- This function returns 'Nothing' if the scale is less than @1@, or if it's not
-- possible to reliably render the decimal string due to a bad choice of
-- separators. That is, if the separators are digits or equal among themselves,
-- this function returns 'Nothing'.
discreteToDecimal
  :: GoodScale scale
  => Approximation
  -- ^ Approximation to use if necesary in order to fit the 'Discrete' amount in
  -- as many decimal numbers as requested.
  -> Bool
  -- ^ Whether to render a leading @\'+\'@ sign in case the amount is positive.
  -> Maybe Char
  -- ^ Thousands separator for the integer part, if any (i.e., the @\',\'@ in
  -- @1,234.56789@).
  --
  -- If the given separator is a digit, or if it is equal to the decimal
  -- separator, then this functions returns 'Nothing'.
  -> Char
  -- ^ Decimal separator (i.e., the @\'.\'@ in @1,234.56789@).
  --
  -- If the given separator is a digit, or if it is equal to the thousands
  -- separator, then this functions returns 'Nothing'.
  -> Word8
  -- ^ Number of decimal numbers to render, if any.
  -> Rational
  -- ^ Scale used to when rendering the decimal number. This is useful if you
  -- want to render a “number of cents” rather than a “number of dollars” when
  -- rendering a USD amount, for example.
  --
  -- Set this to @1 '%' 1@ if you don't care.
  --
  -- For example, when rendering render @'discrete' 123 :: 'Dense' \"USD\"
  -- \"cent\"@ as a decimal number with three decimal places, a scale of @1 '%'
  -- 1@ (analogous to  @'Scale' \"USD\" \"dollar\"@) would render @1@ as the
  -- integer part and @230@ as the fractional part, whereas a scale of @100 '%'
  -- 1@ (analogous @'Scale' \"USD\" \"cent\"@) would render @123@ as the integer
  -- part and @000@ as the fractional part.
  --
  -- You can easily obtain the scale for a particular currency and unit
  -- combination using the 'scale' function. Otherwise, you are free to pass in
  -- any other /positive/ 'Rational' number. If a non-positive scale is
  -- given, then this function returns 'Nothing'.
  --
  -- Specifying scales other than @1 '%' 1@ is particularly useful for
  -- currencies whose main unit is too big. For example, the main unit of gold
  -- (XAU) is the troy-ounce, which is too big for day to day accounting, so
  -- using the gram or the grain as the unit when rendering decimal amounts
  -- could be useful.
  --
  -- Be careful when using a scale smaller than @1 '%' 1@, since it may become
  -- impossible to parse back a meaningful amount from the rendered decimal
  -- representation unless a big number of fractional digits is used.
  -> Discrete' currency scale
  -- ^ The monetary amount to render.
  -> Maybe T.Text
  -- ^ Returns 'Nothing' is the given separators are not acceptable (i.e., they
  -- are digits, or they are equal).
{-# INLINABLE discreteToDecimal #-}
discreteToDecimal a plus ytsep dsep fdigs scal = \dns ->
  denseToDecimal a plus ytsep dsep fdigs scal (denseFromDiscrete dns)

-- | Render a 'ExchangeRate' as a decimal number in a potentially lossy manner.
--
-- @
-- > 'exchangeRateToDecimal' 'Round' 'True' ('Just' \',\') \'.\' 2
--       '=<<' ('exchangeRate' (123456 '%' 100) :: 'Maybe' ('ExchangeRate' \"USD\" \"EUR\"))
-- Just \"1,234.56\"
-- @
--
-- This function returns 'Nothing' if it is not possible to reliably render the
-- decimal string due to a bad choice of separators. That is, if the separators
-- are digits or equal among themselves, this function returns 'Nothing'.
exchangeRateToDecimal
  :: Approximation
  -- ^ Approximation to use if necesary in order to fit the 'Dense' amount in
  -- as many decimal numbers as requested.
  -> Maybe Char
  -- ^ Thousands separator for the integer part, if any (i.e., the @\',\'@ in
  -- @1,234.56789@).
  -> Char
  -- ^ Decimal separator (i.e., the @\'.\'@ in @1,234.56789@)
  -> Word8
  -- ^ Number of decimal numbers to render, if any.
  -> ExchangeRate src dst
  -- ^ The 'ExchangeRate' to render.
  -> Maybe T.Text
  -- ^ Returns 'Nothing' if the given separators are not acceptable (i.e., they
  -- are digits, or they are equal).
{-# INLINABLE exchangeRateToDecimal #-}
exchangeRateToDecimal a ytsep dsep fdigs0 = \(ExchangeRate r0) ->
  rationalToDecimal a False ytsep dsep fdigs0 r0

-- | Render a 'Rational' number as a decimal approximation.
--
-- This function returns 'Nothing' if it is not possible to reliably render the
-- decimal string due to a bad choice of separators. That is, if the separators
-- are digits or equal among themselves, this function returns 'Nothing'.
rationalToDecimal
  :: Approximation
  -- ^ Approximation to use if necesary in order to fit the 'Dense' amount in
  -- as many decimal numbers as requested.
  -> Bool
  -- ^ Whether to render a leading @\'+\'@ sign in case the amount is positive.
  -> Maybe Char
  -- ^ Thousands separator for the integer part, if any (i.e., the @\',\'@ in
  -- @1,234.56789@).
  -> Char
  -- ^ Decimal separator (i.e., the @\'.\'@ in @1,234.56789@)
  -> Word8
  -- ^ Number of decimal numbers to render, if any.
  -> Rational
  -- ^ The dense monetary amount to render.
  -> Maybe T.Text
  -- ^ Returns 'Nothing' if the given separators are not acceptable (i.e., they
  -- are digits, or they are equal).
{-# INLINABLE rationalToDecimal #-}
rationalToDecimal a plus ytsep dsep fdigs0 = \r0 -> do
  guard (not (Char.isDigit dsep))
  for_ ytsep $ \tsep ->
     guard (tsep /= dsep && not (Char.isDigit tsep))
  -- this string-fu is not particularly efficient.
  let parts = approximate a (r0 * (10 ^ fdigs0)) :: Integer
      ipart = fromInteger (abs parts) `div` (10 ^ fdigs0) :: Natural
      ftext | ipart == 0 = show (abs parts) :: String
            | otherwise = drop (length (show ipart)) (show (abs parts))
      itext = maybe (show ipart) (renderThousands ipart) ytsep :: String
      fpad0 = List.replicate (fromIntegral fdigs0 - length ftext) '0' :: String
  Just $ T.pack $ mconcat
    [ if | parts < 0 -> "-"
         | plus && parts > 0 -> "+"
         | otherwise -> ""
    , itext
    , if | fdigs0 > 0 -> dsep : ftext <> fpad0
         | otherwise -> ""
    ]


-- | Render a 'Natural' number with thousand markers.
--
-- @
-- > 'renderThousands' 12045 \',\'
-- \"12,045\"
-- @
renderThousands :: Natural -> Char -> String
{-# INLINABLE renderThousands #-}
renderThousands n0   -- TODO better use text
  | n0 < 1000 = \_ -> show n0
  | otherwise = \c -> List.foldl' (flip mappend) mempty (List.unfoldr (f c) n0)
      where f :: Char -> Natural -> Maybe (String, Natural)
            f c = \x -> case divMod x 1000 of
                           (0, 0) -> Nothing
                           (0, z) -> Just (show z, 0)
                           (y, z) | z <  10   -> Just (c:'0':'0':show z, y)
                                  | z < 100   -> Just (c:'0':show z, y)
                                  | otherwise -> Just (c:show z, y)

--------------------------------------------------------------------------------
-- Decimal parsing

-- | Parses a decimal representation of a 'Dense'.
--
-- Leading @\'-\'@ and @\'+\'@ characters are considered.
denseFromDecimal
  :: Maybe Char
  -- ^ Thousands separator for the integer part, if any (i.e., the @\',\'@ in
  -- @-1,234.56789@).
  -> Char
  -- ^ Decimal separator (i.e., the @\'.\'@ in @-1,234.56789@)
  -> Rational
  -- ^ Scale used by the rendered decimal. It is important to get this number
  -- correctly, otherwise the resulting 'Dense' amount will be wrong. Please
  -- refer to the documentation for 'denseToDecimal' to understand the meaning
  -- of this scale.
  --
  -- In summary, this scale will have a value of @1@ unless the decimal amount
  -- represents a unit other than the main unit for the currency (e.g., cents
  -- rather than dollars for USD, or grams rather than troy-ounces for XAU, or
  -- millibitcoins rather than bitcoins for BTC).
  -> T.Text
  -- ^ The raw string containing the decimal representation (e.g.,
  -- @"-1,234.56789"@).
  -> Maybe (Dense currency)
denseFromDecimal yst sf scal str = do
  guard (scal > 0)
  r <- rationalFromDecimal yst sf str
  pure (Dense $! (r / scal))

-- | Parses a decimal representation of a 'Discrete'.
--
-- Leading @\'-\'@ and @\'+\'@ characters are considered.
--
-- Notice that parsing will fail unless the entire precision of the decimal
-- number can be represented in the desired @scale@.
discreteFromDecimal
  :: GoodScale scale
  => Maybe Char
  -- ^ Thousands separator for the integer part, if any (i.e., the @\',\'@ in
  -- @-1,234.56789@).
  -> Char
  -- ^ Decimal separator (i.e., the @\'.\'@ in @-1,234.56789@)
  -> Rational
  -- ^ Scale used by the rendered decimal. It is important to get this number
  -- correctly, otherwise the resulting 'Dense' amount will be wrong. Please
  -- refer to the documentation for 'denseToDecimal' to understand the meaning
  -- of this scale.
  --
  -- In summary, this scale will have a value of @1@ unless the decimal amount
  -- represents a unit other than the main unit for the currency (e.g., cents
  -- rather than dollars for USD, or grams rather than troy-ounces for XAU, or
  -- millibitcoins rather than bitcoins for BTC).
  -> T.Text
  -- ^ The raw string containing the decimal representation (e.g.,
  -- @"-1,234.56789"@).
  -> Maybe (Discrete' currency scale)
discreteFromDecimal yst sf scal = \str -> do
  dns <- denseFromDecimal yst sf scal str
  case discreteFromDense Truncate dns of
    (x, 0) -> Just x
    _ -> Nothing -- We fail for decimals that don't fit exactly in our scale.

-- | Parses a decimal representation of an 'ExchangeRate'.
exchangeRateFromDecimal
  :: Maybe Char
  -- ^ Thousands separator for the integer part, if any (i.e., the @\',\'@ in
  -- @1,234.56789@).
  -> Char
  -- ^ Decimal separator (i.e., the @\'.\'@ in @1,234.56789@)
  -> T.Text
  -- ^ The raw string containing the decimal representation (e.g.,
  -- @"1,234.56789"@).
  -> Maybe (ExchangeRate src dst)
exchangeRateFromDecimal yst sf t
  | T.isPrefixOf "-" t = Nothing
  | otherwise = exchangeRate =<< rationalFromDecimal yst sf t

rationalFromDecimal
  :: Maybe Char
  -- ^ Thousands separator for the integer part, if any (i.e., the @\',\'@ in
  -- @-1,234.56789@).
  -> Char
  -- ^ Decimal separator (i.e., the @\'.\'@ in @-1,234.56789@)
  -> T.Text
  -- ^ The raw string containing the decimal representation (e.g.,
  -- @"-1,234.56789"@).
  -> Maybe Rational
rationalFromDecimal yst sf = \t ->
  case ReadP.readP_to_S (rationalFromDecimalP yst sf) (T.unpack t) of
    [(x,"")] -> Just x
    _ -> Nothing

-- TODO limit number of digits parsed to prevent DoS
rationalFromDecimalP
  :: Maybe Char
  -- ^ Thousands separator for the integer part, if any (i.e., the @\',\'@ in
  -- @-1,234.56789@).
  --
  -- The separator can't be a digit or control character. If it is, then parsing
  -- will always fail.
  -> Char
  -- ^ Decimal separator (i.e., the @\'.\'@ in @-1,234.56789@).
  --
  -- The separator can't be a digit or control character. If it is, then parsing
  -- will always fail.
  -> ReadP.ReadP Rational
rationalFromDecimalP ytsep dsep = do
   for_ ytsep $ \tsep ->
      guard (tsep /= dsep && not (Char.isDigit tsep))
   guard (not (Char.isDigit dsep))
   sig :: Rational -> Rational <-
     (ReadP.char '-' $> negate) <|>
     (ReadP.char '+' $> id) <|>
     (pure id)
   ipart :: String <- case ytsep of
     Nothing -> ReadP.munch1 Char.isDigit
     Just tsep -> mappend
       <$> (ReadP.count 3 (ReadP.satisfy Char.isDigit) <|>
            ReadP.count 2 (ReadP.satisfy Char.isDigit) <|>
            ReadP.count 1 (ReadP.satisfy Char.isDigit))
       <*> (fmap concat $ ReadP.many
              (ReadP.char tsep *> ReadP.count 3 (ReadP.satisfy Char.isDigit)))
   yfpart :: Maybe String <-
     (ReadP.char dsep *> fmap Just (ReadP.munch1 Char.isDigit) <* ReadP.eof) <|>
     (ReadP.eof $> Nothing)
   pure $! sig $ case yfpart of
     Nothing -> fromInteger (read ipart)
     Just fpart -> read (ipart <> fpart) % (10 ^ length fpart)

--------------------------------------------------------------------------------
-- QuickCheck Arbitrary instances

instance
  ( GoodScale scale
  ) => QC.Arbitrary (Discrete' currency scale) where
  arbitrary = fmap fromInteger QC.arbitrary
  shrink = fmap fromInteger . QC.shrink . toInteger

instance QC.Arbitrary SomeDiscrete where
  arbitrary = do
    let md = mkSomeDiscrete
               <$> fmap T.pack QC.arbitrary
               <*> QC.arbitrary
               <*> QC.arbitrary
    fromJust <$> QC.suchThat md isJust
  shrink = \x -> withSomeDiscrete x (map toSomeDiscrete . QC.shrink)

instance QC.Arbitrary (Dense currency) where
  arbitrary = do
     let myd = fmap dense QC.arbitrary
     fromJust <$> QC.suchThat myd isJust
  shrink = catMaybes . map dense . QC.shrink . toRational

instance QC.Arbitrary SomeDense where
  arbitrary = do
    let md = mkSomeDense <$> fmap T.pack QC.arbitrary <*> QC.arbitrary
    fromJust <$> QC.suchThat md isJust
  shrink = \x -> withSomeDense x (map toSomeDense . QC.shrink)

instance QC.Arbitrary (ExchangeRate src dst) where
  arbitrary = do
    let myxr = fmap exchangeRate QC.arbitrary
    fromJust <$> QC.suchThat myxr isJust
  shrink = catMaybes . map exchangeRate
         . QC.shrink . exchangeRateToRational

instance QC.Arbitrary SomeExchangeRate where
  arbitrary = do
    let md = mkSomeExchangeRate
               <$> fmap T.pack QC.arbitrary
               <*> fmap T.pack QC.arbitrary
               <*> QC.arbitrary
    fromJust <$> QC.suchThat md isJust
  shrink = \x -> withSomeExchangeRate x (map toSomeExchangeRate . QC.shrink)

instance QC.Arbitrary Approximation where
  arbitrary = QC.oneof [ pure Round, pure Floor, pure Ceiling, pure Truncate ]

{-# LANGUAGE CPP #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeApplications #-}

module Main where

import Control.Category (Category((.), id))
import Control.DeepSeq (rnf)
import qualified Data.AdditiveGroup as AG
import qualified Data.Binary as Binary
import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy as BL
import qualified Data.Char as Char
import Data.Maybe (catMaybes, fromJust, fromMaybe, isJust, isNothing)
import Data.Proxy (Proxy(Proxy))
import Data.Ratio ((%), numerator, denominator)
import qualified Data.Text as T
import qualified Data.VectorSpace as VS
import Data.Word (Word8)
import GHC.Exts (fromList)
import GHC.TypeLits (Nat, Symbol, KnownSymbol, symbolVal)
import Prelude hiding ((.), id)
import qualified Test.Tasty as Tasty
import Test.Tasty.HUnit ((@?=), (@=?))
import qualified Test.Tasty.HUnit as HU
import qualified Test.Tasty.Runners as Tasty
import Test.Tasty.QuickCheck ((===), (==>), (.&&.))
import qualified Test.Tasty.QuickCheck as QC


import qualified Money
import qualified Money.Internal as MoneyI
  (rationalFromDecimal, rationalToDecimal)

--------------------------------------------------------------------------------

-- | Generates a valid 'MoneyI.rationalToDecimal' result. Returns the thousand
-- and decimal separators as welland decimal separators as well.
genDecimal :: QC.Gen (T.Text, Maybe Char, Char)
genDecimal = do
  aprox :: Money.Approximation <- QC.arbitrary
  plus :: Bool <- QC.arbitrary
  digs :: Word8 <- QC.arbitrary
  r :: Rational <- (%) <$> QC.arbitrary <*> QC.suchThat QC.arbitrary (/= 0)
  (yts, ds) <- genDecimalSeps
  let
      dec = fromMaybe
          (error "genDecimal failed because rationalToDecimal returned Nothing")
          (MoneyI.rationalToDecimal aprox plus yts ds digs r)
  pure (dec, yts, ds)

-- | Generates valid separators for decimal representations (see genDecimal).
genDecimalSeps :: QC.Gen (Maybe Char, Char)
genDecimalSeps = do
  let msep = QC.suchThat QC.arbitrary (not . Char.isDigit)
  ds :: Char <- msep
  yts :: Maybe Char <- genMaybe (QC.suchThat msep (/= ds))
  pure (yts, ds)


genMaybe :: QC.Gen a -> QC.Gen (Maybe a)
genMaybe m = QC.oneof [pure Nothing, fmap Just m]

--------------------------------------------------------------------------------

main :: IO ()
main =  Tasty.defaultMainWithIngredients
  [ Tasty.consoleTestReporter
  , Tasty.listingTests
  ] (Tasty.localOption (QC.QuickCheckTests 100) tests)

tests :: Tasty.TestTree
tests =
  Tasty.testGroup "root"
  [ testCurrencies
  , testCurrencyUnits
  , testExchange
  , testRationalToDecimal
  , testRationalFromDecimal
  , testDiscreteFromDecimal
  , testRawSerializations
  ]

testCurrencies :: Tasty.TestTree
testCurrencies =
  Tasty.testGroup "Currency"
  [ testDense (Proxy :: Proxy "BTC")  -- A cryptocurrency.
  , testDense (Proxy :: Proxy "USD")  -- A fiat currency with decimal fractions.
  , testDense (Proxy :: Proxy "VUV")  -- A fiat currency with non-decimal fractions.
  , testDense (Proxy :: Proxy "XAU")  -- A precious metal.
  ]

testCurrencyUnits :: Tasty.TestTree
testCurrencyUnits =
  Tasty.testGroup "Currency units"
  [ testDiscrete (Proxy :: Proxy "BTC") (Proxy :: Proxy "BTC")
  , testDiscrete (Proxy :: Proxy "BTC") (Proxy :: Proxy "satoshi")
  , testDiscrete (Proxy :: Proxy "BTC") (Proxy :: Proxy "bitcoin")
  , testDiscrete (Proxy :: Proxy "USD") (Proxy :: Proxy "USD")
  , testDiscrete (Proxy :: Proxy "USD") (Proxy :: Proxy "cent")
  , testDiscrete (Proxy :: Proxy "USD") (Proxy :: Proxy "dollar")
  , testDiscrete (Proxy :: Proxy "VUV") (Proxy :: Proxy "vatu")
  , testDiscrete (Proxy :: Proxy "XAU") (Proxy :: Proxy "gram")
  , testDiscrete (Proxy :: Proxy "XAU") (Proxy :: Proxy "grain")
  ]


testRationalToDecimal :: Tasty.TestTree
testRationalToDecimal =
  Tasty.testGroup "rationalToDecimal"
  [ HU.testCase "Round: r1" $ do
       render Money.Round r1 @?=
         [ "1023004567.90"        --  0
         , "1,023,004,567.90"     --  1
         , "+1023004567.90"       --  2
         , "+1,023,004,567.90"    --  3
         , "1023004568"           --  8
         , "1,023,004,568"        --  9
         , "+1023004568"          -- 10
         , "+1,023,004,568"       -- 11
         ]
  , HU.testCase "Round: negate r1" $ do
       render Money.Round (negate r1) @?=
         [ "-1023004567.90"       --  0
         , "-1,023,004,567.90"    --  1
         , "-1023004567.90"       --  2
         , "-1,023,004,567.90"    --  3
         , "-1023004568"          --  8
         , "-1,023,004,568"       --  9
         , "-1023004568"          -- 10
         , "-1,023,004,568"       -- 11
         ]
  , HU.testCase "Round: r2" $ do
       render Money.Round r2 @?=
         [ "1.23"    --  0
         , "1.23"    --  1
         , "+1.23"   --  2
         , "+1.23"   --  3
         , "1"       --  8
         , "1"       --  9
         , "+1"      -- 10
         , "+1"      -- 11
         ]
  , HU.testCase "Round: negate r2" $ do
       render Money.Round (negate r2) @?=
         [ "-1.23"    --  0
         , "-1.23"    --  1
         , "-1.23"    --  2
         , "-1.23"    --  3
         , "-1"       --  8
         , "-1"       --  9
         , "-1"       -- 10
         , "-1"       -- 11
         ]
  , HU.testCase "Round: r3" $ do
       render Money.Round r3 @?=
         [ "0.34"   --  0
         , "0.34"   --  1
         , "+0.34"  --  2
         , "+0.34"  --  3
         , "0"      --  8
         , "0"      --  9
         , "0"      -- 10
         , "0"      -- 11
         ]
  , HU.testCase "Round: negate r3" $ do
       render Money.Round (negate r3) @?=
         [ "-0.34"   --  0
         , "-0.34"   --  1
         , "-0.34"   --  2
         , "-0.34"   --  3
         , "0"       --  8
         , "0"       --  9
         , "0"       -- 10
         , "0"       -- 11
         ]
  , HU.testCase "Floor: r1" $ do
       render Money.Floor r1 @?=
         [ "1023004567.89"        --  0
         , "1,023,004,567.89"     --  1
         , "+1023004567.89"       --  2
         , "+1,023,004,567.89"    --  3
         , "1023004567"           --  8
         , "1,023,004,567"        --  9
         , "+1023004567"          -- 10
         , "+1,023,004,567"       -- 11
         ]
  , HU.testCase "Floor: negate r1" $ do
       render Money.Floor (negate r1) @?=
         [ "-1023004567.90"       --  0
         , "-1,023,004,567.90"    --  1
         , "-1023004567.90"       --  2
         , "-1,023,004,567.90"    --  3
         , "-1023004568"          --  8
         , "-1,023,004,568"       --  9
         , "-1023004568"          -- 10
         , "-1,023,004,568"       -- 11
         ]
  , HU.testCase "Floor: r2" $ do
       render Money.Floor r2 @?=
         [ "1.23"    --  0
         , "1.23"    --  1
         , "+1.23"   --  2
         , "+1.23"   --  3
         , "1"       --  8
         , "1"       --  9
         , "+1"      -- 10
         , "+1"      -- 11
         ]
  , HU.testCase "Floor: negate r2" $ do
       render Money.Floor (negate r2) @?=
         [ "-1.23"    --  0
         , "-1.23"    --  1
         , "-1.23"    --  2
         , "-1.23"    --  3
         , "-2"       --  8
         , "-2"       --  9
         , "-2"       -- 10
         , "-2"       -- 11
         ]
  , HU.testCase "Floor: r3" $ do
       render Money.Floor r3 @?=
         [ "0.34"   --  0
         , "0.34"   --  1
         , "+0.34"  --  2
         , "+0.34"  --  3
         , "0"      --  8
         , "0"      --  9
         , "0"      -- 10
         , "0"      -- 11
         ]
  , HU.testCase "Floor: negate r3" $ do
       render Money.Floor (negate r3) @?=
         [ "-0.35"   --  0
         , "-0.35"   --  1
         , "-0.35"   --  2
         , "-0.35"   --  3
         , "-1"      --  8
         , "-1"      --  9
         , "-1"      -- 10
         , "-1"      -- 11
         ]
  , HU.testCase "Ceiling: r1" $ do
       render Money.Ceiling r1 @?=
         [ "1023004567.90"        --  0
         , "1,023,004,567.90"     --  1
         , "+1023004567.90"       --  2
         , "+1,023,004,567.90"    --  3
         , "1023004568"           --  8
         , "1,023,004,568"        --  9
         , "+1023004568"          -- 10
         , "+1,023,004,568"       -- 11
         ]
  , HU.testCase "Ceiling: negate r1" $ do
       render Money.Ceiling (negate r1) @?=
         [ "-1023004567.89"       --  0
         , "-1,023,004,567.89"    --  1
         , "-1023004567.89"       --  2
         , "-1,023,004,567.89"    --  3
         , "-1023004567"          --  8
         , "-1,023,004,567"       --  9
         , "-1023004567"          -- 10
         , "-1,023,004,567"       -- 11
         ]
  , HU.testCase "Ceiling: r2" $ do
       render Money.Ceiling r2 @?=
         [ "1.23"    --  0
         , "1.23"    --  1
         , "+1.23"   --  2
         , "+1.23"   --  3
         , "2"       --  8
         , "2"       --  9
         , "+2"      -- 10
         , "+2"      -- 11
         ]
  , HU.testCase "Ceiling: negate r2" $ do
       render Money.Ceiling (negate r2) @?=
         [ "-1.23"    --  0
         , "-1.23"    --  1
         , "-1.23"    --  2
         , "-1.23"    --  3
         , "-1"       --  8
         , "-1"       --  9
         , "-1"       -- 10
         , "-1"       -- 11
         ]
  , HU.testCase "Ceiling: r3" $ do
       render Money.Ceiling r3 @?=
         [ "0.35"   --  0
         , "0.35"   --  1
         , "+0.35"  --  2
         , "+0.35"  --  3
         , "1"      --  8
         , "1"      --  9
         , "+1"     -- 10
         , "+1"     -- 11
         ]
  , HU.testCase "Ceiling: negate r3" $ do
       render Money.Ceiling (negate r3) @?=
         [ "-0.34"   --  0
         , "-0.34"   --  1
         , "-0.34"   --  2
         , "-0.34"   --  3
         , "0"       --  8
         , "0"       --  9
         , "0"       -- 10
         , "0"       -- 11
         ]

  , HU.testCase "Truncate: r1" $ do
      render Money.Truncate r1 @?= render Money.Floor r1

  , HU.testCase "Truncate: negate r1" $ do
      render Money.Truncate (negate r1) @?= render Money.Ceiling (negate r1)

  , HU.testCase "Truncate: r2" $ do
      render Money.Truncate r2 @?= render Money.Floor r2

  , HU.testCase "Truncate: negate r2" $ do
      render Money.Truncate (negate r2) @?= render Money.Ceiling (negate r2)

  , HU.testCase "Truncate: r3" $ do
      render Money.Truncate r3 @?= render Money.Floor r3

  , HU.testCase "Truncate: negate r3" $ do
      render Money.Truncate (negate r3) @?= render Money.Ceiling (negate r3)
  ]
  where
    r1 :: Rational = 1023004567895 % 1000
    r2 :: Rational = 123 % 100
    r3 :: Rational = 345 % 1000

    render :: Money.Approximation -> Rational -> [T.Text]
    render a r =
      [ fromJust $ MoneyI.rationalToDecimal a False Nothing    '.' 2 r  --  0
      , fromJust $ MoneyI.rationalToDecimal a False (Just ',') '.' 2 r  --  1
      , fromJust $ MoneyI.rationalToDecimal a True  Nothing    '.' 2 r  --  2
      , fromJust $ MoneyI.rationalToDecimal a True  (Just ',') '.' 2 r  --  3
      , fromJust $ MoneyI.rationalToDecimal a False Nothing    '.' 0 r  --  8
      , fromJust $ MoneyI.rationalToDecimal a False (Just ',') '.' 0 r  --  9
      , fromJust $ MoneyI.rationalToDecimal a True  Nothing    '.' 0 r  -- 10
      , fromJust $ MoneyI.rationalToDecimal a True  (Just ',') '.' 0 r  -- 11
      ]

testRationalFromDecimal :: Tasty.TestTree
testRationalFromDecimal =
  Tasty.testGroup "rationalFromDecimal"
  [ QC.testProperty "Unsupported separators" $
      let mbadsep :: QC.Gen Char = QC.suchThat QC.arbitrary Char.isDigit
          mgoodsep :: QC.Gen Char = QC.suchThat QC.arbitrary (not . Char.isDigit)
      in QC.forAll ((,,) <$> mbadsep <*> mbadsep <*> mgoodsep) $
           \(s1 :: Char, s2 :: Char, s3 :: Char) ->
              let f = MoneyI.rationalFromDecimal
              in (f Nothing s1 (error "untouched") === Nothing) .&&.
                 (f (Just s1) s2 (error "untouched") === Nothing) .&&.
                 (f (Just s1) s1 (error "untouched") === Nothing) .&&.
                 (f (Just s3) s3 (error "untouched") === Nothing)

  , Tasty.localOption (QC.QuickCheckTests 1000) $
    QC.testProperty "Lossy roundtrip" $
      -- We check that the roundtrip results in a close amount with a fractional
      -- difference of up to one.
      let gen = (,) <$> genDecimalSeps <*> QC.arbitrary
      in QC.forAll gen $ \( (yst :: Maybe Char, sd :: Char)
                          , (r :: Rational, plus :: Bool, digs :: Word8,
                             aprox :: Money.Approximation) ) ->
           let Just dec = MoneyI.rationalToDecimal aprox plus yst sd digs r
               Just r' = MoneyI.rationalFromDecimal yst sd dec
           in 1 > abs (abs r - abs r')
  ]

testDense
  :: forall currency
  .  KnownSymbol currency
  => Proxy currency
  -> Tasty.TestTree
testDense pc =
  Tasty.testGroup ("Dense " ++ show (symbolVal pc))
  [ QC.testProperty "rnf" $
      QC.forAll QC.arbitrary $ \(x :: Money.Dense currency) ->
         () === rnf x

  , QC.testProperty "read . show == id" $
      QC.forAll QC.arbitrary $ \(x :: Money.Dense currency) ->
         x === read (show x)

  , QC.testProperty "read . show . Just == Just " $
      QC.forAll QC.arbitrary $ \(x :: Money.Dense currency) ->
         Just x === read (show (Just x))

  , QC.testProperty "fromSomeDense . someDense == Just" $
      QC.forAll QC.arbitrary $ \(x :: Money.Dense currency) ->
         Just x === Money.fromSomeDense (Money.toSomeDense x)

  , QC.testProperty "fromSomeDense works only for same currency" $
      QC.forAll QC.arbitrary $ \(dr :: Money.SomeDense) ->
        (T.unpack (Money.someDenseCurrency dr) /= symbolVal pc)
           ==> isNothing (Money.fromSomeDense dr :: Maybe (Money.Dense currency))

  , QC.testProperty "withSomeDense" $
      QC.forAll QC.arbitrary $ \(x :: Money.Dense currency) ->
        let dr = Money.toSomeDense x
        in Money.withSomeDense dr $ \x' ->
             (show x, dr, Money.toSomeDense (x + 1))
                === (show x', Money.toSomeDense x', Money.toSomeDense (x' + 1))

  , QC.testProperty "denseCurrency" $
      QC.forAll QC.arbitrary $ \(x :: Money.Dense currency) ->
        T.unpack (Money.denseCurrency x) === symbolVal pc

  , QC.testProperty "denseToDecimal: Same as rationalToDecimal" $
      let gen = (,) <$> genDecimalSeps <*> QC.arbitrary
      in QC.forAll gen $ \( (yst :: Maybe Char, sd :: Char)
                          , (dns :: Money.Dense currency, plus :: Bool,
                             digs :: Word8, aprox :: Money.Approximation) ) ->
            let ydnsd1 = Money.denseToDecimal aprox plus yst sd digs 1 dns
                ydnsd100 = Money.denseToDecimal aprox plus yst sd digs 100 dns
                yrd1 = MoneyI.rationalToDecimal aprox plus yst sd digs (toRational dns)
                yrd100 = MoneyI.rationalToDecimal aprox plus yst sd digs (toRational dns * 100)
            in (ydnsd1 === yrd1) .&&. (ydnsd100 === yrd100)

  , QC.testProperty "denseFromDecimal: Same as rationalFromDecimal" $
      QC.forAll genDecimal $ \(dec :: T.Text, yts :: Maybe Char, ds :: Char) ->
         let Just r = MoneyI.rationalFromDecimal yts ds dec
             Just dns = Money.denseFromDecimal yts ds 1 dec
         in r === toRational (dns :: Money.Dense currency)

  , QC.testProperty "denseFromDecimal: Same as rationalFromDecimal" $
      QC.forAll genDecimal $ \(dec :: T.Text, yts :: Maybe Char, ds :: Char) ->
         let Just r = MoneyI.rationalFromDecimal yts ds dec
             Just dns = Money.denseFromDecimal yts ds 1 dec
         in r === toRational (dns :: Money.Dense currency)


  , Tasty.localOption (QC.QuickCheckTests 1000) $
    QC.testProperty "denseToDecimal/denseFromDiscrete: Lossy roundtrip" $
      -- We check that the roundtrip results in a close amount with a fractional
      -- difference of up to one.
      let gen = (,) <$> genDecimalSeps <*> QC.arbitrary
      in QC.forAll gen $ \( (yst :: Maybe Char, sd :: Char)
                          , (sc0 :: Rational, plus :: Bool,
                             digs :: Word8, aprox :: Money.Approximation,
                             dns :: Money.Dense currency) ) ->
           let sc = abs sc0 + 1 -- smaller scales can't reliably be parsed back
               Just dec = Money.denseToDecimal aprox plus yst sd digs sc dns
               Just dns' = Money.denseFromDecimal yst sd sc dec
           in Money.dense' 1 > abs (abs dns - abs dns')

  , HU.testCase "AdditiveGroup: zeroV" $
      (AG.zeroV :: Money.Dense currency) @?= Money.dense' (0%1)
  , QC.testProperty "AdditiveGroup: negateV" $
      QC.forAll QC.arbitrary $ \(x :: Money.Dense currency) ->
         AG.negateV x === negate x
  , QC.testProperty "AdditiveGroup: ^+^" $
      QC.forAll QC.arbitrary $ \(x :: Money.Dense currency, y) ->
         x AG.^+^ y === x + y
  , QC.testProperty "AdditiveGroup: ^-^" $
      QC.forAll QC.arbitrary $ \(x :: Money.Dense currency, y) ->
         x AG.^-^ y === x - y
  , QC.testProperty "VectorSpace: *^" $
      QC.forAll QC.arbitrary $ \(x :: Money.Dense currency, y) ->
         (toRational x VS.*^ y === x * y) .&&.
         (toRational y VS.*^ x === x * y)

  , QC.testProperty "Binary encoding roundtrip" $
      QC.forAll QC.arbitrary $ \(x :: Money.Dense currency) ->
         let Right (_,_,y) = Binary.decodeOrFail (Binary.encode x)
         in x === y
  , QC.testProperty "Binary encoding roundtrip (SomeDense)" $
      QC.forAll QC.arbitrary $ \(x :: Money.Dense currency) ->
         let x' = Money.toSomeDense x
             bs = Binary.encode x'
         in Right (mempty, BL.length bs, x') === Binary.decodeOrFail bs
  , QC.testProperty "Binary encoding roundtrip (Dense through SomeDense)" $
      QC.forAll QC.arbitrary $ \(x :: Money.Dense currency) ->
         let x' = Money.toSomeDense x
             bs = Binary.encode x'
         in Right (mempty, BL.length bs, x) === Binary.decodeOrFail bs
  , QC.testProperty "Binary encoding roundtrip (SomeDense through Dense)" $
      QC.forAll QC.arbitrary $ \(x :: Money.Dense currency) ->
         let x' = Money.toSomeDense x
             bs = Binary.encode x
         in Right (mempty, BL.length bs, x') === Binary.decodeOrFail bs
  ]

testExchange :: Tasty.TestTree
testExchange =
  Tasty.testGroup "Exchange"
  [ testExchangeRate (Proxy :: Proxy "BTC") (Proxy :: Proxy "BTC")
  , testExchangeRate (Proxy :: Proxy "BTC") (Proxy :: Proxy "USD")
  , testExchangeRate (Proxy :: Proxy "BTC") (Proxy :: Proxy "VUV")
  , testExchangeRate (Proxy :: Proxy "BTC") (Proxy :: Proxy "XAU")
  , testExchangeRate (Proxy :: Proxy "USD") (Proxy :: Proxy "BTC")
  , testExchangeRate (Proxy :: Proxy "USD") (Proxy :: Proxy "USD")
  , testExchangeRate (Proxy :: Proxy "USD") (Proxy :: Proxy "VUV")
  , testExchangeRate (Proxy :: Proxy "USD") (Proxy :: Proxy "XAU")
  , testExchangeRate (Proxy :: Proxy "VUV") (Proxy :: Proxy "BTC")
  , testExchangeRate (Proxy :: Proxy "VUV") (Proxy :: Proxy "USD")
  , testExchangeRate (Proxy :: Proxy "VUV") (Proxy :: Proxy "VUV")
  , testExchangeRate (Proxy :: Proxy "VUV") (Proxy :: Proxy "XAU")
  , testExchangeRate (Proxy :: Proxy "XAU") (Proxy :: Proxy "BTC")
  , testExchangeRate (Proxy :: Proxy "XAU") (Proxy :: Proxy "USD")
  , testExchangeRate (Proxy :: Proxy "XAU") (Proxy :: Proxy "VUV")
  , testExchangeRate (Proxy :: Proxy "XAU") (Proxy :: Proxy "XAU")
  ]


testDiscrete
  :: forall (currency :: Symbol) (unit :: Symbol)
  .  ( Money.GoodScale (Money.Scale currency unit)
     , KnownSymbol currency
     , KnownSymbol unit )
  => Proxy currency
  -> Proxy unit
  -> Tasty.TestTree
testDiscrete pc pu =
  Tasty.testGroup ("Discrete " ++ show (symbolVal pc) ++ " "
                               ++ show (symbolVal pu))
  [ testRounding pc pu

  , QC.testProperty "rnf" $
      QC.forAll QC.arbitrary $ \(x :: Money.Discrete currency unit) ->
         () === rnf x

  , QC.testProperty "read . show == id" $
      QC.forAll QC.arbitrary $ \(x :: Money.Discrete currency unit) ->
         x === read (show x)
  , QC.testProperty "read . show . Just == Just" $
      QC.forAll QC.arbitrary $ \(x :: Money.Discrete currency unit) ->
         Just x === read (show (Just x))
  , QC.testProperty "fromSomeDiscrete . someDiscrete == Just" $
      QC.forAll QC.arbitrary $ \(x :: Money.Discrete currency unit) ->
         Just x === Money.fromSomeDiscrete (Money.toSomeDiscrete x)
  , QC.testProperty "fromSomeDiscrete works only for same currency and scale" $
      QC.forAll QC.arbitrary $ \(dr :: Money.SomeDiscrete) ->
        ((T.unpack (Money.someDiscreteCurrency dr) /= symbolVal pc) &&
         (Money.someDiscreteScale dr /=
             Money.scale (Proxy :: Proxy (Money.Scale currency unit)))
        ) ==> isNothing (Money.fromSomeDiscrete dr
                          :: Maybe (Money.Discrete currency unit))
  , QC.testProperty "withSomeDiscrete" $
      QC.forAll QC.arbitrary $ \(x :: Money.Discrete currency unit) ->
        let dr = Money.toSomeDiscrete x
        in ( Money.withSomeDiscrete dr $ \x' ->
                (show x, dr, Money.toSomeDiscrete (x + 1))
                   === (show x', Money.toSomeDiscrete x', Money.toSomeDiscrete (x' + 1))
           ) :: QC.Property

  , QC.testProperty "discreteCurrency" $
      QC.forAll QC.arbitrary $ \(x :: Money.Discrete currency unit) ->
        T.unpack (Money.discreteCurrency x) === symbolVal pc

  , QC.testProperty "discreteToDecimal/discreteFromDecimal: Same as denseToDecimal/denseFromDecimal" $
      -- We check that the roundtrip results in a close amount with a fractional
      -- difference of up to one.
      let gen = (,) <$> genDecimalSeps <*> QC.arbitrary
      in QC.forAll gen $ \( (yst :: Maybe Char, sd :: Char)
                          , (sc0 :: Rational, plus :: Bool,
                             digs :: Word8, aprox :: Money.Approximation,
                             dis :: Money.Discrete currency unit) ) ->
           let sc = abs sc0 + 1  -- scale can't be less than 1
               dns = Money.denseFromDiscrete dis
               ydec = Money.discreteToDecimal aprox plus yst sd digs sc dis
               ydec' = Money.denseToDecimal aprox plus yst sd digs sc dns
           in ydec === ydec'

  , HU.testCase "AdditiveGroup: zeroV" $
      (AG.zeroV :: Money.Discrete currency unit) @?= Money.discrete 0
  , QC.testProperty "AdditiveGroup: negateV" $
      QC.forAll QC.arbitrary $ \(x :: Money.Discrete currency unit) ->
         AG.negateV x === negate x
  , QC.testProperty "AdditiveGroup: ^+^" $
      QC.forAll QC.arbitrary $ \(x :: Money.Discrete currency unit, y) ->
         x AG.^+^ y === x + y
  , QC.testProperty "AdditiveGroup: ^-^" $
      QC.forAll QC.arbitrary $ \(x :: Money.Discrete currency unit, y) ->
         x AG.^-^ y === x - y
  , QC.testProperty "VectorSpace: *^" $
      QC.forAll QC.arbitrary $ \(x :: Money.Discrete currency unit, y) ->
         (toInteger x VS.*^ y === x * y) .&&.
         (toInteger y VS.*^ x === x * y)

  , QC.testProperty "Binary encoding roundtrip" $
      QC.forAll QC.arbitrary $ \(x :: Money.Discrete currency unit) ->
         let Right (_,_,y) = Binary.decodeOrFail (Binary.encode x)
         in x === y
  , QC.testProperty "Binary encoding roundtrip (SomeDiscrete)" $
      QC.forAll QC.arbitrary $ \(x :: Money.Discrete currency unit) ->
         let x' = Money.toSomeDiscrete x
             bs = Binary.encode x'
         in Right (mempty, BL.length bs, x') === Binary.decodeOrFail bs
  , QC.testProperty "Binary encoding roundtrip (Discrete through SomeDiscrete)" $
      QC.forAll QC.arbitrary $ \(x :: Money.Discrete currency unit) ->
         let x' = Money.toSomeDiscrete x
             bs = Binary.encode x'
         in Right (mempty, BL.length bs, x) === Binary.decodeOrFail bs
  , QC.testProperty "Binary encoding roundtrip (SomeDiscrete through Discrete)" $
      QC.forAll QC.arbitrary $ \(x :: Money.Discrete currency unit) ->
         let x' = Money.toSomeDiscrete x
             bs = Binary.encode x
         in Right (mempty, BL.length bs, x') === Binary.decodeOrFail bs
  ]

testExchangeRate
  :: forall (src :: Symbol) (dst :: Symbol)
  .  (KnownSymbol src, KnownSymbol dst)
  => Proxy src
  -> Proxy dst
  -> Tasty.TestTree
testExchangeRate ps pd =
  Tasty.testGroup ("ExchangeRate " ++ show (symbolVal ps) ++ " "
                                   ++ show (symbolVal pd))
  [ QC.testProperty "Category: left identity" $
      QC.forAll QC.arbitrary $ \(xr :: Money.ExchangeRate src dst) ->
         xr === id . xr
  , QC.testProperty "Category: right identity" $
      QC.forAll QC.arbitrary $ \(xr :: Money.ExchangeRate src dst) ->
         xr === xr . id
  , QC.testProperty "Category: composition with inverse" $
      QC.forAll QC.arbitrary $ \(xr1 :: Money.ExchangeRate src dst) ->
         (1 === Money.exchangeRateToRational (xr1 . Money.exchangeRateRecip xr1)) .&&.
         (1 === Money.exchangeRateToRational (Money.exchangeRateRecip xr1 . xr1))
  , QC.testProperty "Category: composition with other" $
      QC.forAll QC.arbitrary $ \(xr1 :: Money.ExchangeRate src dst,
                                 xr2 :: Money.ExchangeRate dst src) ->
         let a = Money.exchangeRateToRational xr1 * Money.exchangeRateToRational xr2
         in (a === Money.exchangeRateToRational (xr1 . xr2)) .&&.
            (a === Money.exchangeRateToRational (xr2 . xr1))

  , QC.testProperty "read . show == id" $
      QC.forAll QC.arbitrary $ \(xr :: Money.ExchangeRate src dst) ->
         xr === read (show xr)
  , QC.testProperty "read . show . Just == Just" $
      QC.forAll QC.arbitrary $ \(xr :: Money.ExchangeRate src dst) ->
         Just xr === read (show (Just xr))
  , QC.testProperty "flipExchangeRate . flipExchangeRate == id" $
      QC.forAll QC.arbitrary $ \(xr :: Money.ExchangeRate src dst) ->
         let xr' = Money.exchangeRateRecip xr
         in (Money.exchangeRateToRational xr /= Money.exchangeRateToRational xr')
               ==> (xr === Money.exchangeRateRecip xr')
  , QC.testProperty "exchange (flipExchangeRate x) . exchange x == id" $
      QC.forAll QC.arbitrary $
         \( c0 :: Money.Dense src
          , xr :: Money.ExchangeRate src dst
          ) -> c0 === Money.exchange (Money.exchangeRateRecip xr)
                                     (Money.exchange xr c0)
  , QC.testProperty "x == 1 ==> exchange x == id" $
      QC.forAll QC.arbitrary $
         \( c0 :: Money.Dense src
          ) -> let Just xr = Money.exchangeRate 1
               in toRational c0 === toRational (Money.exchange xr c0)
  , QC.testProperty "x /= 1 ==> exchange x /= id" $
      QC.forAll QC.arbitrary $
         \( c0 :: Money.Dense src
          , xr :: Money.ExchangeRate src dst
          ) -> (Money.exchangeRateToRational xr /= 1 && toRational c0 /= 0)
                  ==> (toRational c0 /= toRational (Money.exchange xr c0))
  , QC.testProperty "fromSomeExchangeRate . someExchangeRate == Just" $
      QC.forAll QC.arbitrary $ \(x :: Money.ExchangeRate src dst) ->
         Just x === Money.fromSomeExchangeRate (Money.toSomeExchangeRate x)
  , QC.testProperty "fromSomeExchangeRate works only for same currencies" $
      QC.forAll QC.arbitrary $ \(x :: Money.SomeExchangeRate) ->
        ((T.unpack (Money.someExchangeRateSrcCurrency x) /= symbolVal ps) &&
         (T.unpack (Money.someExchangeRateDstCurrency x) /= symbolVal pd))
            ==> isNothing (Money.fromSomeExchangeRate x
                            :: Maybe (Money.ExchangeRate src dst))
  , QC.testProperty "withSomeExchangeRate" $
      QC.forAll QC.arbitrary $ \(x :: Money.ExchangeRate src dst) ->
        let dr = Money.toSomeExchangeRate x
        in Money.withSomeExchangeRate dr $ \x' ->
             (show x, dr) === (show x', Money.toSomeExchangeRate x')

  , QC.testProperty "exchangeRateToDecimal: Same as rationalToDecimal" $
      let gen = (,) <$> genDecimalSeps <*> QC.arbitrary
      in QC.forAll gen $ \( (yst :: Maybe Char, sd :: Char)
                          , (xr :: Money.ExchangeRate src dst, digs :: Word8,
                             aprox :: Money.Approximation ) ) ->
           let xrd = Money.exchangeRateToDecimal aprox yst sd digs xr
               rd = MoneyI.rationalToDecimal aprox False yst sd digs
                       (Money.exchangeRateToRational xr)
           in xrd === rd

  , QC.testProperty "exchangeRateFromDecimal: Same as rationalFromDecimal" $
      QC.forAll genDecimal $ \(dec :: T.Text, yts :: Maybe Char, ds :: Char) ->
         let Just r = MoneyI.rationalFromDecimal yts ds dec
             yxr = Money.exchangeRateFromDecimal yts ds dec
                      :: Maybe (Money.ExchangeRate src dst)
         in (r > 0) ==> (Just r === fmap Money.exchangeRateToRational yxr)

  , QC.testProperty "Binary encoding roundtrip" $
      QC.forAll QC.arbitrary $ \(x :: Money.ExchangeRate src dst) ->
         let Right (_,_,y) = Binary.decodeOrFail (Binary.encode x)
         in x === y
  , QC.testProperty "Binary encoding roundtrip (SomeExchangeRate)" $
      QC.forAll QC.arbitrary $ \(x :: Money.ExchangeRate src dst) ->
         let x' = Money.toSomeExchangeRate x
             bs = Binary.encode x'
         in Right (mempty, BL.length bs, x') === Binary.decodeOrFail bs
  , QC.testProperty "Binary encoding roundtrip (ExchangeRate through SomeExchangeRate)" $
      QC.forAll QC.arbitrary $ \(x :: Money.ExchangeRate src dst) ->
         let x' = Money.toSomeExchangeRate x
             bs = Binary.encode x'
         in Right (mempty, BL.length bs, x) === Binary.decodeOrFail bs
  , QC.testProperty "Binary encoding roundtrip (SomeExchangeRate through ExchangeRate)" $
      QC.forAll QC.arbitrary $ \(x :: Money.ExchangeRate src dst) ->
         let x' = Money.toSomeExchangeRate x
             bs = Binary.encode x
         in Right (mempty, BL.length bs, x') === Binary.decodeOrFail bs
  ]


testDiscreteFromDecimal :: Tasty.TestTree
testDiscreteFromDecimal =
  Tasty.testGroup "discreteFromDecimal"
  [ HU.testCase "Too large" $ do
      Money.discreteFromDecimal Nothing '.' 1 "0.053"
        @?= (Nothing :: Maybe (Money.Discrete "USD" "cent"))
      Money.discreteFromDecimal (Just ',') '.' 1 "0.253"
        @?= (Nothing :: Maybe (Money.Discrete "USD" "cent"))

  , HU.testCase "USD cent, small, zero" $ do
      let dis = 0 :: Money.Discrete "USD" "cent"
          f = Money.discreteFromDecimal
      f Nothing '.' 1 "0" @?= Just dis
      f Nothing '.' 1 "+0" @?= Just dis
      f Nothing '.' 1 "-0" @?= Just dis
      f (Just ',') '.' 1 "0" @?= Just dis
      f (Just ',') '.' 1 "+0" @?= Just dis
      f (Just ',') '.' 1 "-0" @?= Just dis

  , HU.testCase "USD cent, small, positive" $ do
      let dis = 25 :: Money.Discrete "USD" "cent"
          f = Money.discreteFromDecimal
      f Nothing '.' 1 "0.25" @?= Just dis
      f Nothing '.' 1 "+0.25" @?= Just dis
      f (Just ',') '.' 1 "0.25" @?= Just dis
      f (Just ',') '.' 1 "+0.25" @?= Just dis

  , HU.testCase "USD cent, small, negative" $ do
      let dis = -25 :: Money.Discrete "USD" "cent"
          f = Money.discreteFromDecimal
      f Nothing '.' 1 "-0.25" @?= Just dis
      f Nothing '.' 1 "-0.25" @?= Just dis
      f (Just ',') '.' 1 "-0.25" @?= Just dis
      f (Just ',') '.' 1 "-0.25" @?= Just dis

  , HU.testCase "USD cent, big, positive" $ do
      let dis = 102300456789 :: Money.Discrete "USD" "cent"
          f = Money.discreteFromDecimal
      f Nothing '.' 1 "1023004567.89" @?= Just dis
      f Nothing '.' 1 "+1023004567.89" @?= Just dis
      f (Just ',') '.' 1 "1,023,004,567.89" @?= Just dis
      f (Just ',') '.' 1 "+1,023,004,567.89" @?= Just dis

  , HU.testCase "USD cent, big, negative" $ do
      let dis = -102300456789 :: Money.Discrete "USD" "cent"
          f = Money.discreteFromDecimal
      f Nothing '.' 1 "-1023004567.89" @?= Just dis
      f Nothing '.' 1 "-1023004567.89" @?= Just dis
      f (Just ',') '.' 1 "-1,023,004,567.89" @?= Just dis
      f (Just ',') '.' 1 "-1,023,004,567.89" @?= Just dis
  ]

testRounding
  :: forall (currency :: Symbol) (unit :: Symbol)
  .  (Money.GoodScale (Money.Scale currency unit), KnownSymbol currency)
  => Proxy currency
  -> Proxy unit
  -> Tasty.TestTree
testRounding _ _ =
    Tasty.testGroup "Rounding"
    [ QC.testProperty "floor"    $ QC.forAll QC.arbitrary (g (Money.discreteFromDense Money.Floor))
    , QC.testProperty "ceiling"  $ QC.forAll QC.arbitrary (g (Money.discreteFromDense Money.Ceiling))
    , QC.testProperty "round"    $ QC.forAll QC.arbitrary (g (Money.discreteFromDense Money.Round))
    , QC.testProperty "truncate" $ QC.forAll QC.arbitrary (g (Money.discreteFromDense Money.Truncate))
    , QC.testProperty "floor no reminder"    $ QC.forAll QC.arbitrary (h (Money.discreteFromDense Money.Floor))
    , QC.testProperty "ceiling no reminder"  $ QC.forAll QC.arbitrary (h (Money.discreteFromDense Money.Ceiling))
    , QC.testProperty "round no reminder"    $ QC.forAll QC.arbitrary (h (Money.discreteFromDense Money.Round))
    , QC.testProperty "truncate no reminder" $ QC.forAll QC.arbitrary (h (Money.discreteFromDense Money.Truncate))
    ]
  where
    g :: (Money.Dense currency -> (Money.Discrete' currency (Money.Scale currency unit), Money.Dense currency))
      -> Money.Dense currency
      -> QC.Property
    g f = \x -> x === case f x of (y, z) -> Money.denseFromDiscrete y + z

    h :: (Money.Dense currency -> (Money.Discrete' currency (Money.Scale currency unit), Money.Dense currency))
      -> Money.Discrete currency unit
      -> QC.Property
    h f = \x -> (Money.denseFromDiscrete x) === case f (Money.denseFromDiscrete x) of
      (y, 0) -> Money.denseFromDiscrete y
      (_, _) -> error "testRounding.h: unexpected"

--------------------------------------------------------------------------------
-- Raw parsing "golden tests"

testRawSerializations :: Tasty.TestTree
testRawSerializations =
  Tasty.testGroup "Raw serializations"
  [ Tasty.testGroup "binary"
    [ Tasty.testGroup "encode"
      [ HU.testCase "Dense" $ do
          Right rawDns0 @=?
            fmap (\(_,_,a) -> a) (Binary.decodeOrFail rawDns0_binary)
      , HU.testCase "Discrete" $ do
          Right rawDis0 @=?
            fmap (\(_,_,a) -> a) (Binary.decodeOrFail rawDis0_binary)
      , HU.testCase "ExchangeRate" $ do
          Right rawXr0 @=?
            fmap (\(_,_,a) -> a) (Binary.decodeOrFail rawXr0_binary)
      ]
    , Tasty.testGroup "encode"
      [ HU.testCase "Dense" $ rawDns0_binary @=? Binary.encode rawDns0
      , HU.testCase "Discrete" $ rawDis0_binary @=? Binary.encode rawDis0
      , HU.testCase "ExchangeRate" $ rawXr0_binary @=? Binary.encode rawXr0
      ]
    ]
  ]

rawDns0 :: Money.Dense "USD"
rawDns0 = Money.dense' (26%1)

rawDis0 :: Money.Discrete "USD" "cent"
rawDis0 = Money.discrete 4

rawXr0 :: Money.ExchangeRate "USD" "BTC"
Just rawXr0 = Money.exchangeRate (3%2)

-- binary
rawDns0_binary :: BL.ByteString
rawDns0_binary = "\NUL\NUL\NUL\NUL\NUL\NUL\NUL\ETXUSD\NUL\NUL\NUL\NUL\SUB\NUL\NUL\NUL\NUL\SOH"
rawDis0_binary :: BL.ByteString
rawDis0_binary = "\NUL\NUL\NUL\NUL\NUL\NUL\NUL\ETXUSD\NUL\NUL\NUL\NULd\NUL\NUL\NUL\NUL\SOH\NUL\NUL\NUL\NUL\EOT"
rawXr0_binary :: BL.ByteString
rawXr0_binary = "\NUL\NUL\NUL\NUL\NUL\NUL\NUL\ETXUSD\NUL\NUL\NUL\NUL\NUL\NUL\NUL\ETXBTC\NUL\NUL\NUL\NUL\ETX\NUL\NUL\NUL\NUL\STX"

--------------------------------------------------------------------------------
-- Misc

hush :: Either a b -> Maybe b
hush (Left _ ) = Nothing
hush (Right b) = Just b


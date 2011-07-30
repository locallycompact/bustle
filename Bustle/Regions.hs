{-# LANGUAGE DeriveFunctor #-}
module Bustle.Regions
  (
    Stripe(..)
  , nonOverlapping
  , midpoint

  , Regions
  , translateRegions

  , RegionSelection (..)
  , regionSelectionNew
  , regionSelectionUpdate
  , regionSelectionUp
  , regionSelectionDown
  , regionSelectionFirst
  , regionSelectionLast
  )
where

import Data.Maybe (maybeToList)

import Data.List (sort)

data Stripe = Stripe { stripeTop :: Double
                     , stripeBottom :: Double
                     }
  deriving
    (Show, Eq, Ord)
type Region a = (Stripe, a)
type Regions a = [Region a]

translateRegions :: Double
                 -> Regions a
                 -> Regions a
translateRegions y = map (\(s, a) -> (translate s, a))
  where
    translate (Stripe y1 y2) = Stripe (y1 + y) (y2 + y)

-- A zipper for selected regions. rsBefore is reversed. If rsCurrent is
-- Nothing, the two lists may still both be non-empty (to keep track of roughly
-- where the user's last click was).
data RegionSelection a =
    RegionSelection { rsBefore :: Regions a
                    , rsLastClick :: Double
                    , rsCurrent :: Maybe (Region a)
                    , rsAfter :: Regions a
                    }
  deriving
    (Show, Eq, Functor)

relativeTo :: Double
           -> Stripe
           -> Ordering
relativeTo y (Stripe top bottom)
    | y < top    = LT
    | y > bottom = GT
    | otherwise  = EQ

hits :: Double
     -> Stripe
     -> Bool
hits y stripe = y `relativeTo` stripe == EQ

nonOverlapping :: [Stripe]
               -> Bool
nonOverlapping []         = True
nonOverlapping (_:[])     = True
nonOverlapping (s1:s2:ss) =
    stripeBottom s1 <= stripeTop s2 && nonOverlapping (s2:ss)

regionSelectionNew :: Regions a
                   -> RegionSelection a
regionSelectionNew rs
    | sorted /= map fst rs        = error $ "regionSelectionNew: unsorted regions"
    | not (nonOverlapping sorted) = error $ "regionSelectionNew: overlapping regions"
    | otherwise                   = RegionSelection [] 0 Nothing rs
  where
    sorted = sort (map fst rs)

regionSelectionUpdate :: Double
                      -> RegionSelection a
                      -> RegionSelection a
regionSelectionUpdate y rs = rs' { rsLastClick = y }
  where
    rs' = case rsCurrent rs of
              Just r@(s, _)
                  | y `hits` s -> rs
                  | otherwise  -> doSearch (rsBefore rs) (r:rsAfter rs)
              Nothing -> doSearch (rsBefore rs) (rsAfter rs)
    doSearch bs as =
        if y <= rsLastClick rs
          then
            let (as', result, bs') =
                    searchy y (\y' s -> y' <= stripeBottom s) as bs
            in rs { rsBefore  = bs'
                  , rsCurrent = result
                  , rsAfter   = as'
                  }
          else
            let (bs', result, as') =
                    searchy y (\y' s -> y' >= stripeTop s) bs as
            in rs { rsBefore  = bs'
                  , rsCurrent = result
                  , rsAfter   = as'
                  }

invert :: RegionSelection a
       -> RegionSelection a
invert rs = rs { rsBefore = rsAfter rs, rsAfter = rsBefore rs }

midpoint :: Stripe -> Double
midpoint (Stripe top bottom) = (top + bottom) / 2

regionSelectionUp :: RegionSelection a
                  -> RegionSelection a
regionSelectionUp rs@(RegionSelection before lastClick current after) =
    case before of
        []     -> rs
        (b:bs) -> RegionSelection bs
                                  (midpoint (fst b))
                                  (Just b)
                                  (maybeToList current ++ after)

regionSelectionDown :: RegionSelection a
                    -> RegionSelection a
regionSelectionDown = invert . regionSelectionUp . invert

regionSelectionFirst :: RegionSelection a
                     -> RegionSelection a
regionSelectionFirst rs =
    case (reverse (rsBefore rs) ++ maybeToList (rsCurrent rs) ++ rsAfter rs) of
        []             -> rs
        (first:others) -> RegionSelection []
                                          (midpoint (fst first))
                                          (Just first)
                                          others

regionSelectionLast :: RegionSelection a
                    -> RegionSelection a
regionSelectionLast = invert . regionSelectionFirst . invert

searchy :: Double
        -> (Double -> Stripe -> Bool)
        -> Regions a
        -> Regions a
        -> (Regions a, Maybe (Region a), Regions a)
searchy y worthContinuing = go
  where
    go befores [] = (befores, Nothing, [])
    go befores afters@(a:as)
        | y `hits` fst a            = (befores, Just a, as)
        | worthContinuing y (fst a) = go (a:befores) as
        | otherwise                 = (befores, Nothing, afters)

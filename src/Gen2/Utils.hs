{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE QuasiQuotes                #-}
{-# LANGUAGE TemplateHaskell            #-}

module Gen2.Utils where

import           Language.Haskell.TH.Quote
import           Language.Javascript.JMacro

import           Control.Monad.State.Strict
import           Data.Monoid

import           Data.Char                  (isSpace)
import           Data.List                  (isPrefixOf)
import           Data.Map                   (Map, singleton)

-- missing instances, todo: add to jmacro
instance ToJExpr Ident where
  toJExpr i = ValExpr (JVar i)

-- instance ToJExpr JVal where
--   toJExpr v = ValExpr v

-- easier building of javascript object literals
newtype JObj = JObj (Map String JExpr) deriving (Monoid, Show, Eq)

infix 7 .=
(.=) :: (ToJExpr a) => String -> a -> JObj
(.=) key val = JObj $ singleton key (toJExpr val)

instance ToJExpr JObj where
  toJExpr (JObj m) = ValExpr (JHash m)

-- jmacro wrappers for slightly less noisy macros, `c` instead of `(c)`
j  = wrapQuoter replaceBackquotes jmacro
je = wrapQuoter replaceBackquotes jmacroE


replaceBackquotes :: String -> String
replaceBackquotes xs = go False xs
  where
    go _     []       = []
    go False ('`':ys) = "`(" ++ go True  ys
    go True  ('`':ys) = ")`" ++ go False ys
    go b     (y:ys)   = y : go b ys

wrapQuoter :: (String -> String) -> QuasiQuoter -> QuasiQuoter
wrapQuoter f q = QuasiQuoter
                   { quoteExp  = quoteExp  q . f
                   , quotePat  = quotePat  q . f
                   , quoteType = quoteType q . f
                   , quoteDec  = quoteDec  q . f
                   }

insertAt :: Int -> a -> [a] -> [a]
insertAt 0 y xs             = y:xs
insertAt n y (x:xs) | n > 0 = x : insertAt (n-1) y xs
insertAt _ _ _ = error "insertAt"

-- hack for missing unary negation in jmacro
jneg :: JExpr -> JExpr
jneg e = PPostExpr True "-" e

jnull :: JExpr
jnull = ValExpr (JVar $ StrI "null")

jvar :: String -> JExpr
jvar xs = ValExpr (JVar $ StrI xs)

jstr :: String -> JExpr
jstr xs = toJExpr xs

jint :: Integer -> JExpr
jint n = ValExpr (JInt n)

jzero = jint 0

decl :: Ident -> JStat
decl i = DeclStat i Nothing

-- until supported in jmacro
decl' :: Ident -> JExpr -> JStat
decl' i e = decl i `mappend` AssignStat (ValExpr (JVar i)) e

decls :: String -> JStat
decls s = DeclStat (StrI s) Nothing

-- generate an identifier, use it in both statements
identBoth :: (Ident -> JStat) -> (Ident -> JStat) -> JStat
identBoth s1 s2 = UnsatBlock . IS $ do
  i <- newIdent
  return $ s1 i <> s2 i

withIdent :: (Ident -> JStat) -> JStat
withIdent s = UnsatBlock . IS $ newIdent >>= return . s

-- declare a new var and use it in statement
withVar :: (JExpr -> JStat) -> JStat
withVar s = withIdent (\i -> decl i <> s (ValExpr . JVar $ i))

newIdent :: State [Ident] Ident
newIdent = do
  (x:xs) <- get
  put xs
  return x

iex :: Ident -> JExpr
iex i = (ValExpr . JVar) i

istr :: Ident -> String
istr (StrI s) = s

ji :: Int -> JExpr
ji = toJExpr

showIndent x = unlines . runIndent 0 . map trim . lines . replaceParens . show $ x
    where
      replaceParens ('(':xs) = "\n( " ++ replaceParens xs
      replaceParens (')':xs) = "\n)\n" ++ replaceParens xs
      replaceParens (x:xs)   = x : replaceParens xs
      replaceParens []        = []
      indent n xs = replicate n ' ' ++ xs
      runIndent n (x:xs) | "(" `isPrefixOf` x  = indent n     x : runIndent (n+2) xs
                         | ")" `isPrefixOf` x  = indent (n-2) x : runIndent (n-2) xs
                         | all isSpace x    = runIndent n xs
                         | otherwise = indent n x : runIndent n xs
      runIndent n [] = []

trim :: String -> String
trim = let f = dropWhile isSpace . reverse in f . f


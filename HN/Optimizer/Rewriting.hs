{-# LANGUAGE GADTs #-}
module HN.Optimizer.Rewriting (rewriteExpression, ListFact) where

import qualified Data.Foldable as F
import Data.Functor.Fixedpoint
import Data.Maybe
import Control.Applicative
import Compiler.Hoopl
import HN.Optimizer.Node
import HN.Optimizer.Visualise ()
import Utils


type Rewrite a = a -> Maybe a

type ListFact = WithTopAndBot DefinitionNode	

dropR :: Rewrite a -> a -> a
dropR a x = fromMaybe x (a x)

rewriteApplication :: ExpressionFix -> [ExpressionFix] -> FactBase ListFact -> Maybe ExpressionFix

isAtom (Fix (Atom _)) = True
isAtom _ = False  

isAtomApplication (Fix (Application (Fix (Atom _)) _)) = True
isAtomApplication _ = False

rewriteApplication (Fix (Application a b)) c f = case processAtom2 "rewriteApplication.Double.1" a f of 
	Nothing -> Nothing
	Just ([], _) -> error "rewriteApplication.double.var"
	Just (outerParams, Fix (Atom aOuterBody)) -> case processAtom2 "rewriteApplication.Double.2" (Fix $ Atom aOuterBody) f of
		Just (innerParams, innerBody) -> fmap ff $ inlineApplication innerParams c f innerBody where
			ff (Fix (Application aa bb)) = Fix $ Application (dropR (inlineApplication outerParams b f) aa) bb  
			ff _ = error "rewriteApplication.double.fn.Just.noApp"				
		_ -> error "rewriteApplication.double.fn.Nothing"

inlineApplication formalArgs actualArgs f 
	= Just . dropR (rewriteExpression2 $ flip mapUnion f $ mapFromList $ zip formalArgs $ map (PElem . LetNode []) actualArgs) 

rewriteExpression :: FactBase ListFact -> Rewrite (ExpressionFix)
rewriteExpression = rewriteMany . rewriteExpression2 
	
rewriteExpression2 :: FactBase ListFact -> Rewrite (ExpressionFix)
rewriteExpression2 = process2 . phi2
	
phi :: FactBase ListFact -> (ExpressionFunctor (ExpressionFix, Maybe ExpressionFix) -> Maybe ExpressionFix)
phi f (Constant _) = Nothing
phi f a @ (Atom _) = do 
	([], e) <- processAtom "rewriteExpression2" a $ xtrace ("factBase-atom {" ++ show a ++ "}") f
	return e
phi f expr @ (Application (a, _) bb) | isAtom (a) = let
	b' = map (uncurry fromMaybe) bb
	in case processAtom2 "rewriteApplication.Single" a f of
		Nothing -> foo expr
		Just ([], expr) -> Just $ Fix $ Application expr b' 
		Just (args, expr) -> inlineApplication args b' f expr
phi f (Application (a, _) bb) | isAtomApplication (a) = rewriteApplication a (map fst bb) f
phi f expr @ (Application _ _) = foo expr


phi2 :: FactBase ListFact -> (ExpressionFunctor ExpressionFix -> Maybe (Fix ExpressionFunctor))
phi2 f (Constant _) = Nothing
phi2 f a @ (Atom _) = do 
	([], e) <- processAtom "rewriteExpression2" a $ xtrace ("factBase-atom {" ++ show a ++ "}") f
	return e
phi2 f expr @ (Application a b') | isAtom (a) = case processAtom2 "rewriteApplication.Single" a f of
	Nothing -> Nothing
	Just ([], expr) -> Just $ Fix $ Application expr b' 
	Just (args, expr) -> inlineApplication args b' f expr
phi2 f (Application a bb) | isAtomApplication (a) = rewriteApplication a bb f
phi2 f (Application a bb) = Nothing 
 
		
foo (Application (a, _) bb) = if bChanged then Just $ Fix $ Application a b' else Nothing where
	b' = map (uncurry fromMaybe) bb 
	bChanged = any (isJust . snd) bb

processAtom err (Atom a) f = case lookupFact a f of
	Nothing -> error $ err ++ ".uncondLookupFact.Nothing"
 	Just Bot -> error $ err ++ ".rewriteExitL.Bot"
 	Just (PElem (LetNode args body)) -> Just (args, body)
	_ -> Nothing


processAtom2 err a f = processAtom err (unFix a) f 

process3 :: (Fix ExpressionFunctor -> c -> b) -> (ExpressionFunctor b -> c) -> Fix ExpressionFunctor -> c
process3 j f = self
	where self = f . fmap (\x -> j x (self x)) . unFix
	
process :: (ExpressionFunctor (ExpressionFix, Maybe ExpressionFix) -> Maybe ExpressionFix) -> Rewrite ExpressionFix
process = process3 (,)

process2 :: (ExpressionFunctor ExpressionFix -> Maybe (Fix ExpressionFunctor)) -> Rewrite ExpressionFix
process2 f = process ff where
	ff x = let
 		isChanged = F.any (isJust . snd) x
		x' :: ExpressionFunctor ExpressionFix
		x' = uncurry fromMaybe <$> x
		in case f x' of
 			Nothing -> if isChanged then Just $ Fix x' else Nothing
			x -> x
	
rewriteMany :: Rewrite a -> Rewrite a
rewriteMany clientRewrite x = clientRewrite x >>= rewriteAfterChange where
	rewriteAfterChange x = (clientRewrite x >>= rewriteAfterChange) <|> return x

module Handler.Events where

import           Data.Aeson
import qualified Data.Text           as T  (pack, splitOn)
import qualified Data.Text.Read      as T  (decimal)
import           Handler.Event
import           Import


addPager :: ( PersistEntity val
            , PersistEntityBackend val ~ YesodPersistBackend m
            , PersistQuery (YesodPersistBackend m)
            , Yesod m
            )
         => Int
         -> [ SelectOpt val ]
         -> HandlerT m IO [ SelectOpt val ]
addPager resultsPerPage selectOpt  = do
  mpage <- lookupGetParam "page"
  let pageNumber = case (T.decimal $ fromMaybe "0" mpage) of
                      Left _ -> 0
                      Right (val, _) -> val
  let pagerOpt = [ LimitTo resultsPerPage
                 , OffsetBy $ (pageNumber - 1) * resultsPerPage
                 ]
  return $ selectOpt `mappend` pagerOpt


-- @todo: Generalize not to be only for Event
addOrder :: ( PersistQuery (YesodPersistBackend m)
            , Yesod m
            )
         => [SelectOpt Event]
         -> HandlerT m IO [ SelectOpt Event ]
addOrder selectOpt = do
  morder <- lookupGetParam "order"

  let order = case morder of
                  Nothing -> [ Desc EventId ]
                  Just vals -> orderText2SelectOpt $ T.splitOn "," vals

  return $ selectOpt `mappend` order

addListMetaData :: KeyValue t
                => [t]
                -> HandlerT App IO ([t])
addListMetaData json = do
  mpage <- lookupGetParam "page"
  let pageNumber = case (T.decimal $ fromMaybe "0" mpage) of
                      Left _ -> 1 :: Integer
                      Right (val, _) -> (val :: Integer) + 1

  render <- getUrlRender
  let metaData =
        [ "_links" .= object
            [ "self" .= render EventsR
            -- , "page" .= Number pageNumber
            ]
        ]
  return $ json `mappend` metaData


orderText2SelectOpt :: [Text] -> [SelectOpt Event]
orderText2SelectOpt []              = []
orderText2SelectOpt ("id" : xs)     = [ Asc EventId] ++ (orderText2SelectOpt xs)
orderText2SelectOpt ("-id" : xs)    = [ Desc EventId] ++ (orderText2SelectOpt xs)
orderText2SelectOpt ("title" : xs)  = [ Asc EventTitle] ++ (orderText2SelectOpt xs)
orderText2SelectOpt ("-title" : xs) = [ Desc EventTitle] ++ (orderText2SelectOpt xs)
orderText2SelectOpt (_ : xs)        = [] ++ (orderText2SelectOpt xs)

getEventsR :: Handler Value
getEventsR = do
    selectOpt <- (addPager 2) [] >>= addOrder
    events <- runDB $ selectList [] selectOpt :: Handler [Entity Event]

    eventsWithMetaData <- addListMetaData ["data" .= events]
    return $ object eventsWithMetaData

postEventsR :: Handler Value
postEventsR = do
    event <- requireJsonBody :: Handler Event
    eid <- runDB $ insert event

    returnVal <- getEventR eid

    sendResponseStatus status201 returnVal

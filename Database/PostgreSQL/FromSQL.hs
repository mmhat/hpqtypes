{-# OPTIONS_GHC -Wall #-}
{-# LANGUAGE BangPatterns, FlexibleContexts, FlexibleInstances
  , FunctionalDependencies, RecordWildCards, ScopedTypeVariables
  , UndecidableInstances #-}
module Database.PostgreSQL.FromSQL {-(FromSQL(..))-} where

import Control.Applicative
import Data.Int
import Data.Ratio
import Data.Text (Text)
import Data.Text.Encoding
import Data.Time
import Foreign.C
import Foreign.Marshal.Alloc
import Foreign.Storable
import qualified Control.Exception as E
import qualified Data.ByteString.Char8 as BS

import Database.PostgreSQL.Internal.C.Get
import Database.PostgreSQL.Internal.C.Interface
import Database.PostgreSQL.Internal.C.Types
import Database.PostgreSQL.Internal.Error
import Database.PostgreSQL.Types

unexpectedNullValue :: IO a
unexpectedNullValue = E.throwIO . InternalError $ "unexpected NULL value"

----------------------------------------

class Storable base => FromSQL base dest | dest -> base where
  pqFormatGet :: dest -> BS.ByteString
  fromSQL     :: Maybe base -> IO dest

-- NULLables

instance FromSQL base dest => FromSQL base (Maybe dest) where
  pqFormatGet _ = pqFormatGet (undefined::dest)
  fromSQL mbase = case mbase of
    Just _  -> Just <$> fromSQL mbase
    Nothing -> return Nothing

-- NUMERICS

instance FromSQL CShort Int16 where
  pqFormatGet _ = BS.pack "%int2"
  fromSQL Nothing = unexpectedNullValue
  fromSQL (Just n) = return . fromIntegral $ n

instance FromSQL CInt Int32 where
  pqFormatGet _ = BS.pack "%int4"
  fromSQL Nothing = unexpectedNullValue
  fromSQL (Just n) = return . fromIntegral $ n

instance FromSQL CLLong Int64 where
  pqFormatGet _ = BS.pack "%int8"
  fromSQL Nothing = unexpectedNullValue
  fromSQL (Just n) = return . fromIntegral $ n

instance FromSQL CFloat Float where
  pqFormatGet _ = BS.pack "%float4"
  fromSQL Nothing = unexpectedNullValue
  fromSQL (Just n) = return . realToFrac $ n

instance FromSQL CDouble Double where
  pqFormatGet _ = BS.pack "%float8"
  fromSQL Nothing = unexpectedNullValue
  fromSQL (Just n) = return . realToFrac $ n

-- ARRAYS

instance FromSQL base dest => FromSQL PGarray (Array dest) where
  pqFormatGet _ = pqFormatGet (undefined::dest) `BS.append` BS.pack "[]"
  fromSQL Nothing = unexpectedNullValue
  fromSQL (Just PGarray{..}) = flip E.finally (c_PQclear pgArrayRes) $ if pgArrayNDims > 1
    then E.throwIO . InternalError $ "Array type supports 1-dimensional arrays only, given array is " ++ show pgArrayNDims ++ "-dimensional"
    else do
      let fmt = pqFormatGet (undefined::dest)
      size <- c_PQntuples pgArrayRes
      BS.useAsCString fmt (loop [] $ size - 1)
    where
      loop acc (-1) _ = return . Array $ acc
      loop acc !i fmt = alloca $ \ptr -> do
        success <- c_PQgetf1 pgArrayRes i fmt 0 ptr
        if success == 0
          then throwLibPQTypesError "fromSQL (Array)"
          else do
            isNull <- c_PQgetisnull pgArrayRes i 0
            mbase  <- if isNull == 1 then return Nothing else Just <$> peek ptr
            item   <- fromSQL mbase `E.catch` addArrayInfo i
            loop (item : acc) (i-1) fmt

      addArrayInfo :: CInt -> E.SomeException -> IO a
      addArrayInfo i (E.SomeException e) =
        E.throwIO ArrayItemError {
          arrItemIndex = fromIntegral i + 1
        , arrItemError = e
        }

-- TIMESTAMP

instance FromSQL PGtimestamp LocalTime where
  pqFormatGet _ = BS.pack "%timestamp"
  fromSQL Nothing = unexpectedNullValue
  fromSQL (Just PGtimestamp{..}) = return $ LocalTime day tod
    where
      day = fromGregorian year mon mday
      tod = TimeOfDay hour mins $ sec + fromRational (usec % 1000000)

      year = fromIntegral $ pgDateYear pgTimestampDate
      mon  = fromIntegral $ pgDateMon pgTimestampDate + 1
      mday = fromIntegral $ pgDateMDay pgTimestampDate
      hour = fromIntegral $ pgTimeHour pgTimestampTime
      mins = fromIntegral $ pgTimeMin pgTimestampTime
      sec  = fromIntegral $ pgTimeSec pgTimestampTime
      usec = fromIntegral $ pgTimeUSec pgTimestampTime

-- TIMESTAMPTZ

localToZoned :: (TimeZone -> LocalTime -> a) -> Maybe PGtimestamp -> IO a
localToZoned _ Nothing = unexpectedNullValue
localToZoned construct jts@(Just PGtimestamp{..}) = do
  localTime <- fromSQL jts
  case rest of
    0 -> return . construct (minutesToTimeZone mins) $ localTime
    _ -> E.throwIO . InternalError $ "Invalid gmtoff: " ++ show gmtoff
  where
    gmtoff = pgTimeGMTOff pgTimestampTime
    (mins, rest) = fromIntegral gmtoff `divMod` 60

instance FromSQL PGtimestamp UTCTime where
  pqFormatGet _ = BS.pack "%timestamptz"
  fromSQL = localToZoned localTimeToUTC

instance FromSQL PGtimestamp ZonedTime where
  pqFormatGet _ = BS.pack "%timestamptz"
  fromSQL = localToZoned (flip ZonedTime)

-- VARIABLE-LENGTH CHARACTER TYPES

instance FromSQL CString String where
  pqFormatGet _ = BS.pack "%text"
  fromSQL Nothing = unexpectedNullValue
  fromSQL (Just cs) = peekCString cs

instance FromSQL CString BS.ByteString where
  pqFormatGet _ = BS.pack "%text"
  fromSQL Nothing = unexpectedNullValue
  fromSQL (Just cs) = BS.packCString cs

instance FromSQL CString Text where
  pqFormatGet _ = BS.pack "%text"
  fromSQL Nothing = unexpectedNullValue
  fromSQL (Just cs) = either E.throwIO return . decodeUtf8' =<< BS.packCString cs
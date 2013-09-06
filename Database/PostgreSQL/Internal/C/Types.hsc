{-# OPTIONS_GHC -Wall #-}
{-# LANGUAGE EmptyDataDecls, RecordWildCards, ScopedTypeVariables #-}
module Database.PostgreSQL.Internal.C.Types where

import Control.Applicative
import Data.ByteString.Unsafe
import Data.Int
import Foreign.C
import Foreign.Marshal.Array
import Foreign.Ptr
import Foreign.Storable
import qualified Data.Vector.Unboxed as V
import qualified Data.ByteString as BS

#let alignment t = "%lu", (unsigned long)offsetof(struct {char x__; t (y__);}, y__)

data PGconn
data PGparam
data PGresult
data PGtypeArgs

#include <libpqtypes.h>
#include <postgresql/libpq-fe.h>

newtype ConnStatusType = ConnStatusType CInt
  deriving Eq

#{enum ConnStatusType, ConnStatusType
, c_CONNECTION_OK = CONNECTION_OK
, c_CONNECTION_BAD = CONNECTION_BAD
, c_CONNECTION_STARTED = CONNECTION_STARTED
, c_CONNECTION_MADE = CONNECTION_MADE
, c_CONNECTION_AWAITING_RESPONSE = CONNECTION_AWAITING_RESPONSE
, c_CONNECTION_AUTH_OK = CONNECTION_AUTH_OK
, c_CONNECTION_SETENV = CONNECTION_SETENV
, c_CONNECTION_SSL_STARTUP = CONNECTION_SSL_STARTUP
, c_CONNECTION_NEEDED = CONNECTION_NEEDED
}

newtype ExecStatusType = ExecStatusType CInt
  deriving Eq

#{enum ExecStatusType, ExecStatusType
, c_PGRES_EMPTY_QUERY = PGRES_EMPTY_QUERY
, c_PGRES_COMMAND_OK = PGRES_COMMAND_OK
, c_PGRES_TUPLES_OK = PGRES_TUPLES_OK
, c_PGRES_COPY_OUT = PGRES_COPY_OUT
, c_PGRES_COPY_IN = PGRES_COPY_IN
, c_PGRES_BAD_RESPONSE = PGRES_BAD_RESPONSE
, c_PGRES_NONFATAL_ERROR = PGRES_NONFATAL_ERROR
, c_PGRES_FATAL_ERROR = PGRES_FATAL_ERROR
, c_PGRES_COPY_BOTH = PGRES_COPY_BOTH
}

newtype TypeClass = TypeClass CInt
  deriving Eq

#{enum TypeClass, TypeClass
, c_PQT_SUBCLASS = PQT_SUBCLASS
, c_PQT_COMPOSITE = PQT_COMPOSITE
, c_PQT_USERDEFINED = PQT_USERDEFINED
}

data PGregisterType = PGregisterType {
  pgRegisterTypeTypName :: CString
, pgRegisterTypeTypPut  :: FunPtr (Ptr PGtypeArgs -> IO CInt)
, pgRegisterTypeTypGet  :: FunPtr (Ptr PGtypeArgs -> IO CInt)
} deriving Show

instance Storable PGregisterType where
  sizeOf _ = #{size PGregisterType}
  alignment _ = #{alignment PGregisterType}
  peek ptr = PGregisterType
    <$> #{peek PGregisterType, typname} ptr
    <*> #{peek PGregisterType, typput} ptr
    <*> #{peek PGregisterType, typget} ptr
  poke ptr PGregisterType{..} = do
    #{poke PGregisterType, typname} ptr pgRegisterTypeTypName
    #{poke PGregisterType, typput} ptr pgRegisterTypeTypPut
    #{poke PGregisterType, typget} ptr pgRegisterTypeTypGet

c_MAXDIM :: Int
c_MAXDIM = #{const MAXDIM}

data PGarray = PGarray {
  pgArrayNDims  :: {-# UNPACK #-} !CInt
, pgArrayLBound ::                !(V.Vector Int32)
, pgArrayDims   ::                !(V.Vector Int32)
, pgArrayParam  :: {-# UNPACK #-} !(Ptr PGparam)
, pgArrayRes    :: {-# UNPACK #-} !(Ptr PGresult)
} deriving Show

instance Storable PGarray where
  sizeOf _ = #{size PGarray}
  alignment _ = #{alignment PGarray}
  peek ptr = PGarray
    <$> #{peek PGarray, ndims} ptr
    <*> V.mapM (readElem $ #{ptr PGarray, lbound} ptr) indexVec
    <*> V.mapM (readElem $ #{ptr PGarray, dims} ptr) indexVec
    <*> #{peek PGarray, param} ptr
    <*> #{peek PGarray, res} ptr
    where
      indexVec :: V.Vector Int
      indexVec = V.enumFromN (0::Int) c_MAXDIM

      readElem :: Ptr CInt -> Int -> IO Int32
      readElem p i = fromIntegral <$> peekElemOff p i

  poke ptr PGarray{..} = do
    #{poke PGarray, ndims} ptr pgArrayNDims
    V.mapM_ (writeElem $ #{ptr PGarray, lbound} ptr) $ adapt pgArrayLBound
    V.mapM_ (writeElem $ #{ptr PGarray, dims} ptr) $ adapt pgArrayDims
    #{poke PGarray, param} ptr pgArrayParam
    #{poke PGarray, res} ptr pgArrayRes
    where
      writeElem :: Ptr CInt -> (Int, Int32) -> IO ()
      writeElem p (i, n) = pokeElemOff p i (fromIntegral n)

      adapt :: V.Vector Int32 -> V.Vector (Int, Int32)
      adapt v = V.indexed $ case V.length v of
       len | len >= c_MAXDIM -> V.take c_MAXDIM v
           | otherwise -> v V.++ V.replicate (c_MAXDIM - len) 0

data PGdate = PGdate {
  pgDateIsBC :: {-# UNPACK #-} !CInt
, pgDateYear :: {-# UNPACK #-} !CInt
, pgDateMon  :: {-# UNPACK #-} !CInt
, pgDateMDay :: {-# UNPACK #-} !CInt
, pgDateJDay :: {-# UNPACK #-} !CInt
, pgDateYDay :: {-# UNPACK #-} !CInt
, pgDateWDay :: {-# UNPACK #-} !CInt
} deriving Show

instance Storable PGdate where
  sizeOf _ = #{size PGdate}
  alignment _ = #{alignment PGdate}
  peek ptr = PGdate
    <$> #{peek PGdate, isbc} ptr
    <*> #{peek PGdate, year} ptr
    <*> #{peek PGdate, mon}  ptr
    <*> #{peek PGdate, mday} ptr
    <*> #{peek PGdate, jday} ptr
    <*> #{peek PGdate, yday} ptr
    <*> #{peek PGdate, wday} ptr
  poke ptr PGdate{..} = do
    #{poke PGdate, isbc} ptr pgDateIsBC
    #{poke PGdate, year} ptr pgDateYear
    #{poke PGdate, mon}  ptr pgDateMon
    #{poke PGdate, mday} ptr pgDateMDay
    #{poke PGdate, jday} ptr pgDateJDay
    #{poke PGdate, yday} ptr pgDateYDay
    #{poke PGdate, wday} ptr pgDateWDay

data PGtime = PGtime {
  pgTimeHour   :: {-# UNPACK #-} !CInt
, pgTimeMin    :: {-# UNPACK #-} !CInt
, pgTimeSec    :: {-# UNPACK #-} !CInt
, pgTimeUSec   :: {-# UNPACK #-} !CInt
, pgTimeWithTZ :: {-# UNPACK #-} !CInt
, pgTimeIsDST  :: {-# UNPACK #-} !CInt
, pgTimeGMTOff :: {-# UNPACK #-} !CInt
, pgTimeTZAbbr :: {-# UNPACK #-} !BS.ByteString
} deriving Show

instance Storable PGtime where
  sizeOf _ = #{size PGtime}
  alignment _ = #{alignment PGtime}
  peek ptr = PGtime
    <$> #{peek PGtime, hour}   ptr
    <*> #{peek PGtime, min}    ptr
    <*> #{peek PGtime, sec}    ptr
    <*> #{peek PGtime, usec}   ptr
    <*> #{peek PGtime, withtz} ptr
    <*> #{peek PGtime, isdst}  ptr
    <*> #{peek PGtime, gmtoff} ptr
    <*> BS.packCString (#{ptr PGtime, tzabbr} ptr)
  poke ptr PGtime{..} = do
    #{poke PGtime, hour}   ptr pgTimeHour
    #{poke PGtime, min}    ptr pgTimeMin
    #{poke PGtime, sec}    ptr pgTimeSec
    #{poke PGtime, usec}   ptr pgTimeUSec
    #{poke PGtime, withtz} ptr pgTimeWithTZ
    #{poke PGtime, isdst}  ptr pgTimeIsDST
    #{poke PGtime, gmtoff} ptr pgTimeGMTOff
    unsafeUseAsCStringLen pgTimeTZAbbr $ \(cs, len) -> do
      let tzabbr = #{ptr PGtime, tzabbr} ptr
      copyArray tzabbr cs (min len 16)
      pokeElemOff tzabbr (min len 15) (0::CChar)

data PGtimestamp = PGtimestamp {
  pgTimestampEpoch :: {-# UNPACK #-} !CLLong
, pgTimestampDate  :: {-# UNPACK #-} !PGdate
, pgTimestampTime  :: {-# UNPACK #-} !PGtime
} deriving Show

instance Storable PGtimestamp where
  sizeOf _ = #{size PGtimestamp}
  alignment _ = #{alignment PGtimestamp}
  peek ptr = PGtimestamp
    <$> #{peek PGtimestamp, epoch} ptr
    <*> #{peek PGtimestamp, date}  ptr
    <*> #{peek PGtimestamp, time}  ptr
  poke ptr PGtimestamp{..} = do
    #{poke PGtimestamp, epoch} ptr pgTimestampEpoch
    #{poke PGtimestamp, date}  ptr pgTimestampDate
    #{poke PGtimestamp, time}  ptr pgTimestampTime
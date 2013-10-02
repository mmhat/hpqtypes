{-# OPTIONS_GHC -Wall #-}
module Database.PostgreSQL.PQTypes.Internal.State (
    TransactionSettings(..)
  , IsolationLevel(..)
  , Permissions(..)
  , QueryResult(..)
  , DBState(..)
  ) where

import Foreign.ForeignPtr

import Database.PostgreSQL.PQTypes.Internal.C.Types
import Database.PostgreSQL.PQTypes.Internal.Connection
import Database.PostgreSQL.PQTypes.SQL.Class

data TransactionSettings = TransactionSettings {
  tsAutoTransaction :: !Bool
, tsIsolationLevel  :: !IsolationLevel
, tsPermissions     :: !Permissions
}

data IsolationLevel = DefaultLevel | ReadCommitted | RepeatableRead | Serializable
data Permissions = DefaultPermissions | ReadOnly | ReadWrite

newtype QueryResult = QueryResult { unQueryResult :: ForeignPtr PGresult }

----------------------------------------

data DBState = DBState {
  dbConnection          :: !Connection
, dbConnectionSource    :: !ConnectionSource
, dbTransactionSettings :: !TransactionSettings
, dbLastQuery           :: !SomeSQL
, dbQueryResult         :: !(Maybe QueryResult)
}

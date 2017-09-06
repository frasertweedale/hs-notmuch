-- This file is part of hs-notmuch - Haskell Notmuch binding
-- Copyright (C) 2014, 2017  Fraser Tweedale
--
-- hs-notmuch is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.

{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}

{-|

High-level interface to the /notmuch/ mail indexer.

Some functions that operate on 'Message' objects cause a file
descriptor to be opened (indicated below).  The file descriptor is
automatically closed when the data gets GC'd but when the RTS is
using a multi-generation collector (the default) it becomes more
likely to hit /max open files/ limits.  Approaches to avoid this
scenario include:

- Avoid using these functions; if you need to open the mail file,
  open it from Haskell, do the thing, then close it promptly.

- Use a single-generation collector (build with @-rtsopts@ and run
  with @+RTS -G1@).  This incurs the cost of scanning the entire
  heap on every GC run.

- In an interactive program, build with @-threaded@ to enable
  parallel GC.  By default, major GC will be triggered when the
  program is idle for a certain time.

- Manually execute 'System.Mem.performMajorGC' at appropriate times
  to ensure that older generations get cleaned up.

The functions that may open file descriptors are:

- 'messageHeader'

-}
module Notmuch
  (
    Tag
  , mkTag
  , getTag
  , MessageId
  , ThreadId

  , Database
  , RO
  , RW
  , databaseOpen
  , databaseOpenReadOnly
  , databaseDestroy
  , databaseVersion
  , findMessage

  , Query
  , query
  , queryCountMessages
  , queryCountThreads

  , Thread

  , Message
  , messageId
  , messageDate
  , messageHeader
  , messageFilename
  , messageSetTags

  , HasTags(..)
  , HasMessages(..)
  , HasThreads(..)
  , HasThread(..)

  , Status(..)
  ) where

import Control.Exception (bracket)
import Control.Monad.Except (MonadError(..))
import Control.Monad.IO.Class (MonadIO(..))
import Data.Foldable (traverse_)

import qualified Data.ByteString as B
import Data.Time (UTCTime)
import Data.Time.Clock.POSIX (posixSecondsToUTCTime)

import Notmuch.Binding
import Notmuch.Search

--
-- PUBLIC API
--

--
-- Classes
--

class HasTags a where
  tags :: MonadIO m => a -> m [Tag]

instance HasTags (Database a) where
  tags = liftIO . database_get_all_tags

instance HasTags (Thread a) where
  tags = liftIO . thread_get_tags

instance HasTags Messages where
  tags = liftIO . messages_collect_tags

instance HasTags (Message n a) where
  tags = liftIO . message_get_tags


class HasMessages a where
  messages :: (MonadError Status m, MonadIO m) => a mode -> m [Message 0 mode]

instance HasMessages Query where
  messages = query_search_messages

instance HasMessages Thread where
  messages = thread_get_messages

instance HasMessages (Message n) where
  messages = message_get_replies
  -- replies!


class HasThreads a where
  threads :: MonadIO m => a mode -> m [Thread mode]


class HasThread a where
  threadId :: MonadIO m => a -> m ThreadId

instance HasThread (Thread a) where
  threadId = liftIO . thread_get_thread_id

instance HasThread (Message n a) where
  threadId = liftIO . message_get_thread_id


databaseOpen
  :: (Mode a, MonadError Status m, MonadIO m)
  => FilePath -> m (Database a)
databaseOpen = database_open

-- | Convenience function for opening a database read-only
databaseOpenReadOnly
  :: (MonadError Status m, MonadIO m)
   => FilePath -> m (Database RO)
databaseOpenReadOnly = database_open

-- | Close the database and free associated resources
--
-- Don't use any resources derived from this database
-- after using this function!
--
databaseDestroy :: (MonadError Status m, MonadIO m) => Database a -> m ()
databaseDestroy = database_destroy

databaseVersion :: MonadIO m => Database a -> m Int
databaseVersion = liftIO . database_get_version

findMessage
  :: (MonadError Status m, MonadIO m)
  => Database a -> MessageId -> m (Maybe (Message 0 a))
findMessage = database_find_message

query :: (MonadIO m) => Database a -> SearchTerm -> m (Query a)
query db = liftIO . query_create db . show

queryCountMessages, queryCountThreads
  :: (MonadError Status m, MonadIO m) => Query a -> m Int
queryCountMessages = query_count_messages
queryCountThreads = query_count_threads

messageId :: MonadIO m => Message n a -> m MessageId
messageId = liftIO . message_get_message_id

messageDate :: MonadIO m => Message n a -> m (UTCTime)
messageDate = liftIO . fmap (posixSecondsToUTCTime . realToFrac) . message_get_date

-- | Get the named header as a UTF-8 encoded string.
-- Empty string if header is missing or @Nothing@ on error.
--
-- /May open a file descriptor./
--
messageHeader :: MonadIO m => B.ByteString -> Message n a -> m (Maybe B.ByteString)
messageHeader k = liftIO . flip message_get_header k

messageFilename :: MonadIO m => Message n a -> m FilePath
messageFilename = liftIO . message_get_filename

-- | Freeze the message, run the given computation
-- and return the result.  The message is always thawed at the end.
-- (Don't thaw the message as part of the computation!)
--
-- Have to start with @Message 0 RW@ due to GHC type system limitation
-- (type-level Nat is not inductive).
--
withFrozenMessage :: (Message 1 RW -> IO a) -> Message 0 RW -> IO a
withFrozenMessage k msg = bracket (message_freeze msg) message_thaw k

-- | Set tags for the message.  Atomic.
--
messageSetTags :: MonadIO m => Foldable t => t Tag -> Message 0 RW -> m ()
messageSetTags l = liftIO . withFrozenMessage (\msg ->
  message_remove_all_tags msg *> traverse_ (message_add_tag msg) l)

-- Copyright (C) 2017  Fraser Tweedale
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

module Notmuch.Binding.Constants
  (
    libnotmuchVersion
  , tagMaxLen
  ) where

import Data.Version (Version, makeVersion)

#include <notmuch.h>

-- | The maximum tag length.  Defined as @NOTMUCH_TAG_MAX@ in @notmuch.h@.
tagMaxLen :: Int
tagMaxLen = {#const NOTMUCH_TAG_MAX #}

-- | The version of /libnotmuch/ that /hs-notmuch/ was __built__ against.
-- (The program could be running against a different version.)
libnotmuchVersion :: Version
libnotmuchVersion = makeVersion
  [ {#const LIBNOTMUCH_MAJOR_VERSION #}
  , {#const LIBNOTMUCH_MINOR_VERSION #}
  , {#const LIBNOTMUCH_MICRO_VERSION #}
  ]

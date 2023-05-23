# encoding: ascii-8bit

# Copyright 2022 OpenC3, Inc.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3'
require 'openc3/utilities/bucket_utilities'

OpenC3.disable_warnings do
  def require(*args, **kw_args)
    begin
      return super(*args, **kw_args)
    rescue LoadError
      begin
        @bucket_require_cache ||= {}
        if @bucket_require_cache[args[0]]
          return false
        else
          scope = nil
          if kw_args[:scope]
            scope = kw_args[:scope]
          else
            scope = $openc3_scope
          end
          OpenC3::BucketUtilities.bucket_load(*args, scope: scope)
          @bucket_require_cache[args[0]] = true
          return true
        end
      rescue Exception => err
        raise LoadError, "#{err.class}:#{err.message}", err.backtrace
      end
    end
  end

  def load(*args, **kw_args)
    begin
      super(*args, **kw_args)
    rescue LoadError
      begin
        scope = nil
        if kw_args[:scope]
          scope = kw_args[:scope]
        else
          scope = $openc3_scope
        end
        OpenC3::BucketUtilities.bucket_load(*args, scope: scope)
      rescue Exception
        raise LoadError, "#{err.class}:#{err.message}", err.backtrace
      end
    end
  end
end
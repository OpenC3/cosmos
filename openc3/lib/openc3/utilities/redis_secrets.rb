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

require 'openc3/models/secret_model'
require 'openc3/utilities/secrets'

module OpenC3
  class RedisSecrets < Secrets
    def keys(secret_store: nil, scope:)
      SecretModel.names(scope: scope)
    end

    def get(key, secret_store: nil, scope:)
      data = SecretModel.get(name: key, scope: scope)
      if data
        return data['value']
      else
        return nil
      end
    end

    def set(key, value, secret_store: nil, scope:)
      SecretModel.set( {name: key, value: value.to_s }, scope: scope)
    end

    def delete(key, secret_store: nil, scope:)
      model = SecretModel.get_model(name: key, scope: scope)
      model.destroy if model
    end
  end
end

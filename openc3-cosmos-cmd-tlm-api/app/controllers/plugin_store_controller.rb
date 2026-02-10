# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/models/plugin_store_model'

class PluginStoreController < ApplicationController
  before_action :ensure_exists

  def index
    render json: OpenC3::PluginStoreModel.all()
  end

  private
  def ensure_exists
    OpenC3::PluginStoreModel.ensure_exists()
  end
end

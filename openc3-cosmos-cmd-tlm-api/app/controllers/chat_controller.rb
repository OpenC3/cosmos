# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

begin
  require 'openc3-enterprise/controllers/chat_controller'
rescue LoadError
  class ChatController < ApplicationController
    def stream
      render json: { status: 'error', message: 'AI chat is only available in COSMOS Enterprise' }, status: :not_implemented
    end

    def config_show
      render json: { status: 'error', message: 'AI chat is only available in COSMOS Enterprise' }, status: :not_implemented
    end

    def config_update
      render json: { status: 'error', message: 'AI chat is only available in COSMOS Enterprise' }, status: :not_implemented
    end
  end
end

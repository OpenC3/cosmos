# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
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

# Modified by OpenC3, Inc.
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved

require 'openc3'
require 'openc3/models/auth_model'

class AuthController < ApplicationController
  def token_exists
    result = OpenC3::AuthModel.is_set?
    render :json => {
      result: result
    }
  end

  def verify
    begin
      if OpenC3::AuthModel.verify(params[:token])
        head :ok
      else
        head :unauthorized
      end
    rescue StandardError => e
      render :json => { :status => 'error', :message => e.message, 'type' => e.class }, :status => 500
    end
  end

  def set
    begin
      # Set throws an exception if it fails for any reason
      OpenC3::AuthModel.set(params[:token], params[:old_token])
      OpenC3::Logger.info("Password changed", user: user_info(request.headers['HTTP_AUTHORIZATION']))
      head :ok
    rescue StandardError => e
      render :json => { :status => 'error', :message => e.message, 'type' => e.class }, :status => 500
    end
  end
end

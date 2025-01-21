# encoding: utf-8

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
# All changes Copyright 2024, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/utilities/authorization'

class ApplicationController < ActionController::API
  include OpenC3::Authorization

  private

  def user_full_name()
    # For user_info see openc3/utilities/authorization and
    # openc3_enterprise/utilities/authorization
    user = user_info(request.headers['HTTP_AUTHORIZATION'])
    name = user['name']
    # Open Source name (EE has the actual name)
    name ||= 'Anonymous'
    return name
  end

  def username()
    # For user_info see openc3/utilities/authorization and
    # openc3_enterprise/utilities/authorization
    user = user_info(request.headers['HTTP_AUTHORIZATION'])
    username = user['username']
    # Open Source username (EE has the actual username)
    username ||= 'anonymous'
    return username
  end

  # Authorize and rescue the possible exceptions
  # @return [Boolean] true if authorize successful
  def authorization(permission, target_name: nil)
    begin
      authorize(
        permission: permission,
        target_name: target_name,
        manual: request.headers['HTTP_MANUAL'],
        scope: params[:scope],
        token: request.headers['HTTP_AUTHORIZATION'],
      )
    rescue OpenC3::AuthError => e
      render json: { status: 'error', message: e.message }, status: 401
      return false
    rescue OpenC3::ForbiddenError => e
      render json: { status: 'error', message: e.message }, status: 403
      return false
    end
    return true
  end

  def sanitize_params(param_list, require_params: true, allow_forward_slash: false, allow_parent_dir: false)
    if require_params
      result = params.require(param_list)
    else
      result = []
      param_list.each do |param|
        result << params[param]
      end
    end
    result.each_with_index do |arg, index|
      if arg
        # Prevent the code scanner detects:
        # "Uncontrolled data used in path expression"
        # This method is taken directly from the Rails source:
        #   https://api.rubyonrails.org/v5.2/classes/ActiveStorage/Filename.html#method-i-sanitized
        if allow_forward_slash
          # Sometimes we have forward slashes so optionally allow those
          value = arg.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "�").strip.tr("\u{202E}%$|:;\t\r\n\\", "-")
        else
          value = arg.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "�").strip.tr("\u{202E}%$|:;/\t\r\n\\", "-")
        end
        if not allow_parent_dir
          value = value.gsub(/(\.|%2e){2}/i, "-")
        end
        if value != arg
          render json: { status: 'error', message: "Invalid #{param_list[index]}: #{arg}" }, status: 400
          return false
        end
      end
    end
    return result
  end
end

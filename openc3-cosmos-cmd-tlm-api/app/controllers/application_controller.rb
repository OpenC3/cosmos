# encoding: utf-8

# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2026, OpenC3, Inc.
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
    # COSMOS Core name (Enterprise has the actual name)
    name ||= 'Anonymous'
    return name
  end

  def username()
    # For user_info see openc3/utilities/authorization and
    # openc3_enterprise/utilities/authorization
    user = user_info(request.headers['HTTP_AUTHORIZATION'])
    username = user['username']
    # COSMOS Core username (Enterprise has the actual username)
    username ||= 'anonymous'
    return username
  end

  # Authorize and rescue the possible exceptions
  # @return [Boolean or User] User if authorize successful
  def authorization(permission, target_name: nil, packet_name: nil, perform_render: true)
    begin
      return authorize(
        permission: permission,
        target_name: target_name,
        packet_name: packet_name,
        manual: request.headers['HTTP_MANUAL'],
        scope: params[:scope],
        token: request.headers['HTTP_AUTHORIZATION'],
      )
    rescue OpenC3::AuthError => e
      render json: { status: 'error', message: e.message }, status: :unauthorized if perform_render
      return false
    rescue OpenC3::ForbiddenError => e
      render json: { status: 'error', message: e.message }, status: :forbidden if perform_render
      return false
    end
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
          render json: { status: 'error', message: "Invalid #{param_list[index]}: #{arg}" }, status: :bad_request
          return false
        end
      end
    end
    return result
  end

  def log_error(e)
    if ENV['OPENC3_FULL_BACKTRACE']
      filtered_backtrace = e.backtrace
    else
      # Filter out backtrace to only application code
      filtered_backtrace = e.backtrace.select { |line| !line.include?('activesupport') && !line.include?('actionpack') && !line.include?('rspec') && !line.include?('bundler') }
    end
    logger.error("#{e.message}\n#{filtered_backtrace.join("\n")}")
  end

  # JSON for responses that carry user text, like plugin.txt descriptions or
  # device names ("Manette 🎮"). The COSMOS String#as_json used by
  # `render json:` sends strings with characters outside Latin-1 as raw byte
  # objects. Strings read as binary (plugin.txt) are UTF-8 text, so they're
  # sent as UTF-8 with any invalid bytes replaced.
  def text_json(value)
    JSON.generate(utf8_text(value))
  end

  def utf8_text(value)
    case value
    when String
      return value if value.encoding == Encoding::UTF_8 and value.valid_encoding?
      value.dup.force_encoding(Encoding::UTF_8).scrub
    when Array then value.map { |item| utf8_text(item) }
    when Hash then value.to_h { |key, item| [utf8_text(key), utf8_text(item)] }
    else value
    end
  end
end

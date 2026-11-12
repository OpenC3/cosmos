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

require 'base64'
require 'json'
require 'openc3/models/service_account_script_auth_model'
require 'openc3/utilities/secrets'

module OpenC3
  # Helpers for persisting durable child-script auth context for service-account
  # callers.
  module ServiceAccountScriptAuth
    module_function

    def bearer_token_from_header(auth_header)
      return nil unless auth_header&.start_with?('Bearer ')

      auth_header.delete_prefix('Bearer ').strip
    end

    def service_account_username?(username)
      username&.start_with?('service-account-')
    end

    def persist_service_account_script_auth_context(scope:, username:, token:)
      raise 'Invalid service-account username' unless service_account_username?(username)

      client_id = extract_service_account_client_id(token)
      secret_reference = service_account_secret_reference(scope: scope, client_id: client_id)

      ServiceAccountScriptAuthModel.set(
        {
          name: username,
          auth_kind: 'client_credentials',
          client_id: client_id,
          client_secret_name: secret_reference[:client_secret_name],
          secret_store: secret_reference[:secret_store],
        },
        scope: scope,
      )
    end

    def service_account_secret_reference(scope:, client_id:)
      secret_name = service_account_secret_name(client_id)
      secret_value = OpenC3::Secrets.getClient.get(secret_name, scope: scope)
      if secret_present?(secret_value)
        return {
          client_secret_name: secret_name,
          secret_store: nil,
        }
      end

      raise "No durable machine client secret configured for service-account client #{client_id}"
    end

    def extract_service_account_client_id(token)
      token_parts = token.to_s.split('.')
      raise 'Service-account bearer token must be a JWT access token' unless token_parts.length == 3

      payload = token_parts[1]
      missing_padding = -payload.length % 4
      payload += '=' * missing_padding if missing_padding != 0
      claims = JSON.parse(Base64.urlsafe_decode64(payload))
      client_id = claims['azp']
      raise 'Service-account bearer token missing azp claim' if client_id.nil? || client_id.empty?

      client_id
    rescue JSON::ParserError, ArgumentError => error
      raise "Unable to parse service-account bearer token: #{error.message}"
    end

    def service_account_secret_name(client_id)
      client_id
    end

    def secret_present?(secret_value)
      !secret_value.nil? && !secret_value.empty?
    end
  end
end

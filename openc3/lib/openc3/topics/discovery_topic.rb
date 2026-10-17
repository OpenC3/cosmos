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

require 'securerandom'
require 'openc3/topics/topic'

module OpenC3
  # Discovery requests are published to a bridge hub (bridge_microservice) which
  # hands them to openc3-app. openc3-app runs the Python Discovery class on the
  # host and the hub publishes the result back on the result topic.
  # See openc3/python/openc3/topics/discovery_topic.py
  class DiscoveryTopic < Topic
    DISCOVERY_TIMEOUT_S = 30

    def self.request_topic(bridge_name, scope:)
      "#{scope}__DISCOVERY__#{bridge_name}"
    end

    def self.result_topic(bridge_name, scope:)
      "#{scope}__DISCOVERY_RESULT__#{bridge_name}"
    end

    # Run a discovery on the host connected to the given bridge
    #
    # @param bridge_name [String] Name of the bridge (e.g. DEFAULT)
    # @param discovery [Array<String>] Discovery class filename followed by its parameters
    # @param timeout [Numeric] Seconds to wait for the host to respond
    # @return [Array<Hash>] Discovered values as { 'value' => ..., 'text' => ... }
    def self.discover(bridge_name, discovery, timeout: nil, scope:)
      timeout = DISCOVERY_TIMEOUT_S unless timeout
      result_topic = result_topic(bridge_name, scope: scope)
      Topic.update_topic_offsets([result_topic])

      id = SecureRandom.uuid
      request = { 'id' => id, 'discovery' => JSON.generate(discovery), 'expires_at' => (Time.now.to_f + timeout).to_s }
      Topic.write_topic(request_topic(bridge_name, scope: scope), request, '*', 100)
      time = Time.now
      while (Time.now - time) < timeout
        Topic.read_topics([result_topic]) do |_topic, _msg_id, msg_hash, _redis|
          next unless msg_hash['id'] == id
          result = JSON.parse(msg_hash['result'])
          raise result['error'] if result['error']
          return result['results'] || []
        end
      end
      raise "Timeout of #{timeout}s waiting for discovery on bridge '#{bridge_name}'. Is openc3-app running and paired with COSMOS?"
    end
  end
end

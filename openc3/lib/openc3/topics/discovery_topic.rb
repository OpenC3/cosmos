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
  # hands them to openc3-cosmos-app. openc3-cosmos-app runs the Python Discovery class on the
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
      result = request(bridge_name, { 'discovery' => JSON.generate(discovery) }, timeout: timeout, scope: scope)
      result['results'] || []
    end

    # Scan the host connected to the given bridge for hardware and check it
    # against discovery matchers (see openc3/python/openc3/discovery/discovery_scan.py)
    #
    # @param bridge_name [String] Name of the bridge (e.g. DEFAULT)
    # @param scan [Hash] { 'matchers' => [{ 'id', 'class', 'params' }], 'classes' => [...] }
    # @param timeout [Numeric] Seconds to wait for the host to respond
    # @return [Hash] { 'devices' => [...], 'errors' => {...}, 'skipped' => {...} }
    def self.scan(bridge_name, scan, timeout: nil, scope:)
      # An empty discovery makes an openc3-cosmos-app without scan support answer with an error
      fields = { 'discovery' => '[]', 'scan' => JSON.generate(scan) }
      result = request(bridge_name, fields, timeout: timeout, scope: scope)
      return result['scan'] if result['scan']
      raise "openc3-cosmos-app on the host for bridge '#{bridge_name}' does not support hardware discovery. Update openc3-cosmos-app."
    rescue RuntimeError => error
      raise "openc3-cosmos-app on the host for bridge '#{bridge_name}' does not support hardware discovery. Update openc3-cosmos-app." if error.message == 'no discovery class given'
      raise
    end

    # Publish a request for the bridge's host and wait for its result
    def self.request(bridge_name, fields, timeout:, scope:)
      timeout = DISCOVERY_TIMEOUT_S unless timeout
      result_topic = result_topic(bridge_name, scope: scope)
      Topic.update_topic_offsets([result_topic])

      id = SecureRandom.uuid
      request = { 'id' => id }.merge(fields).merge('expires_at' => (Time.now.to_f + timeout).to_s)
      Topic.write_topic(request_topic(bridge_name, scope: scope), request, '*', 100)
      time = Time.now
      while (Time.now - time) < timeout
        Topic.read_topics([result_topic]) do |_topic, _msg_id, msg_hash, _redis|
          next unless msg_hash['id'] == id
          result = JSON.parse(msg_hash['result'])
          raise result['error'] if result['error']
          return result
        end
      end
      raise "Timeout of #{timeout}s waiting for discovery on bridge '#{bridge_name}'. Is openc3-cosmos-app running and paired with COSMOS?"
    end
    private_class_method :request
  end
end

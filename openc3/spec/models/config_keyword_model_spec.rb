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

require 'spec_helper'
require 'openc3/models/config_keyword_model'
require 'openc3/models/interface_model'
require 'openc3/models/microservice_model'

module OpenC3
  # PORT and SECRET are handled by ConfigKeywordModel on behalf of every model
  # that includes it, so the keyword behavior is specified once here and run
  # against each including model. Model specific storage of the parsed result
  # (and InterfaceModel's BRIDGE_SECRET) stays in the individual model specs.
  describe ConfigKeywordModel do
    before(:each) do
      mock_redis()
    end

    # Feed lines through the model's handle_config and return the model
    def parse(model, *lines)
      with_config_file(lines) do |parser, path|
        parser.parse_file(path) do |keyword, params|
          model.handle_config(parser, keyword, params)
        end
      end
      model
    end

    # Feed a single line through handle_config and expect it to raise
    def expect_parse_error(model, line, message)
      with_config_file([line]) do |parser, path|
        parser.parse_file(path) do |keyword, params|
          expect { model.handle_config(parser, keyword, params) }.to raise_error(ConfigParser::Error, message)
        end
      end
    end

    def with_config_file(lines)
      parser = ConfigParser.new
      tf = Tempfile.new
      lines.each { |line| tf.puts(line) }
      tf.close
      begin
        yield parser, tf.path
      ensure
        tf.unlink
      end
    end

    shared_examples "a model that handles PORT" do
      it "defaults the protocol to TCP" do
        expect(parse(new_model, "PORT 8888").as_json()['ports']).to eql [[8888, 'TCP']]
      end

      it "accepts and upcases the supported protocols" do
        model = parse(new_model, "PORT 1 TCP", "PORT 2 udp", "PORT 3 sctp")
        expect(model.as_json()['ports']).to eql [[1, 'TCP'], [2, 'UDP'], [3, 'SCTP']]
      end

      it "raises on non-integer ports" do
        expect_parse_error(new_model, "PORT asdf", /Port must be an integer/)
      end

      it "raises on invalid port protocols" do
        expect_parse_error(new_model, "PORT 1234 BLAH", /Unknown port protocol: BLAH/)
      end
    end

    shared_examples "a model that validates SECRET" do
      it "rejects SECRET FILE paths outside the secret file dir" do
        ['/etc/passwd', '/tmp/../etc/passwd', '/root/.ssh/id_rsa', '../../config/secrets.yml'].each do |path|
          expect_parse_error(new_model, secret_line('FILE', 'KEY', path), /must be under/)
        end
      end

      it "rejects unknown SECRET types" do
        expect_parse_error(new_model, secret_line('OTHER', 'KEY', 'DATA'), /Unknown secret type/)
      end

      it "normalizes the secret type and file path" do
        model = parse(new_model,
                      secret_line('env', 'USERNAME', 'ENV_USERNAME'),
                      secret_line('file', 'KEY', '/tmp/DATA/../DATA/cert'),
                      secret_line('file', 'KEY2', '/tmp/DATA/./cert2'))
        # secrets are [type, name, data, ...] - the trailing entries are model specific
        expect(model.secrets.map { |secret| secret[0..2] }).to eql [
          ['ENV', 'USERNAME', 'ENV_USERNAME'],
          ['FILE', 'KEY', '/tmp/DATA/cert'],
          ['FILE', 'KEY2', '/tmp/DATA/cert2'],
        ]
      end
    end

    context "InterfaceModel" do
      def new_model
        InterfaceModel.new(name: "TEST_INT", scope: "DEFAULT")
      end

      # InterfaceModel SECRET takes a trailing Option Name
      def secret_line(type, name, data)
        "SECRET #{type} #{name} \"#{data}\" #{name}"
      end

      it_behaves_like "a model that handles PORT"
      it_behaves_like "a model that validates SECRET"
    end

    context "MicroserviceModel" do
      def new_model
        MicroserviceModel.new(folder_name: "TEST", name: "DEFAULT__TYPE__NAME", scope: "DEFAULT")
      end

      def secret_line(type, name, data)
        "SECRET #{type} #{name} \"#{data}\""
      end

      it_behaves_like "a model that handles PORT"
      it_behaves_like "a model that validates SECRET"
    end
  end
end

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
require 'openc3/script'

module OpenC3
  describe Script do
    describe "metadata deprecation" do
      before(:each) do
        @orig_api_server = $api_server
        $api_server = double("ApiServer")
        body = JSON.generate({ 'start' => 1, 'color' => '#003784', 'metadata' => { 'key1' => 'value1' } })
        allow($api_server).to receive(:request) do |method, *_args, **_kwargs|
          status = method == 'post' ? 201 : 200
          double("Response", status: status, body: body)
        end
      end

      after(:each) do
        $api_server = @orig_api_server
      end

      it "warns for each metadata method" do
        expect { metadata_all() }.to output(/\[DEPRECATION\] `metadata_all` is deprecated/).to_stderr
        expect { metadata_get() }.to output(/\[DEPRECATION\] `metadata_get` is deprecated/).to_stderr
        expect { metadata_set({ 'key1' => 'value1' }) }.to output(/\[DEPRECATION\] `metadata_set` is deprecated/).to_stderr
        expect { metadata_update({ 'key1' => 'value2' }) }.to output(/\[DEPRECATION\] `metadata_update` is deprecated/).to_stderr
      end

      it "warns before metadata_input raises outside Script Runner" do
        expect {
          expect { metadata_input() }.to raise_error(StandardError, "can only be used in Script Runner")
        }.to output(/\[DEPRECATION\] `metadata_input` is deprecated/).to_stderr
      end

      it "warns only once from metadata_update" do
        expect { metadata_update({ 'key1' => 'value2' }) }.to output(/\A[^\n]*metadata_update[^\n]*\n\z/).to_stderr
      end

      it "warns even when deprecation warnings are disabled" do
        orig_deprecated = Warning[:deprecated]
        Warning[:deprecated] = false
        expect { metadata_get() }.to output(/\[DEPRECATION\] `metadata_get` is deprecated/).to_stderr
      ensure
        Warning[:deprecated] = orig_deprecated
      end

      # Script Runner evaluates scripts inside OpenC3.disable_warnings ($VERBOSE = nil),
      # which turns Kernel#warn into a no-op
      it "warns even when Ruby warnings are disabled" do
        OpenC3.disable_warnings do
          expect { metadata_get() }.to output(/\[DEPRECATION\] `metadata_get` is deprecated/).to_stderr
          expect {
            expect { metadata_input() }.to raise_error(StandardError, "can only be used in Script Runner")
          }.to output(/\[DEPRECATION\] `metadata_input` is deprecated/).to_stderr
        end
      end
    end
  end
end

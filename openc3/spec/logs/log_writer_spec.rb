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
require 'openc3/logs/log_writer'

module OpenC3
  describe LogWriter do
    describe "self.db_shard_for_topic" do
      it "looks up the db_shard of the target in the topic hashtag" do
        expect(Store).to receive(:db_shard_for_target).with('INST', scope: 'OTHER').and_return(2)
        expect(LogWriter.db_shard_for_topic('OTHER__TELEMETRY__{INST}__HEALTH_STATUS')).to eql 2
      end

      it "handles target names containing underscores" do
        expect(Store).to receive(:db_shard_for_target).with('MY_TARGET', scope: 'DEFAULT').and_return(1)
        expect(LogWriter.db_shard_for_topic('DEFAULT__DECOM__{MY_TARGET}__PKT')).to eql 1
      end

      it "returns 0 for topics without a target" do
        expect(Store).not_to receive(:db_shard_for_target)
        expect(LogWriter.db_shard_for_topic('DEFAULT__openc3_log_messages')).to eql 0
      end
    end
  end
end

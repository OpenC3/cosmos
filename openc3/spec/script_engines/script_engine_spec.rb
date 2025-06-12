# encoding: ascii-8bit

# Copyright 2025 OpenC3, Inc.
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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'openc3/script_engines/script_engine'

module OpenC3
  describe ScriptEngine do
    before(:each) do
      @mock_running_script = double("running_script")
      @engine = ScriptEngine.new(@mock_running_script)
    end

    describe "tokenizer" do
      it "handles basic tokenization" do
        result = @engine.tokenizer("WRITE 'Hello World'")
        expect(result).to eq(['WRITE', "'Hello World'"])
      end

      it "handles special characters" do
        result = @engine.tokenizer("LET $VAR = 42")
        expect(result).to eq(["LET", "$VAR", "=", "42"])
      end

      it "preserves double quotes" do
        result = @engine.tokenizer('WRITE "Hello World"')
        expect(result).to eq(['WRITE', '"Hello World"'])
      end

      it "preserves single quotes" do
        result = @engine.tokenizer("WRITE 'Single quotes'")
        expect(result).to eq(['WRITE', "'Single quotes'"])
      end

      it "handles multiple quoted strings" do
        result = @engine.tokenizer('WRITE "Hello" , "World"')
        expect(result).to eq(['WRITE', '"Hello"', ',', '"World"'])
      end

      context "with timestamps" do
        it "handles simple time format" do
          result = @engine.tokenizer('WRITE 11:30:00')
          expect(result).to eq(['WRITE', '11:30:00'])
        end

        it "handles full date-time format" do
          result = @engine.tokenizer('WRITE 2025/123-11:30:00.57')
          expect(result).to eq(['WRITE', '2025', '/', '123', '-', '11:30:00.57'])
        end

        it "handles day of year without year" do
          result = @engine.tokenizer('WRITE /123-11:30:00.57')
          expect(result).to eq(['WRITE', '/', '123', '-', '11:30:00.57'])
        end

        it "handles year with no day of year" do
          result = @engine.tokenizer('WRITE 2025/-11:30:00.57')
          expect(result).to eq(['WRITE', '2025', '/', '-', '11:30:00.57'])
        end

        it "handles time with no date" do
          result = @engine.tokenizer('WRITE /-11:30:00.57')
          expect(result).to eq(['WRITE', '/', '-', '11:30:00.57'])
        end
      end
    end
  end
end
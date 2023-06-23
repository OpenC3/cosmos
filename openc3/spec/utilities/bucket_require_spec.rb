# encoding: ascii-8bit

# Copyright 2023 OpenC3, Inc
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

# bucket_require redefines require and load so first store the originals
$orig_require = Object.instance_method(:require)
$orig_load = Object.instance_method(:load)

require 'spec_helper'
require 'openc3/utilities/bucket_require'

module OpenC3
  describe Bucket do
    before(:each) do
      @bucket = double(Bucket)
      allow(@bucket).to receive(:get_object).and_return(nil)
      allow(Bucket).to receive(:getClient).and_return(@bucket)
    end

    after(:all) do
      # Restore the original require and load for the rest of the specs
      Object.define_method($orig_require.name, $orig_require)
      Object.define_method($orig_load.name, $orig_load)
    end

    describe "require" do
      it "raise LoadError if file not found" do
        expect { require('INST/filename') }.to raise_error(LoadError, "cannot load such file -- INST/filename.rb")
      end

      it "doesn't allow absolute paths" do
        expect { require('/INST/filename') }.to raise_error(LoadError, "only relative TARGET files are allowed -- /INST/filename")
      end

      it "doesn't allow non-target paths" do
        expect { require('path/filename') }.to raise_error(LoadError, "only relative TARGET files are allowed -- path/filename")
      end

      it "handles other exceptions" do
        allow(@bucket).to receive(:get_object).and_raise("BLAH")
        expect { require('INST/filename') }.to raise_error(LoadError, "RuntimeError:BLAH")
      end
    end

    describe "load" do
      it "raise LoadError if file not found" do
        expect { load('INST/filename.rb') }.to raise_error(LoadError, "cannot load such file -- INST/filename.rb")
      end

      it "doesn't allow absolute paths" do
        expect { load('/INST/filename.rb') }.to raise_error(LoadError, "only relative TARGET files are allowed -- /INST/filename.rb")
      end

      it "doesn't allow non-target paths" do
        expect { load('path/filename.rb') }.to raise_error(LoadError, "only relative TARGET files are allowed -- path/filename.rb")
      end

      it "handles other exceptions" do
        allow(@bucket).to receive(:get_object).and_raise("BLAH")
        expect { load('INST/filename.rb') }.to raise_error(LoadError, "RuntimeError:BLAH")
      end
    end
  end
end

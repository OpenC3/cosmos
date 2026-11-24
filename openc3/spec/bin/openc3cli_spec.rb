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

require "spec_helper"
require "open3"
require "tmpdir"

# Runs the real openc3/bin/openc3cli in a child process, so what is asserted is
# the exit status `openc3.sh cli` hands back to a shell or CI step.
module OpenC3
  describe "openc3cli" do
    OPENC3_DIR = File.expand_path(File.join(__dir__, "..", ".."))

    around(:each) do |example|
      Dir.mktmpdir do |dir|
        @dir = dir
        example.run
      end
    end

    def openc3cli(*args)
      Open3.capture2e(RbConfig.ruby, "-I", File.join(OPENC3_DIR, "lib"),
                      File.join(OPENC3_DIR, "bin", "openc3cli"), *args, chdir: @dir)
    end

    describe "rake" do
      before(:each) do
        File.write(File.join(@dir, "Rakefile"), <<~RUBY)
          task(:pass) { puts "rake ran \#{ENV['VERSION']}" }
          task(:fail) { abort "rake failed" }
        RUBY
      end

      it "passes arguments to rake and exits 0 when it succeeds" do
        output, status = openc3cli("rake", "pass", "VERSION=1.0.0")

        expect(output).to include("rake ran 1.0.0")
        expect(status.exitstatus).to eql 0
      end

      # A failed `rake build` must fail `openc3.sh cli rake build`, or a CI
      # job that builds a plugin passes with no gem
      it "exits non-zero when rake fails" do
        output, status = openc3cli("rake", "fail")

        expect(output).to include("rake failed")
        expect(status.success?).to be false
      end

      it "exits non-zero without a Rakefile" do
        File.delete(File.join(@dir, "Rakefile"))
        output, status = openc3cli("rake", "build")

        expect(output).to include("No Rakefile found!")
        expect(status.success?).to be false
      end
    end
  end
end

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

# Everything else about the index arguments is asserted against the argv COSMOS
# builds. This file asserts the other half: that uv still *behaves* the way
# those arguments assume. Both facts below are uv implementation details that a
# uv upgrade could change without any COSMOS code changing, and the symptom
# would be silent - a plugin resolving off the index an operator designated,
# with the install still reporting success.
#
# No network: every index here is an RFC 2606 .invalid host, so resolution
# always fails at DNS and the error names whichever index uv decided to consult.
# That name is the assertion.
module OpenC3
  describe "uv index isolation" do
    DEFAULT_INDEX = "https://default.invalid/simple"
    PLUGIN_INDEX = "https://plugin-private.invalid/simple"

    before(:all) do
      # uv is present in the COSMOS images and on a normal dev machine, but this
      # spec is about a tool the suite does not otherwise need, so skip rather
      # than fail where it is absent.
      skip "uv is not on PATH" unless system("which uv > /dev/null 2>&1")
    end

    around(:each) do |example|
      Dir.mktmpdir { |dir| @dir = dir and example.run }
    end

    # @param uv_table [String] the [tool.uv] body under test
    def write_pyproject(uv_table)
      File.write(File.join(@dir, "pyproject.toml"), <<~TOML)
        [project]
        name = "fixture-plugin"
        version = "0.0.0"
        requires-python = ">=3.11"
        dependencies = ["fixture-package"]

        [tool.uv]
        #{uv_table}
      TOML
    end

    # @return [String] combined uv output, which on failure names the index host
    #   uv tried to reach
    def uv_lock(*extra_args)
      output, _status = Open3.capture2e(
        { "UV_HTTP_CONNECT_TIMEOUT" => "5", "UV_HTTP_RETRIES" => "0", "UV_OFFLINE" => "0" },
        "uv", "lock", "--default-index", DEFAULT_INDEX, *extra_args,
        chdir: @dir
      )
      output
    end

    # openc3/bin/uvinstall and openc3/bin/pipinstall pass --no-config for exactly
    # this reason: without it the operator's index loses to one the plugin
    # declared, which is not what --default-index reads like it should do.
    context "an index the plugin declares in [tool.uv].index" do
      before(:each) do
        write_pyproject(%(index = [{ name = "private", url = "#{PLUGIN_INDEX}" }]))
      end

      it "beats --default-index on its own" do
        expect(uv_lock).to include("plugin-private.invalid")
      end

      it "is suppressed by --no-config" do
        expect(uv_lock("--no-config")).to include("default.invalid")
      end
    end

    # A sources pin is project metadata rather than user configuration, so it
    # survives --no-config. This is why --no-sources is needed on top of it, and
    # it is the fact most likely to change quietly in a future uv.
    context "a package pinned to that index with [tool.uv].sources" do
      before(:each) do
        write_pyproject(<<~TOML)
          index = [{ name = "private", url = "#{PLUGIN_INDEX}" }]
          sources = { fixture-package = { index = "private" } }
        TOML
      end

      it "survives --no-config" do
        expect(uv_lock("--no-config")).to include("plugin-private.invalid")
      end

      it "is suppressed by --no-sources" do
        expect(uv_lock("--no-config", "--no-sources")).to include("default.invalid")
      end
    end

    # uvinstall must never add --no-sources to its `uv sync --frozen` call. uv
    # rejects the pair outright, so doing so would fail every locked plugin
    # install rather than degrading quietly.
    it "rejects --no-sources on a frozen sync" do
      write_pyproject("package = false")
      output, status = Open3.capture2e("uv", "sync", "--frozen", "--no-sources", chdir: @dir)

      expect(status.success?).to be false
      expect(output).to include("cannot be used with")
    end
  end
end

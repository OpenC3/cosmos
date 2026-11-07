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
require "tmpdir"

# openc3/bin/uvinstall and openc3/bin/pipinstall decide where --no-sources goes,
# and that decision is not visible from Ruby: PypiUrl.build_args stops at
# --no-config. These examples run the real scripts with a stub `uv` on PATH that
# records the argv it was handed, so what is asserted is the command line the
# scripts actually build.
module OpenC3
  describe "python install scripts" do
    BIN_DIR = File.expand_path(File.join(__dir__, "..", "..", "bin"))

    # A mirror configured by an operator. PypiUrl.build_args adds --no-config
    # alongside the index whenever it is not the public default, so --no-config
    # is what the scripts read as "an operator designated an index".
    MIRROR_ARGS = ["--default-index", "https://mirror.example.com/simple", "--no-config"].freeze
    DEFAULT_ARGS = ["--default-index", "https://pypi.org/simple"].freeze

    around(:each) do |example|
      Dir.mktmpdir do |dir|
        @dir = dir
        @uv_log = File.join(dir, "uv.log")
        stub_uv
        example.run
      end
    end

    # Records one line per invocation so an example can assert on the specific
    # uv subcommand it cares about. Always succeeds: these examples are about
    # the argv, not about install behavior.
    def stub_uv
      stub_bin = File.join(@dir, "stub_bin")
      FileUtils.mkdir_p(stub_bin)
      uv = File.join(stub_bin, "uv")
      File.write(uv, <<~SH)
        #!/bin/sh
        echo "$@" >> "#{@uv_log}"
        exit 0
      SH
      FileUtils.chmod(0o755, uv)
      @path = "#{stub_bin}:#{ENV['PATH']}"
    end

    # @return [Array<String>] the recorded uv invocations whose first word is
    #   the given subcommand, e.g. "pip install" or "sync"
    def uv_calls(starting_with)
      return [] unless File.exist?(@uv_log)

      File.readlines(@uv_log, chomp: true).select { |line| line.start_with?(starting_with) }
    end

    # The negative assertions below would pass on an empty log, so every example
    # goes through this: it fails loudly when the script never reached uv.
    def only_uv_call(starting_with)
      calls = uv_calls(starting_with)
      expect(calls).to_not be_empty, "expected a `uv #{starting_with}` invocation, got: #{uv_calls('').inspect}"
      expect(calls.first).to include("--default-index")
      calls.first
    end

    def run_script(script, *args, env: {})
      system({ "PATH" => @path }.merge(env), File.join(BIN_DIR, script), *args,
             out: File::NULL, err: File::NULL)
    end

    describe "pipinstall" do
      def run_pipinstall(*args)
        run_script("pipinstall", *args, env: { "PIPINSTALL_VENV" => File.join(@dir, "venv") })
      end

      # --no-config alone leaves a [tool.uv].sources pin in force, so the
      # operator's index would still be bypassed for the pinned package.
      it "adds --no-sources when an operator designated an index" do
        run_pipinstall(*MIRROR_ARGS, File.join(@dir, "pkg.tar.gz"))

        expect(only_uv_call("pip install")).to include("--no-sources")
      end

      # At the public default there is no operator policy to enforce, so a
      # plugin's own index configuration is left alone.
      it "omits --no-sources at the public default index" do
        run_pipinstall(*DEFAULT_ARGS, File.join(@dir, "pkg.tar.gz"))

        expect(only_uv_call("pip install")).to_not include("--no-sources")
      end
    end

    describe "uvinstall" do
      def gem_path_with(filename, contents)
        gem_path = File.join(@dir, "gem")
        FileUtils.mkdir_p(gem_path)
        File.write(File.join(gem_path, filename), contents)
        gem_path
      end

      def run_uvinstall(gem_path, *args)
        run_script("uvinstall", "TEST__PLUGIN", gem_path, *args,
                   env: { "UVINSTALL_VENV_ROOT" => File.join(@dir, "venvs") })
      end

      it "adds --no-sources to a resolving install when an operator designated an index" do
        gem_path = gem_path_with("requirements.txt", "requests\n")
        run_uvinstall(gem_path, *MIRROR_ARGS)

        expect(only_uv_call("pip install")).to include("--no-sources")
      end

      it "omits --no-sources at the public default index" do
        gem_path = gem_path_with("requirements.txt", "requests\n")
        run_uvinstall(gem_path, *DEFAULT_ARGS)

        expect(only_uv_call("pip install")).to_not include("--no-sources")
      end

      # uv rejects the combination outright - "the argument '--frozen' cannot be
      # used with '--no-sources'" - and a frozen sync has no use for it anyway,
      # because it installs the URLs already recorded in uv.lock without
      # resolving. Passing it here would fail every locked plugin install.
      it "never passes --no-sources to a frozen sync" do
        gem_path = gem_path_with("pyproject.toml", "[project]\n")
        File.write(File.join(gem_path, "uv.lock"), "version = 1\n")
        run_uvinstall(gem_path, *MIRROR_ARGS)

        sync = only_uv_call("sync")
        expect(sync).to include("--no-config")
        expect(sync).to_not include("--no-sources")
      end
    end
  end
end

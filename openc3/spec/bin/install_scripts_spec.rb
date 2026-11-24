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
    # uv subcommand it cares about. Succeeds unless UV_STUB_FAIL_ON names the
    # start of the argv, which lets an example drive a failure path.
    def stub_uv
      stub_bin = File.join(@dir, "stub_bin")
      FileUtils.mkdir_p(stub_bin)
      uv = File.join(stub_bin, "uv")
      File.write(uv, <<~SH)
        #!/bin/sh
        echo "$@" >> "#{@uv_log}"
        case "$*" in
            "${UV_STUB_FAIL_ON:-<none>}"*) exit 1 ;;
        esac
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

      # A plugin built with [tool.openc3] offline_install = true ships its wheels
      # in python_wheels/. PluginModel points uvinstall at them, and the install
      # must come from those files alone: the deployment has no index to reach.
      describe "with bundled wheels" do
        def offline_gem_path
          gem_path = gem_path_with("pyproject.toml", "[project]\n")
          File.write(File.join(gem_path, "uv.lock"), "version = 1\n")
          FileUtils.mkdir_p(File.join(gem_path, "python_wheels"))
          File.write(File.join(gem_path, "python_wheels", "six-1.17.0-py2.py3-none-any.whl"), "wheel")
          gem_path
        end

        def wheelhouse
          File.join(@dir, "uv_cache", "offline_wheels")
        end

        def run_offline_uvinstall(gem_path, fail_on: nil)
          env = { "UVINSTALL_VENV_ROOT" => File.join(@dir, "venvs"),
                  "UV_CACHE_DIR" => File.join(@dir, "uv_cache"),
                  "UVINSTALL_OFFLINE_WHEELS" => File.join(gem_path, "python_wheels") }
          env["UV_STUB_FAIL_ON"] = fail_on if fail_on
          run_script("uvinstall", "TEST__PLUGIN", gem_path, *MIRROR_ARGS, env: env)
        end

        it "installs from the bundled wheels against the hashes in uv.lock" do
          gem_path = offline_gem_path
          expect(run_offline_uvinstall(gem_path)).to be true

          export = uv_calls("export")
          expect(export.length).to eql 1
          expect(export[0]).to include("--frozen", "--no-dev", "--format requirements-txt")

          install = uv_calls("pip install")
          expect(install.length).to eql 1
          # uv caches find-links wheels under a digest of the directory, and the
          # gem is extracted to a new temp directory on every install. Staging
          # the wheels in one directory inside the UV cache keeps that digest
          # stable, so a reinstall reuses the cache instead of growing it.
          expect(install[0]).to include("--offline", "--no-index", "--require-hashes", "--find-links #{wheelhouse}")
          expect(File.read(File.join(wheelhouse, "six-1.17.0-py2.py3-none-any.whl"))).to eql "wheel"
          # The operator's index is irrelevant here and must not be consulted
          expect(install[0]).to_not include("--default-index")
          expect(uv_calls("sync")).to be_empty
          expect(File.exist?(File.join(@dir, "venvs", "TEST__PLUGIN", ".uv_managed"))).to be true
        end

        # Plugins that share a dependency stage the same wheel name, and one
        # install's uv may be reading it while another stages it. Rewriting the
        # file in place would expose a partial wheel; a rename never does.
        it "replaces a staged wheel by rename, never rewriting it in place" do
          gem_path = offline_gem_path
          staged = File.join(wheelhouse, "six-1.17.0-py2.py3-none-any.whl")
          FileUtils.mkdir_p(wheelhouse)
          File.write(staged, "old")
          inode = File.stat(staged).ino

          expect(run_offline_uvinstall(gem_path)).to be true

          expect(File.read(staged)).to eql "wheel"
          expect(File.stat(staged).ino).to_not eql inode
          expect(Dir.children(wheelhouse)).to eql ["six-1.17.0-py2.py3-none-any.whl"]
        end

        it "fails without retrying online when the bundle cannot satisfy the lock" do
          gem_path = offline_gem_path
          expect(run_offline_uvinstall(gem_path, fail_on: "pip install")).to be false

          expect(uv_calls("pip install").length).to eql 1
          expect(uv_calls("sync")).to be_empty
          expect(File.exist?(File.join(@dir, "venvs", "TEST__PLUGIN", ".uv_managed"))).to be false
        end
      end
    end
  end
end

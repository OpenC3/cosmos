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
require 'tmpdir'
require 'base64'
require 'digest'
require 'stringio'
require 'zip'
require 'openc3/utilities/python_wheel_bundle'

module OpenC3
  describe PythonWheelBundle do
    around(:each) do |example|
      Dir.mktmpdir do |dir|
        @dir = dir
        example.run
      end
    end

    def write_pyproject(body)
      File.write(File.join(@dir, 'pyproject.toml'), "[project]\nname = \"p\"\nversion = \"0.0.0\"\n#{body}")
    end

    describe "config" do
      it "is disabled when the plugin has no pyproject.toml" do
        expect(PythonWheelBundle.offline_install?(@dir)).to be false
      end

      it "is disabled when [tool.openc3] does not set offline_install" do
        write_pyproject("[tool.uv]\npackage = false\n")
        expect(PythonWheelBundle.offline_install?(@dir)).to be false
      end

      it "defaults the targets to the build machine" do
        write_pyproject("[tool.openc3]\noffline_install = true\n")
        expect(PythonWheelBundle.offline_install?(@dir)).to be true
        expect(PythonWheelBundle.config(@dir)).to eql({ offline_install: true, python_platforms: [], python_version: nil, requires_python: nil })
      end

      it "reads any TOML spelling of the table" do
        write_pyproject("[tool]\nopenc3 = { offline_install = true, python_platforms = [\"x86_64-manylinux_2_28\", \"aarch64-manylinux_2_28\"], python_version = \"3.13\" }\n")
        expect(PythonWheelBundle.config(@dir)).to eql({ offline_install: true,
                                                        python_platforms: ["x86_64-manylinux_2_28", "aarch64-manylinux_2_28"],
                                                        python_version: "3.13", requires_python: nil })
      end

      # The plugin template documents the setting in a comment, so the commented
      # example must not count, and must not need a Python process to rule out
      it "skips Python when offline_install appears only in a comment" do
        write_pyproject("[tool.openc3]\n# offline_install = true\n")
        expect(Open3).to_not receive(:capture3)
        expect(PythonWheelBundle.offline_install?(@dir)).to be false
      end

      it "is disabled when offline_install is false" do
        write_pyproject("[tool.openc3]\noffline_install = false\n")
        expect(PythonWheelBundle.offline_install?(@dir)).to be false
      end

      it "rejects an offline_install that is not a boolean" do
        write_pyproject("[tool.openc3]\noffline_install = \"yes\"\n")
        expect { PythonWheelBundle.config(@dir) }.to raise_error(PythonWheelBundle::Error, /offline_install must be true or false/)
      end

      it "rejects python_platforms that is not a list of strings" do
        write_pyproject("[tool.openc3]\noffline_install = true\npython_platforms = \"x86_64-manylinux_2_28\"\n")
        expect { PythonWheelBundle.config(@dir) }.to raise_error(PythonWheelBundle::Error, /python_platforms must be a list of strings/)
      end

      # Without it uv picks wheels for the build machine's Python, which is
      # only right by coincidence when building for another platform
      it "requires python_version alongside python_platforms" do
        write_pyproject("[tool.openc3]\noffline_install = true\npython_platforms = [\"x86_64-manylinux_2_28\"]\n")
        expect { PythonWheelBundle.config(@dir) }.to raise_error(PythonWheelBundle::Error, /python_platforms also needs python_version/)
      end

      it "reports a pyproject.toml that is not valid TOML" do
        write_pyproject("[tool.openc3]\noffline_install = \n")
        expect { PythonWheelBundle.config(@dir) }.to raise_error(PythonWheelBundle::Error, /pyproject.toml/)
      end

      it "reads the plugin's requires-python" do
        write_pyproject("requires-python = \">=3.11\"\n[tool.openc3]\noffline_install = true\n")
        expect(PythonWheelBundle.config(@dir)[:requires_python]).to eql ">=3.11"
      end
    end

    # uv selects wheels for any --python-version without checking the plugin's
    # requires-python, so a version the lock doesn't cover would bundle wheels
    # no COSMOS image can install. The check runs before the uv.lock checks,
    # so a version it accepts fails next on the missing lock instead.
    describe "python_version" do
      def build_with(requires_python, python_version)
        requires = requires_python ? "requires-python = \"#{requires_python}\"\n" : ""
        write_pyproject("#{requires}[tool.openc3]\noffline_install = true\npython_version = \"#{python_version}\"\n")
        PythonWheelBundle.build(@dir, out: StringIO.new)
      end

      it "rejects a version older than requires-python" do
        expect { build_with(">=3.11", "3.10") }.to raise_error(PythonWheelBundle::Error,
                                                               /python_version 3.10 is older than the plugin's requires-python \(>=3.11\)/)
        expect { build_with("~=3.12", "3.11") }.to raise_error(PythonWheelBundle::Error, /older than/)
      end

      it "accepts the same or a newer minor version" do
        expect { build_with(">=3.11", "3.11") }.to raise_error(PythonWheelBundle::Error, /requires a uv.lock/)
        expect { build_with(">=3.11.4", "3.11") }.to raise_error(PythonWheelBundle::Error, /requires a uv.lock/)
        expect { build_with(">=3.11,<4", "3.13.1") }.to raise_error(PythonWheelBundle::Error, /requires a uv.lock/)
      end

      it "accepts any version when requires-python has no lower bound" do
        expect { build_with(nil, "3.9") }.to raise_error(PythonWheelBundle::Error, /requires a uv.lock/)
      end

      it "rejects a value that is not a Python 3 version" do
        expect { build_with(nil, "abc") }.to raise_error(PythonWheelBundle::Error, /must be a Python version such as "3.13", not "abc"/)
        expect { build_with(nil, "3") }.to raise_error(PythonWheelBundle::Error, /must be a Python version/)
      end

      # Install reads the same pyproject.toml, and an existing gem built for an
      # older version must still install: only build and verify check it
      it "is not checked at install" do
        write_pyproject("requires-python = \">=3.11\"\n[tool.openc3]\noffline_install = true\npython_version = \"3.10\"\n")
        File.write(File.join(@dir, 'uv.lock'), "version = 1\n")
        FileUtils.mkdir_p(File.join(@dir, 'python_wheels'))

        expect(PythonWheelBundle.offline_wheels_dir(@dir)).to eql File.join(@dir, 'python_wheels')
      end
    end

    describe "installed_wheels" do
      # WHEEL is copied from the wheel as built, so it can have CRLF line endings
      it "reads the tags from a WHEEL file with LF or CRLF line endings" do
        ["\n", "\r\n"].each_with_index do |newline, index|
          target = File.join(@dir, "target_#{index}")
          dist_info = File.join(target, "fake-1.0.dist-info")
          FileUtils.mkdir_p(dist_info)
          File.write(File.join(dist_info, 'METADATA'), ["Metadata-Version: 2.1", "Name: fake", "Version: 1.0", ""].join(newline))
          File.write(File.join(dist_info, 'WHEEL'), ["Wheel-Version: 1.0", "Tag: py2-none-any", "Tag: py3-none-any", ""].join(newline))

          expect(PythonWheelBundle.send(:installed_wheels, target)).to eql [["fake", "1.0", ["py2-none-any", "py3-none-any"]]]
        end
      end
    end

    # These run real uv with UV_OFFLINE against a file:// index the examples
    # build themselves, so they need uv but no network. The index serves the
    # wheels with their sha256 the way PyPI does, so uv.lock records a hash for
    # every wheel just as it would for a real plugin.
    describe "build and verify" do
      around(:each) do |example|
        skip "uv is not on PATH" unless system("which uv > /dev/null 2>&1")
        saved = ENV.to_h.slice('UV_OFFLINE', 'UV_CACHE_DIR')
        ENV['UV_OFFLINE'] = '1'
        ENV['UV_CACHE_DIR'] = File.join(@dir, 'uv_cache')
        example.run
      ensure
        ENV.delete('UV_OFFLINE')
        ENV.delete('UV_CACHE_DIR')
        ENV.update(saved) if saved
      end

      # Writes a minimal, valid wheel. Each tag segment may be a dotted
      # compressed set, e.g. "manylinux_2_17_x86_64.manylinux2014_x86_64".
      def make_wheel(dir, name, version, tag)
        python, abi, platform = tag.split('-')
        dist_info = "#{name}-#{version}.dist-info"
        tags = python.split('.').product(abi.split('.'), platform.split('.')).map { |t| "Tag: #{t.join('-')}\n" }.join
        files = {
          "#{name}/__init__.py" => "",
          "#{dist_info}/METADATA" => "Metadata-Version: 2.1\nName: #{name}\nVersion: #{version}\n",
          "#{dist_info}/WHEEL" => "Wheel-Version: 1.0\nGenerator: spec\nRoot-Is-Purelib: true\n#{tags}",
        }
        record = files.map do |path, data|
          digest = Base64.urlsafe_encode64(Digest::SHA256.digest(data)).delete('=')
          "#{path},sha256=#{digest},#{data.bytesize}\n"
        end.join + "#{dist_info}/RECORD,,\n"
        files["#{dist_info}/RECORD"] = record
        path = File.join(dir, "#{name}-#{version}-#{tag}.whl")
        Zip::File.open(path, create: true) do |zip|
          files.each { |entry, data| zip.get_output_stream(entry) { |f| f.write(data) } }
        end
        path
      end

      PURE = "fakepure-1.0-py3-none-any.whl"
      LINUX_X86 = "fakenative-1.0-py3-none-manylinux_2_17_x86_64.manylinux2014_x86_64.whl"
      LINUX_ARM = "fakenative-1.0-py3-none-manylinux_2_28_aarch64.whl"
      MAC_ARM = "fakenative-1.0-py3-none-macosx_11_0_arm64.whl"

      # Publishes the fixture wheels as a PEP 503 index and locks a plugin
      # against it.
      def locked_plugin(openc3_table)
        wheelhouse = File.join(@dir, 'wheelhouse')
        FileUtils.mkdir_p(wheelhouse)
        make_wheel(wheelhouse, 'fakepure', '1.0', 'py3-none-any')
        make_wheel(wheelhouse, 'fakenative', '1.0', 'py3-none-manylinux_2_17_x86_64.manylinux2014_x86_64')
        make_wheel(wheelhouse, 'fakenative', '1.0', 'py3-none-manylinux_2_28_aarch64')
        make_wheel(wheelhouse, 'fakenative', '1.0', 'py3-none-macosx_11_0_arm64')
        Dir[File.join(wheelhouse, '*.whl')].each do |wheel|
          name = File.basename(wheel).split('-')[0]
          page = File.join(@dir, 'simple', name, 'index.html')
          FileUtils.mkdir_p(File.dirname(page))
          File.open(page, 'a') do |f|
            f.puts "<a href=\"file://#{wheel}#sha256=#{Digest::SHA256.file(wheel).hexdigest}\">#{File.basename(wheel)}</a><br>"
          end
        end

        @plugin = File.join(@dir, 'plugin')
        FileUtils.mkdir_p(@plugin)
        File.write(File.join(@plugin, 'pyproject.toml'), <<~TOML)
          [project]
          name = "plugin"
          version = "0.0.0"
          requires-python = ">=3.11"
          dependencies = ["fakepure", "fakenative"]

          [tool.uv]
          package = false

          [[tool.uv.index]]
          name = "fixture"
          url = "file://#{File.join(@dir, 'simple')}"
          default = true

          [tool.openc3]
          #{openc3_table}
        TOML
        _, status = Open3.capture2e('uv', 'lock', chdir: @plugin)
        expect(status.success?).to be true
        @plugin
      end

      def bundled
        Dir[File.join(@plugin, PythonWheelBundle::WHEELS_DIR, '*.whl')].map { |f| File.basename(f) }.sort
      end

      it "bundles the lock's wheels for each target platform and nothing else" do
        plugin = locked_plugin(<<~TOML)
          offline_install = true
          python_platforms = ["x86_64-manylinux_2_28", "aarch64-manylinux_2_28"]
          python_version = "3.13"
        TOML

        PythonWheelBundle.build(plugin, out: StringIO.new)

        expect(bundled).to eql [LINUX_ARM, LINUX_X86, PURE].sort
        # Each file is the one uv.lock hashed, byte for byte
        bundled.each do |wheel|
          expect(Digest::SHA256.file(File.join(plugin, 'python_wheels', wheel)).hexdigest).to eql \
            Digest::SHA256.file(File.join(@dir, 'wheelhouse', wheel)).hexdigest
        end
        sums = File.read(File.join(plugin, 'python_wheels', 'SHA256SUMS'))
        expect(sums.lines.length).to eql 3
        expect(sums).to include("#{Digest::SHA256.file(File.join(@dir, 'wheelhouse', PURE)).hexdigest}  #{PURE}")
      end

      it "replaces wheels left over from an earlier build" do
        plugin = locked_plugin("offline_install = true\npython_platforms = [\"x86_64-manylinux_2_28\"]\npython_version = \"3.13\"\n")
        FileUtils.mkdir_p(File.join(plugin, 'python_wheels'))
        File.write(File.join(plugin, 'python_wheels', MAC_ARM), 'stale')

        PythonWheelBundle.build(plugin, out: StringIO.new)

        expect(bundled).to eql [LINUX_X86, PURE].sort
      end

      # cli bundlewheels and cli verifywheels both take a plugin directory
      # argument, and uv runs inside that directory
      it "builds and verifies a plugin given as a relative path" do
        locked_plugin("offline_install = true\n")

        Dir.chdir(@dir) do
          expect(PythonWheelBundle.build('plugin', out: StringIO.new)).to include(PURE)
          expect(PythonWheelBundle.verify('plugin', out: StringIO.new)).to be true
        end
      end

      # uv exports such a package as "name @ url", which --find-links can't
      # satisfy, so a deployment with no network could never install it
      it "rejects a package locked from a direct reference" do
        plugin = locked_plugin("offline_install = true\n")
        pyproject = File.join(plugin, 'pyproject.toml')
        direct = "fakepure @ file://#{File.join(@dir, 'wheelhouse', PURE)}"
        File.write(pyproject, File.read(pyproject).sub('dependencies = ["fakepure", "fakenative"]', "dependencies = [\"#{direct}\"]"))
        _, status = Open3.capture2e('uv', 'lock', chdir: plugin)
        expect(status.success?).to be true

        expect { PythonWheelBundle.build(plugin, out: StringIO.new) }.to raise_error(PythonWheelBundle::Error, /locks fakepure \((url|path)\) from a direct source/)
      end

      it "requires a uv.lock" do
        plugin = locked_plugin("offline_install = true\n")
        File.delete(File.join(plugin, 'uv.lock'))

        expect { PythonWheelBundle.build(plugin, out: StringIO.new) }.to raise_error(PythonWheelBundle::Error, /requires a uv.lock/)
      end

      describe "lock" do
        it "writes uv.lock so the plugin builds" do
          plugin = locked_plugin("offline_install = true\n")
          File.delete(File.join(plugin, 'uv.lock'))
          out = StringIO.new

          PythonWheelBundle.lock(plugin, out: out)

          expect(out.string).to start_with("uv lock\n")
          expect(File.exist?(File.join(plugin, 'uv.lock'))).to be true
          expect(PythonWheelBundle.build(plugin, out: StringIO.new)).to include(PURE)
        end

        it "brings a lock that is out of date with pyproject.toml up to date" do
          plugin = locked_plugin("offline_install = true\n")
          pyproject = File.join(plugin, 'pyproject.toml')
          File.write(pyproject, File.read(pyproject).sub('dependencies = ["fakepure", "fakenative"]', 'dependencies = ["fakepure"]'))
          expect { PythonWheelBundle.build(plugin, out: StringIO.new) }.to raise_error(PythonWheelBundle::Error, /out of date/)

          PythonWheelBundle.lock(plugin, out: StringIO.new)

          expect(PythonWheelBundle.build(plugin, out: StringIO.new)).to eql [PURE]
        end

        it "passes the upgrade options to uv" do
          plugin = locked_plugin("offline_install = true\n")
          out = StringIO.new

          PythonWheelBundle.lock(plugin, upgrade: true, upgrade_packages: ['fakepure', 'fakenative'], out: out)

          expect(out.string).to start_with("uv lock --upgrade --upgrade-package fakepure --upgrade-package fakenative\n")
        end

        it "requires a pyproject.toml" do
          expect { PythonWheelBundle.lock(@dir, out: StringIO.new) }.to raise_error(PythonWheelBundle::Error, /has no pyproject.toml/)
        end

        it "reports a failed lock" do
          plugin = locked_plugin("offline_install = true\n")
          pyproject = File.join(plugin, 'pyproject.toml')
          File.write(pyproject, File.read(pyproject).sub('dependencies = ["fakepure", "fakenative"]', 'dependencies = ["notapackage"]'))
          out = StringIO.new

          expect { PythonWheelBundle.lock(plugin, out: out) }.to raise_error(PythonWheelBundle::Error, /uv lock failed/)
          expect(out.string).to include("notapackage")
        end
      end

      it "requires the uv.lock to match pyproject.toml" do
        plugin = locked_plugin("offline_install = true\n")
        pyproject = File.join(plugin, 'pyproject.toml')
        File.write(pyproject, File.read(pyproject).sub('dependencies = ["fakepure", "fakenative"]', 'dependencies = ["fakepure"]'))

        expect { PythonWheelBundle.build(plugin, out: StringIO.new) }.to raise_error(PythonWheelBundle::Error, /uv.lock is out of date/)
      end

      it "names the target platform that has no compatible wheel" do
        plugin = locked_plugin("offline_install = true\npython_platforms = [\"x86_64-pc-windows-msvc\"]\npython_version = \"3.13\"\n")

        expect { PythonWheelBundle.build(plugin, out: StringIO.new) }.to raise_error(PythonWheelBundle::Error, /x86_64-pc-windows-msvc.*fakenative/m)
      end

      it "removes bundled wheels when offline_install is off" do
        plugin = locked_plugin("offline_install = false\n")
        FileUtils.mkdir_p(File.join(plugin, 'python_wheels'))
        File.write(File.join(plugin, 'python_wheels', PURE), 'stale')

        expect(PythonWheelBundle.build(plugin, out: StringIO.new)).to eql []
        expect(File.exist?(File.join(plugin, 'python_wheels'))).to be false
      end

      describe "verify" do
        TARGETS = <<~TOML.freeze
          offline_install = true
          python_platforms = ["x86_64-manylinux_2_28", "aarch64-manylinux_2_28"]
          python_version = "3.13"
        TOML

        # Packages the plugin the way its gemspec does, so verify reads a real gem
        def package_gem(plugin)
          spec = Gem::Specification.new do |s|
            s.name = 'plugin'
            s.version = '1.0.0'
            s.summary = 'plugin'
            s.authors = ['spec']
            s.files = Dir.chdir(plugin) { Dir.glob('{pyproject.toml,uv.lock,python_wheels/*}') }
          end
          File.join(plugin, Dir.chdir(plugin) { Gem::Package.build(spec) })
        end

        def verify(path, **kwargs)
          @report = StringIO.new
          PythonWheelBundle.verify(path, out: @report, **kwargs)
        end

        it "reports which bundled wheel serves each package on each target" do
          plugin = locked_plugin(TARGETS)
          PythonWheelBundle.build(plugin, out: StringIO.new)

          expect(verify(package_gem(plugin))).to be true
          report = @report.string
          expect(report).to include("x86_64-manylinux_2_28 / Python 3.13", "aarch64-manylinux_2_28 / Python 3.13")
          expect(report).to match(/fakenative +1\.0 +#{Regexp.escape(LINUX_X86)} +OK/)
          expect(report).to match(/fakenative +1\.0 +#{Regexp.escape(LINUX_ARM)} +OK/)
          expect(report).to match(/fakepure +1\.0 +#{Regexp.escape(PURE)} +OK/)
          expect(report).to include("PASS")
        end

        it "fails on a bundled wheel that differs from uv.lock" do
          plugin = locked_plugin(TARGETS)
          PythonWheelBundle.build(plugin, out: StringIO.new)
          File.open(File.join(plugin, 'python_wheels', PURE), 'ab') { |f| f.write('tampered') }

          expect(verify(plugin)).to be false
          expect(@report.string).to match(/#{Regexp.escape(PURE)} +HASH MISMATCH/)
          expect(@report.string).to include("FAIL")
        end

        it "names the target a missing wheel breaks" do
          plugin = locked_plugin(TARGETS)
          PythonWheelBundle.build(plugin, out: StringIO.new)
          File.delete(File.join(plugin, 'python_wheels', LINUX_ARM))

          expect(verify(plugin)).to be false
          expect(@report.string).to match(/aarch64-manylinux_2_28 \/ Python 3.13.*FAIL.*fakenative/m)
          expect(@report.string).to match(/x86_64-manylinux_2_28 \/ Python 3.13 +PASS/)
        end

        it "checks a deployment target given on the command line instead" do
          plugin = locked_plugin(TARGETS)
          PythonWheelBundle.build(plugin, out: StringIO.new)

          expect(verify(plugin, python_platforms: ["aarch64-apple-darwin"], python_version: "3.13")).to be false
          expect(@report.string).to match(/aarch64-apple-darwin \/ Python 3.13.*FAIL/m)
        end

        it "rejects a --python-version older than requires-python" do
          plugin = locked_plugin(TARGETS)
          PythonWheelBundle.build(plugin, out: StringIO.new)

          expect { verify(plugin, python_platforms: ["x86_64-manylinux_2_28"], python_version: "3.10") }.to \
            raise_error(PythonWheelBundle::Error, /python_version 3.10 is older than the plugin's requires-python/)
        end

        it "fails a gem that does not set offline_install" do
          plugin = locked_plugin("offline_install = false\n")

          expect(verify(plugin)).to be false
          expect(@report.string).to include("does not set [tool.openc3] offline_install")
        end
      end
    end
  end
end

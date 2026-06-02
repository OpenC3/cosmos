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
require 'openc3/models/python_package_model'

module OpenC3
  describe PythonPackageModel do
    describe ".names" do
      before(:each) do
        allow(PythonPackageModel).to receive(:cached_packages).and_return([])
      end

      it "returns empty hash when no cache or plugin venvs exist" do
        allow(File).to receive(:directory?).with(PythonPackageModel::PLUGIN_VENVS_DIR).and_return(false)
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('PYTHONUSERBASE').and_return(nil)

        result = PythonPackageModel.names
        expect(result).to eq({})
      end

      it "includes cached packages under 'cached' key when present" do
        allow(PythonPackageModel).to receive(:cached_packages).and_return(["numpy-2.4.6", "requests-2.34.2"])
        allow(File).to receive(:directory?).with(PythonPackageModel::PLUGIN_VENVS_DIR).and_return(false)
        allow(PythonPackageModel).to receive(:shared_venv_packages).and_return([])

        result = PythonPackageModel.names
        expect(result["cached"]).to eq(["numpy-2.4.6", "requests-2.34.2"])
      end

      it "omits cached key when UV cache has no packages" do
        allow(File).to receive(:directory?).with(PythonPackageModel::PLUGIN_VENVS_DIR).and_return(false)
        allow(PythonPackageModel).to receive(:shared_venv_packages).and_return([])

        result = PythonPackageModel.names
        expect(result).not_to have_key("cached")
      end

      it "places cached key before plugin keys" do
        allow(PythonPackageModel).to receive(:cached_packages).and_return(["numpy-2.0.0"])
        allow(File).to receive(:directory?).with(PythonPackageModel::PLUGIN_VENVS_DIR).and_return(true)
        allow(Dir).to receive(:glob).with("#{PythonPackageModel::PLUGIN_VENVS_DIR}/*/").and_return(
          ["/gems/plugin_venvs/demo/"]
        )
        allow(File).to receive(:directory?).with("/gems/plugin_venvs/demo/.venv").and_return(true)
        allow(PythonPackageModel).to receive(:packages_in_venv).with("/gems/plugin_venvs/demo/.venv").and_return(["requests-2.31.0"])
        allow(PythonPackageModel).to receive(:shared_venv_packages).and_return([])

        result = PythonPackageModel.names
        expect(result.keys.first).to eq("cached")
      end

      it "collects packages from per-plugin venvs" do
        allow(File).to receive(:directory?).with(PythonPackageModel::PLUGIN_VENVS_DIR).and_return(true)
        allow(Dir).to receive(:glob).with("#{PythonPackageModel::PLUGIN_VENVS_DIR}/*/").and_return(
          ["/gems/plugin_venvs/demo/", "/gems/plugin_venvs/other/"]
        )

        # demo plugin has a .venv with packages
        allow(File).to receive(:directory?).with("/gems/plugin_venvs/demo/.venv").and_return(true)
        allow(PythonPackageModel).to receive(:packages_in_venv).with("/gems/plugin_venvs/demo/.venv").and_return(["numpy-2.0.0", "requests-2.31.0"])

        # other plugin has a .venv with packages
        allow(File).to receive(:directory?).with("/gems/plugin_venvs/other/.venv").and_return(true)
        allow(PythonPackageModel).to receive(:packages_in_venv).with("/gems/plugin_venvs/other/.venv").and_return(["boto3-1.28.0"])

        allow(PythonPackageModel).to receive(:shared_venv_packages).and_return([])

        result = PythonPackageModel.names
        expect(result["demo"]).to eq(["numpy-2.0.0", "requests-2.31.0"])
        expect(result["other"]).to eq(["boto3-1.28.0"])
      end

      it "includes shared venv packages under 'shared' key when present" do
        allow(File).to receive(:directory?).with(PythonPackageModel::PLUGIN_VENVS_DIR).and_return(false)
        allow(PythonPackageModel).to receive(:shared_venv_packages).and_return(["requests-2.31.0", "flask-3.0.0"])

        result = PythonPackageModel.names
        expect(result["shared"]).to eq(["flask-3.0.0", "requests-2.31.0"])
      end

      it "omits shared key when shared venv has no packages" do
        allow(File).to receive(:directory?).with(PythonPackageModel::PLUGIN_VENVS_DIR).and_return(false)
        allow(PythonPackageModel).to receive(:shared_venv_packages).and_return([])

        result = PythonPackageModel.names
        expect(result).not_to have_key("shared")
      end

      it "skips plugin dirs that lack a .venv subdirectory" do
        allow(File).to receive(:directory?).with(PythonPackageModel::PLUGIN_VENVS_DIR).and_return(true)
        allow(Dir).to receive(:glob).with("#{PythonPackageModel::PLUGIN_VENVS_DIR}/*/").and_return(
          ["/gems/plugin_venvs/incomplete/"]
        )
        allow(File).to receive(:directory?).with("/gems/plugin_venvs/incomplete/.venv").and_return(false)
        allow(PythonPackageModel).to receive(:shared_venv_packages).and_return([])

        result = PythonPackageModel.names
        expect(result).not_to have_key("incomplete")
      end
    end

    describe ".system_venv_packages" do
      it "delegates to packages_in_venv with SYSTEM_VENV_DIR" do
        expect(PythonPackageModel).to receive(:packages_in_venv).with(PythonPackageModel::SYSTEM_VENV_DIR).and_return(["boto3-1.36.13"])
        result = PythonPackageModel.system_venv_packages
        expect(result).to eq(["boto3-1.36.13"])
      end
    end

    describe ".cached_packages" do
      it "returns empty array when UV cache directory does not exist" do
        allow(ENV).to receive(:fetch).with('UV_CACHE_DIR', PythonPackageModel::DEFAULT_UV_CACHE_DIR).and_return('/gems/uv')
        allow(File).to receive(:directory?).with('/gems/uv').and_return(false)

        result = PythonPackageModel.cached_packages
        expect(result).to eq([])
      end

      it "extracts package names and versions from cached wheel entries" do
        allow(ENV).to receive(:fetch).with('UV_CACHE_DIR', PythonPackageModel::DEFAULT_UV_CACHE_DIR).and_return('/gems/uv')
        allow(File).to receive(:directory?).with('/gems/uv').and_return(true)
        allow(File).to receive(:directory?).with('/gems/uv/uploads').and_return(false)
        allow(Dir).to receive(:glob).with("/gems/uv/wheels-v*/*/*/*").and_return([
          "/gems/uv/wheels-v6/pypi/numpy/2.4.6-cp312-cp312-musllinux_1_2_aarch64",
          "/gems/uv/wheels-v6/pypi/numpy/2.4.6-cp312-cp312-musllinux_1_2_aarch64.http",
          "/gems/uv/wheels-v6/pypi/requests/2.34.2-py3-none-any",
          "/gems/uv/wheels-v6/pypi/requests/2.34.2-py3-none-any.http",
          "/gems/uv/wheels-v6/pypi/boto3/1.43.17-py3-none-any",
        ])

        result = PythonPackageModel.cached_packages
        expect(result).to contain_exactly("numpy-2.4.6", "requests-2.34.2", "boto3-1.43.17")
      end

      it "normalizes underscores to hyphens and lowercases package directory names" do
        allow(ENV).to receive(:fetch).with('UV_CACHE_DIR', PythonPackageModel::DEFAULT_UV_CACHE_DIR).and_return('/gems/uv')
        allow(File).to receive(:directory?).with('/gems/uv').and_return(true)
        allow(File).to receive(:directory?).with('/gems/uv/uploads').and_return(false)
        allow(Dir).to receive(:glob).with("/gems/uv/wheels-v*/*/*/*").and_return([
          "/gems/uv/wheels-v6/pypi/typing_extensions/4.15.0-py3-none-any",
        ])

        result = PythonPackageModel.cached_packages
        expect(result).to eq(["typing-extensions-4.15.0"])
      end

      it "deduplicates multiple platform variants and lists multiple versions" do
        allow(ENV).to receive(:fetch).with('UV_CACHE_DIR', PythonPackageModel::DEFAULT_UV_CACHE_DIR).and_return('/gems/uv')
        allow(File).to receive(:directory?).with('/gems/uv').and_return(true)
        allow(File).to receive(:directory?).with('/gems/uv/uploads').and_return(false)
        allow(Dir).to receive(:glob).with("/gems/uv/wheels-v*/*/*/*").and_return([
          "/gems/uv/wheels-v6/pypi/numpy/2.4.6-cp312-cp312-musllinux_1_2_aarch64",
          "/gems/uv/wheels-v6/pypi/numpy/2.4.4-cp312-cp312-musllinux_1_2_aarch64",
        ])

        result = PythonPackageModel.cached_packages
        expect(result).to contain_exactly("numpy-2.4.6", "numpy-2.4.4")
      end

      it "skips metadata files with dots in the basename" do
        allow(ENV).to receive(:fetch).with('UV_CACHE_DIR', PythonPackageModel::DEFAULT_UV_CACHE_DIR).and_return('/gems/uv')
        allow(File).to receive(:directory?).with('/gems/uv').and_return(true)
        allow(File).to receive(:directory?).with('/gems/uv/uploads').and_return(false)
        allow(Dir).to receive(:glob).with("/gems/uv/wheels-v*/*/*/*").and_return([
          "/gems/uv/wheels-v6/pypi/boto3/1.43.17-py3-none-any",
          "/gems/uv/wheels-v6/pypi/boto3/1.43.17-py3-none-any.http",
          "/gems/uv/wheels-v6/pypi/boto3/1.43.17-py3-none-any.msgpack",
        ])

        result = PythonPackageModel.cached_packages
        expect(result).to eq(["boto3-1.43.17"])
      end

      it "includes uploaded wheels from the uploads directory" do
        allow(ENV).to receive(:fetch).with('UV_CACHE_DIR', PythonPackageModel::DEFAULT_UV_CACHE_DIR).and_return('/gems/uv')
        allow(File).to receive(:directory?).with('/gems/uv').and_return(true)
        allow(Dir).to receive(:glob).with("/gems/uv/wheels-v*/*/*/*").and_return([])
        allow(File).to receive(:directory?).with('/gems/uv/uploads').and_return(true)
        allow(Dir).to receive(:glob).with("/gems/uv/uploads/*.whl").and_return([
          "/gems/uv/uploads/my_custom_lib-1.0.0-py3-none-any.whl",
        ])

        result = PythonPackageModel.cached_packages
        expect(result).to eq(["my-custom-lib-1.0.0"])
      end

      it "deduplicates uploaded wheels against UV cache entries" do
        allow(ENV).to receive(:fetch).with('UV_CACHE_DIR', PythonPackageModel::DEFAULT_UV_CACHE_DIR).and_return('/gems/uv')
        allow(File).to receive(:directory?).with('/gems/uv').and_return(true)
        allow(Dir).to receive(:glob).with("/gems/uv/wheels-v*/*/*/*").and_return([
          "/gems/uv/wheels-v6/pypi/numpy/2.4.6-cp312-cp312-musllinux_1_2_aarch64",
        ])
        allow(File).to receive(:directory?).with('/gems/uv/uploads').and_return(true)
        allow(Dir).to receive(:glob).with("/gems/uv/uploads/*.whl").and_return([
          "/gems/uv/uploads/numpy-2.4.6-cp312-cp312-musllinux_1_2_aarch64.whl",
        ])

        result = PythonPackageModel.cached_packages
        expect(result).to eq(["numpy-2.4.6"])
      end

      it "skips non-wheel files in uploads directory" do
        allow(ENV).to receive(:fetch).with('UV_CACHE_DIR', PythonPackageModel::DEFAULT_UV_CACHE_DIR).and_return('/gems/uv')
        allow(File).to receive(:directory?).with('/gems/uv').and_return(true)
        allow(Dir).to receive(:glob).with("/gems/uv/wheels-v*/*/*/*").and_return([])
        allow(File).to receive(:directory?).with('/gems/uv/uploads').and_return(true)
        allow(Dir).to receive(:glob).with("/gems/uv/uploads/*.whl").and_return([])

        result = PythonPackageModel.cached_packages
        expect(result).to eq([])
      end

      it "skips uploads directory when it does not exist" do
        allow(ENV).to receive(:fetch).with('UV_CACHE_DIR', PythonPackageModel::DEFAULT_UV_CACHE_DIR).and_return('/gems/uv')
        allow(File).to receive(:directory?).with('/gems/uv').and_return(true)
        allow(Dir).to receive(:glob).with("/gems/uv/wheels-v*/*/*/*").and_return([
          "/gems/uv/wheels-v6/pypi/requests/2.34.2-py3-none-any",
        ])
        allow(File).to receive(:directory?).with('/gems/uv/uploads').and_return(false)

        result = PythonPackageModel.cached_packages
        expect(result).to eq(["requests-2.34.2"])
      end
    end

    describe ".parse_wheel_filename" do
      it "parses a standard wheel filename" do
        result = PythonPackageModel.parse_wheel_filename("numpy-2.4.6-cp312-cp312-musllinux_1_2_aarch64.whl")
        expect(result).to eq(["numpy", "2.4.6"])
      end

      it "normalizes underscores to hyphens in package name" do
        result = PythonPackageModel.parse_wheel_filename("my_custom_lib-1.0.0-py3-none-any.whl")
        expect(result).to eq(["my-custom-lib", "1.0.0"])
      end

      it "handles browser-appended duplicate suffixes" do
        result = PythonPackageModel.parse_wheel_filename("numpy-2.4.6-cp312-cp312-musllinux_1_2_aarch64 (1).whl")
        expect(result).to eq(["numpy", "2.4.6"])
      end

      it "returns nil for non-wheel files" do
        expect(PythonPackageModel.parse_wheel_filename("requests-2.31.0.tar.gz")).to be_nil
      end

      it "returns nil for malformed wheel names with too few segments" do
        expect(PythonPackageModel.parse_wheel_filename("bad-name.whl")).to be_nil
      end

      it "returns nil when version does not start with a digit" do
        expect(PythonPackageModel.parse_wheel_filename("pkg-abc-py3-none-any.whl")).to be_nil
      end
    end

    describe ".packages_in_venv" do
      it "finds .dist-info directories and returns package names" do
        venv_dir = "/gems/plugin_venvs/demo/.venv"
        site_packages = "#{venv_dir}/lib/python3.12/site-packages"

        allow(Dir).to receive(:glob).with("#{venv_dir}/lib/*/site-packages").and_return([site_packages])
        allow(File).to receive(:directory?).with(site_packages).and_return(true)

        numpy_dist = Pathname.new("#{site_packages}/numpy-2.0.0.dist-info")
        requests_dist = Pathname.new("#{site_packages}/requests-2.31.0.dist-info")
        some_package = Pathname.new("#{site_packages}/numpy")

        allow(Pathname).to receive(:new).with(site_packages).and_return(double("pathname", children: [numpy_dist, requests_dist, some_package]))
        allow(numpy_dist).to receive(:directory?).and_return(true)
        allow(requests_dist).to receive(:directory?).and_return(true)
        allow(some_package).to receive(:directory?).and_return(true)

        result = PythonPackageModel.packages_in_venv(venv_dir)
        expect(result).to contain_exactly("numpy-2.0.0", "requests-2.31.0")
      end

      it "returns empty array for venv with no packages" do
        venv_dir = "/gems/plugin_venvs/empty/.venv"
        allow(Dir).to receive(:glob).with("#{venv_dir}/lib/*/site-packages").and_return([])

        result = PythonPackageModel.packages_in_venv(venv_dir)
        expect(result).to eq([])
      end
    end

    describe ".shared_venv_packages" do
      it "reads from PYTHONUSERBASE environment variable" do
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch).with('PYTHONUSERBASE', nil).and_return('/gems/python_packages')

        site_packages = "/gems/python_packages/lib/python3.12/site-packages"
        allow(Dir).to receive(:glob).with("/gems/python_packages/lib/*").and_return(["/gems/python_packages/lib/python3.12"])
        allow(File).to receive(:directory?).with(site_packages).and_return(true)

        requests_dist = Pathname.new("#{site_packages}/requests-2.31.0.dist-info")
        allow(Pathname).to receive(:new).with(site_packages).and_return(double("pathname", children: [requests_dist]))
        allow(requests_dist).to receive(:directory?).and_return(true)

        result = PythonPackageModel.shared_venv_packages
        expect(result).to eq(["requests-2.31.0"])
      end

      it "returns empty array when PYTHONUSERBASE is nil" do
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch).with('PYTHONUSERBASE', nil).and_return(nil)

        result = PythonPackageModel.shared_venv_packages
        expect(result).to eq([])
      end
    end

    describe ".put" do
      before(:each) do
        @temp_dir = Dir.mktmpdir
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('PYTHONUSERBASE').and_return(@temp_dir)
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch).with('UV_CACHE_DIR', PythonPackageModel::DEFAULT_UV_CACHE_DIR).and_return(@temp_dir)
      end

      after(:each) do
        FileUtils.remove_entry_secure(@temp_dir)
      end

      it "copies .whl files to the UV uploads directory" do
        whl_file = File.join(@temp_dir, "my_lib-1.0.0-py3-none-any.whl")
        File.write(whl_file, "fake wheel content")
        allow(PythonPackageModel).to receive(:install).and_return("process_name")

        PythonPackageModel.put(whl_file, scope: "DEFAULT")

        uploads_path = File.join(@temp_dir, PythonPackageModel::UPLOADS_DIR_NAME, "my_lib-1.0.0-py3-none-any.whl")
        expect(File.exist?(uploads_path)).to be true
      end

      it "does not copy non-whl files to the uploads directory" do
        tar_file = File.join(@temp_dir, "my_lib-1.0.0.tar.gz")
        File.write(tar_file, "fake tarball content")
        allow(PythonPackageModel).to receive(:install).and_return("process_name")

        PythonPackageModel.put(tar_file, scope: "DEFAULT")

        uploads_dir = File.join(@temp_dir, PythonPackageModel::UPLOADS_DIR_NAME)
        expect(File.directory?(uploads_dir)).to be false
      end

      it "raises when the package file does not exist" do
        allow(OpenC3::Logger).to receive(:error)
        expect { PythonPackageModel.put("/nonexistent/file.whl", scope: "DEFAULT") }.to raise_error(/does not exist/)
      end

      it "forwards plugin parameter to install" do
        whl_file = File.join(@temp_dir, "my_lib-1.0.0-py3-none-any.whl")
        File.write(whl_file, "fake wheel content")
        expect(PythonPackageModel).to receive(:install).with(anything, scope: "DEFAULT", plugin: "demo").and_return("process_name")

        PythonPackageModel.put(whl_file, scope: "DEFAULT", plugin: "demo")
      end
    end

    describe ".install" do
      before(:each) do
        @temp_dir = Dir.mktmpdir
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('PYTHONUSERBASE').and_return(@temp_dir)
        allow(ENV).to receive(:[]).with('PIP_ENABLE_TRUSTED_HOST').and_return(nil)
        allow(ENV).to receive(:[]).with('PYPI_URL').and_return(nil)
        allow(OpenC3::Logger).to receive(:info)
      end

      after(:each) do
        FileUtils.remove_entry_secure(@temp_dir)
      end

      it "sets PIPINSTALL_VENV when plugin is provided" do
        pkg_file = File.join(@temp_dir, "my_lib-1.0.0.tar.gz")
        File.write(pkg_file, "fake")

        process_double = double("process", name: "process_123")
        pm = double("process_manager")
        allow(OpenC3::ProcessManager).to receive(:instance).and_return(pm)
        allow(PythonPackageModel).to receive(:get_setting).and_raise("no redis")

        expect(pm).to receive(:spawn) do |cmd, type, detail, expires, **kw|
          expect(kw[:env]).to eq({ 'PIPINSTALL_VENV' => '/gems/plugin_venvs/demo/.venv' })
          process_double
        end

        PythonPackageModel.install(pkg_file, scope: "DEFAULT", plugin: "demo")
      end

      it "passes empty env hash when plugin is nil" do
        pkg_file = File.join(@temp_dir, "my_lib-1.0.0.tar.gz")
        File.write(pkg_file, "fake")

        process_double = double("process", name: "process_123")
        pm = double("process_manager")
        allow(OpenC3::ProcessManager).to receive(:instance).and_return(pm)
        allow(PythonPackageModel).to receive(:get_setting).and_raise("no redis")

        expect(pm).to receive(:spawn) do |cmd, type, detail, expires, **kw|
          expect(kw[:env]).to eq({})
          process_double
        end

        PythonPackageModel.install(pkg_file, scope: "DEFAULT")
      end

      it "resolves pypi_url from get_setting" do
        pkg_file = File.join(@temp_dir, "my_lib-1.0.0.tar.gz")
        File.write(pkg_file, "fake")

        process_double = double("process", name: "process_123")
        pm = double("process_manager")
        allow(OpenC3::ProcessManager).to receive(:instance).and_return(pm)
        allow(PythonPackageModel).to receive(:get_setting).with('pypi_url', scope: "DEFAULT").and_return("https://custom.pypi.example.com")

        expect(pm).to receive(:spawn) do |cmd, type, detail, expires, **kw|
          expect(cmd).to include("-i")
          expect(cmd).to include("https://custom.pypi.example.com/simple")
          process_double
        end

        PythonPackageModel.install(pkg_file, scope: "DEFAULT")
      end

      it "falls back to ENV PYPI_URL when get_setting raises" do
        pkg_file = File.join(@temp_dir, "my_lib-1.0.0.tar.gz")
        File.write(pkg_file, "fake")

        allow(ENV).to receive(:[]).with('PYPI_URL').and_return("https://env.pypi.example.com")

        process_double = double("process", name: "process_123")
        pm = double("process_manager")
        allow(OpenC3::ProcessManager).to receive(:instance).and_return(pm)
        allow(PythonPackageModel).to receive(:get_setting).and_raise("no redis")

        expect(pm).to receive(:spawn) do |cmd, type, detail, expires, **kw|
          expect(cmd).to include("https://env.pypi.example.com/simple")
          process_double
        end

        PythonPackageModel.install(pkg_file, scope: "DEFAULT")
      end

      it "falls back to pypi.org/simple when get_setting raises and ENV is nil" do
        pkg_file = File.join(@temp_dir, "my_lib-1.0.0.tar.gz")
        File.write(pkg_file, "fake")

        process_double = double("process", name: "process_123")
        pm = double("process_manager")
        allow(OpenC3::ProcessManager).to receive(:instance).and_return(pm)
        allow(PythonPackageModel).to receive(:get_setting).and_raise("no redis")

        expect(pm).to receive(:spawn) do |cmd, type, detail, expires, **kw|
          expect(cmd).to include("https://pypi.org/simple")
          process_double
        end

        PythonPackageModel.install(pkg_file, scope: "DEFAULT")
      end
    end

    describe ".destroy" do
      before(:each) do
        allow(OpenC3::Logger).to receive(:info)
      end

      it "sets PIPINSTALL_VENV when plugin is provided" do
        process_double = double("process", name: "process_123")
        pm = double("process_manager")
        allow(OpenC3::ProcessManager).to receive(:instance).and_return(pm)

        expect(pm).to receive(:spawn) do |cmd, type, detail, expires, **kw|
          expect(kw[:env]).to eq({ 'PIPINSTALL_VENV' => '/gems/plugin_venvs/demo/.venv' })
          expect(cmd).to include("my-package")
          process_double
        end

        PythonPackageModel.destroy("my-package-1.0.0", scope: "DEFAULT", plugin: "demo")
      end

      it "passes empty env hash when plugin is nil" do
        process_double = double("process", name: "process_123")
        pm = double("process_manager")
        allow(OpenC3::ProcessManager).to receive(:instance).and_return(pm)

        expect(pm).to receive(:spawn) do |cmd, type, detail, expires, **kw|
          expect(kw[:env]).to eq({})
          process_double
        end

        PythonPackageModel.destroy("my-package-1.0.0", scope: "DEFAULT")
      end
    end

    describe ".trees" do
      it "calls uv pip list for each plugin venv and returns output keyed by plugin name" do
        allow(File).to receive(:directory?).with(PythonPackageModel::PLUGIN_VENVS_DIR).and_return(true)
        allow(Dir).to receive(:glob).with("#{PythonPackageModel::PLUGIN_VENVS_DIR}/*/").and_return(
          ["/gems/plugin_venvs/demo/"]
        )
        allow(File).to receive(:directory?).with("/gems/plugin_venvs/demo/.venv").and_return(true)

        uv_output = "Package    Version\n---------- -------\nnumpy      2.0.0\nrequests   2.31.0"
        status = double("status", success?: true)
        allow(Open3).to receive(:capture2).with('uv', 'pip', 'list', '--python', '/gems/plugin_venvs/demo/.venv').and_return([uv_output, status])

        result = PythonPackageModel.trees
        expect(result["demo"]).to eq(uv_output)
      end

      it "skips venvs where uv pip list fails" do
        allow(File).to receive(:directory?).with(PythonPackageModel::PLUGIN_VENVS_DIR).and_return(true)
        allow(Dir).to receive(:glob).with("#{PythonPackageModel::PLUGIN_VENVS_DIR}/*/").and_return(
          ["/gems/plugin_venvs/broken/"]
        )
        allow(File).to receive(:directory?).with("/gems/plugin_venvs/broken/.venv").and_return(true)

        status = double("status", success?: false)
        allow(Open3).to receive(:capture2).with('uv', 'pip', 'list', '--python', '/gems/plugin_venvs/broken/.venv').and_return(["", status])

        result = PythonPackageModel.trees
        expect(result).to be_empty
      end

      it "returns empty hash when plugin venvs directory does not exist" do
        allow(File).to receive(:directory?).with(PythonPackageModel::PLUGIN_VENVS_DIR).and_return(false)

        result = PythonPackageModel.trees
        expect(result).to eq({})
      end
    end
  end
end

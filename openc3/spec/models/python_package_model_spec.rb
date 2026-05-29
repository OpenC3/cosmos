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
        allow(Dir).to receive(:glob).with("/gems/uv/wheels-v*/*/*/*").and_return([
          "/gems/uv/wheels-v6/pypi/typing_extensions/4.15.0-py3-none-any",
        ])

        result = PythonPackageModel.cached_packages
        expect(result).to eq(["typing-extensions-4.15.0"])
      end

      it "deduplicates multiple platform variants and lists multiple versions" do
        allow(ENV).to receive(:fetch).with('UV_CACHE_DIR', PythonPackageModel::DEFAULT_UV_CACHE_DIR).and_return('/gems/uv')
        allow(File).to receive(:directory?).with('/gems/uv').and_return(true)
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
        allow(Dir).to receive(:glob).with("/gems/uv/wheels-v*/*/*/*").and_return([
          "/gems/uv/wheels-v6/pypi/boto3/1.43.17-py3-none-any",
          "/gems/uv/wheels-v6/pypi/boto3/1.43.17-py3-none-any.http",
          "/gems/uv/wheels-v6/pypi/boto3/1.43.17-py3-none-any.msgpack",
        ])

        result = PythonPackageModel.cached_packages
        expect(result).to eq(["boto3-1.43.17"])
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
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('PYTHONUSERBASE').and_return('/gems/python_packages')

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
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('PYTHONUSERBASE').and_return(nil)

        result = PythonPackageModel.shared_venv_packages
        expect(result).to eq([])
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

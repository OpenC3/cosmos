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
require "openc3/utilities/pypi_url"

module OpenC3
  describe PypiUrl do
    describe ".validate" do
      context "with a valid http(s) url" do
        it "returns https urls unchanged" do
          url = "https://pypi.org/simple"
          expect(PypiUrl.validate(url)).to eql url
        end

        it "returns http urls unchanged" do
          url = "http://pypi.example.com/simple"
          expect(PypiUrl.validate(url)).to eql url
        end

        it "allows a host with a port" do
          url = "http://localhost:8080/simple"
          expect(PypiUrl.validate(url)).to eql url
        end

        it "does not log an error" do
          expect(Logger).to_not receive(:error)
          PypiUrl.validate("https://pypi.org/simple")
        end
      end

      context "with an invalid url" do
        # Shell metacharacters that previously enabled command injection
        it "rejects a value containing shell metacharacters" do
          expect(Logger).to receive(:error)
          payload = "https://pypi.org ; id > /tmp/PWNED ; #"
          expect(PypiUrl.validate(payload)).to eql PypiUrl::DEFAULT
        end

        it "rejects a non-http(s) scheme" do
          expect(Logger).to receive(:error)
          expect(PypiUrl.validate("ftp://example.com/simple")).to eql PypiUrl::DEFAULT
        end

        it "rejects a url with no host" do
          expect(Logger).to receive(:error)
          expect(PypiUrl.validate("https:///simple")).to eql PypiUrl::DEFAULT
        end

        it "rejects a value that is not a url" do
          expect(Logger).to receive(:error)
          expect(PypiUrl.validate("not a url")).to eql PypiUrl::DEFAULT
        end

        it "rejects an empty string" do
          expect(Logger).to receive(:error)
          expect(PypiUrl.validate("")).to eql PypiUrl::DEFAULT
        end
      end
    end

    describe "self.build_args" do
      before(:each) do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with(PypiUrl::INSECURE_HOST_ENV).and_return(nil)
        allow(ENV).to receive(:[]).with(PypiUrl::DEPRECATED_INSECURE_HOST_ENV).and_return(nil)
      end

      # uv deprecated -i/--index-url in favor of --default-index on both
      # `uv sync` and `uv pip install`, and every COSMOS install path runs uv
      # (openc3/bin/pipinstall is a uv pip install wrapper).
      it "uses the non deprecated uv index option" do
        expect(PypiUrl.build_args("https://pypi.org/simple")).to eql ["--default-index", "https://pypi.org/simple"]
      end

      it "does not allow an insecure host by default" do
        expect(PypiUrl.build_args("https://private.example.com/simple")).to_not include "--allow-insecure-host"
      end

      # --trusted-host is only an undocumented uv alias, so the real uv option
      # is used instead.
      it "allows an insecure host when opted in" do
        allow(ENV).to receive(:[]).with(PypiUrl::INSECURE_HOST_ENV).and_return('1')
        expect(PypiUrl.build_args("https://private.example.com/simple")).to eql \
          ["--default-index", "https://private.example.com/simple", "--allow-insecure-host", "private.example.com"]
      end

      # The variable was named for pip's --trusted-host before every install
      # path moved to uv. Existing helm values and compose files still set it.
      it "honors the deprecated environment variable name" do
        allow(ENV).to receive(:[]).with(PypiUrl::DEPRECATED_INSECURE_HOST_ENV).and_return('1')
        expect(PypiUrl.build_args("https://private.example.com/simple")).to include "--allow-insecure-host"
      end

      it "passes the host without the port or path" do
        allow(ENV).to receive(:[]).with(PypiUrl::INSECURE_HOST_ENV).and_return('1')
        args = PypiUrl.build_args("https://private.example.com:8443/simple")
        expect(args.last).to eql "private.example.com"
      end
    end

    describe "DEFAULT" do
      it "is the public pypi simple index" do
        expect(PypiUrl::DEFAULT).to eql "https://pypi.org/simple"
      end
    end
  end
end

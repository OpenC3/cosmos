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

    describe "DEFAULT" do
      it "is the public pypi simple index" do
        expect(PypiUrl::DEFAULT).to eql "https://pypi.org/simple"
      end
    end
  end
end

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

require 'uri'
require 'openc3/utilities/logger'

module OpenC3
  class PypiUrl
    DEFAULT = 'https://pypi.org/simple'

    # Validate that a resolved pypi_url is an http(s) URL before it is handed to
    # pip. The value can come from a user-writable setting or ENV, so a malformed
    # or non-http value is rejected and replaced with the default rather than
    # passed through to pip.
    #
    # @param pypi_url [String] the resolved pypi index url to validate
    # @return [String] the original url if valid, otherwise DEFAULT
    def self.validate(pypi_url)
      uri = URI.parse(pypi_url)
      unless uri.is_a?(URI::HTTP) && !uri.host.to_s.empty?
        raise URI::InvalidURIError, "not an http(s) URL"
      end
      pypi_url
    rescue URI::InvalidURIError => e
      Logger.error("Invalid pypi_url '#{pypi_url}' (#{e.message}); falling back to #{DEFAULT}")
      DEFAULT
    end

    # Environment variable that opts a deployment into insecure (unverified TLS)
    # connections to the pypi index host, for operators running a private index
    # with a self-signed certificate.
    INSECURE_HOST_ENV = 'UV_ALLOW_INSECURE_HOST'

    # Previous name for INSECURE_HOST_ENV, still honored so existing helm values
    # and compose files keep working. It was named for pip's --trusted-host, but
    # every install path goes through uv (openc3/bin/pipinstall is a uv pip
    # install wrapper), so the flag it produces is uv's --allow-insecure-host.
    DEPRECATED_INSECURE_HOST_ENV = 'PIP_ENABLE_TRUSTED_HOST'

    # Build the argv array of index arguments shared by every uv invocation.
    #
    # --default-index rather than -i/--index-url: the latter is deprecated by uv
    # on both `uv sync` and `uv pip install`. Note this only affects the index uv
    # resolves against, so it has no effect on `uv sync --frozen`, where uv.lock
    # already pins each package's registry and wheel URL.
    #
    # --allow-insecure-host rather than --trusted-host: --trusted-host is an
    # undocumented uv alias, so use the real uv option.
    #
    # @param pypi_url [String] the resolved and validated pypi index url
    # @return [Array<String>] arguments to append to a uv command line
    def self.build_args(pypi_url)
      args = ["--default-index", pypi_url]
      if allow_insecure_host?
        args += ["--allow-insecure-host", URI.parse(pypi_url).host]
      end
      args
    end

    # @return [Boolean] whether the deployment opted into insecure connections
    #   to the pypi index host
    def self.allow_insecure_host?
      !ENV[INSECURE_HOST_ENV].nil? || !ENV[DEPRECATED_INSECURE_HOST_ENV].nil?
    end
  end
end

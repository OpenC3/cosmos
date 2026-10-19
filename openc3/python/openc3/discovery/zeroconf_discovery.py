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

import time
from fnmatch import fnmatch

from openc3.discovery.discovery import Discovery


class ZeroconfDiscovery(Discovery):
    """Lists the IP addresses of devices advertising mDNS (zeroconf) services.

    Each parameter is a service type, e.g. _hue._tcp.local., optionally followed
    by |-separated filters on the service name or its TXT properties as
    case-insensitive globs, e.g. _http._tcp.local.|name=shelly* or
    _http._tcp.local.|manufacturer=*pella*. Requires the zeroconf package."""

    BROWSE_SECONDS = 3.0
    INFO_TIMEOUT_MS = 1500

    def __init__(self, *matchers):
        super().__init__(*matchers)
        self.matchers = [self._parse_matcher(matcher) for matcher in matchers if matcher]

    @staticmethod
    def _parse_matcher(text):
        service_type, *filters = text.split("|")
        service_type = service_type.strip()
        if not service_type.endswith("."):
            service_type += "."
        properties = {}
        for item in filters:
            key, _, glob = item.partition("=")
            properties[key.strip().lower()] = glob.strip().lower()
        return service_type, properties

    @staticmethod
    def _matches(name, service_type, properties, matcher):
        matcher_type, filters = matcher
        if matcher_type != service_type:
            return False
        for key, glob in filters.items():
            value = name if key == "name" else properties.get(key)
            if value is None or not fnmatch(value.lower(), glob):
                return False
        return True

    def discover(self):
        if not self.matchers:
            return []
        try:
            from zeroconf import IPVersion, ServiceBrowser, Zeroconf
        except ImportError as error:
            raise RuntimeError("The zeroconf Python package is not installed on the host") from error

        found = {}

        def on_change(zeroconf, service_type, name, state_change):
            found[name] = service_type

        zeroconf = Zeroconf()
        try:
            browser = ServiceBrowser(zeroconf, sorted({type for type, _ in self.matchers}), handlers=[on_change])
            time.sleep(self.BROWSE_SECONDS)
            browser.cancel()
            results = []
            seen = set()
            for name, service_type in sorted(found.items()):
                info = zeroconf.get_service_info(service_type, name, timeout=self.INFO_TIMEOUT_MS)
                if info is None:
                    continue
                properties = {}
                for key, value in (info.properties or {}).items():
                    if value is not None:
                        properties[key.decode(errors="replace").lower()] = value.decode(errors="replace")
                if not any(self._matches(name, service_type, properties, matcher) for matcher in self.matchers):
                    continue
                for address in info.parsed_addresses(IPVersion.V4Only):
                    if address not in seen:
                        seen.add(address)
                        label = name.removesuffix(f".{service_type}")
                        results.append({"value": address, "text": f"{label} ({address})"})
                    break
        finally:
            zeroconf.close()
        return results

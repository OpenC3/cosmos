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
from concurrent.futures import ThreadPoolExecutor
from fnmatch import fnmatch

from openc3.discovery.discovery import Discovery


class ZeroconfDiscovery(Discovery):
    """Lists the IP addresses of devices advertising mDNS (zeroconf) services.

    Each parameter is a service type, e.g. _hue._tcp.local., optionally followed
    by |-separated filters on the service name or its TXT properties as
    case-insensitive globs, e.g. _http._tcp.local.|name=shelly* or
    _http._tcp.local.|manufacturer=*pella*. Requires the zeroconf package.

    Without parameters discover() finds nothing, but scan() lists every service
    advertised on the network for hardware discovery."""

    BROWSE_SECONDS = 3.0
    INFO_TIMEOUT_MS = 1500
    # Service details are looked up in parallel since each can take a while
    INFO_THREADS = 16

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
        return super().discover()

    def scan(self):
        try:
            from zeroconf import IPVersion, ServiceBrowser, Zeroconf
        except ImportError as error:
            raise RuntimeError("The zeroconf Python package is not installed on the host") from error

        found = {}

        def on_change(zeroconf, service_type, name, state_change):
            found[name] = service_type

        zeroconf = Zeroconf()
        try:
            if self.matchers:
                service_types = sorted({type for type, _ in self.matchers})
            else:
                # Every type of service advertised on the network
                from zeroconf import ZeroconfServiceTypes

                service_types = sorted(ZeroconfServiceTypes.find(zc=zeroconf, timeout=self.BROWSE_SECONDS))
            if not service_types:
                return []
            browser = ServiceBrowser(zeroconf, service_types, handlers=[on_change])
            time.sleep(self.BROWSE_SECONDS)
            browser.cancel()

            services = sorted(found.items())
            with ThreadPoolExecutor(max_workers=self.INFO_THREADS) as executor:
                infos = list(
                    executor.map(
                        lambda service: zeroconf.get_service_info(service[1], service[0], timeout=self.INFO_TIMEOUT_MS),
                        services,
                    )
                )
            devices = []
            for (name, service_type), info in zip(services, infos, strict=True):
                if info is None:
                    continue
                addresses = info.parsed_addresses(IPVersion.V4Only)
                if not addresses:
                    continue
                properties = {}
                for key, value in (info.properties or {}).items():
                    if value is not None:
                        properties[key.decode(errors="replace").lower()] = value.decode(errors="replace")
                label = name.removesuffix(f".{service_type}")
                devices.append(
                    {
                        "value": addresses[0],
                        "text": f"{label} ({addresses[0]})",
                        "type": service_type,
                        "name": name,
                        "properties": properties,
                    }
                )
            return devices
        finally:
            zeroconf.close()

    def match(self, device):
        if not self.matchers:
            return True
        return any(
            self._matches(device["name"], device["type"], device["properties"], matcher) for matcher in self.matchers
        )

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

import ipaddress
import socket
import time
import urllib.request
import xml.etree.ElementTree as ElementTree
from concurrent.futures import ThreadPoolExecutor
from fnmatch import fnmatch
from urllib.parse import urlparse

from openc3.discovery.discovery import Discovery


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


class SsdpDiscovery(Discovery):
    """Lists the IP addresses of network devices advertising themselves with SSDP
    (UPnP), such as media players, smart TVs, IP cameras, routers and NAS.

    Each parameter is a matcher made of key=glob conditions joined with |, all of
    which must match (case-insensitive). The keys are the search response
    headers st (the device or service type), usn and server, and the fields of
    the device description: devicetype, friendlyname, manufacturer,
    manufacturerurl, modelname, modelnumber, modeldescription, modelurl,
    serialnumber, udn, upc and presentationurl. Description conditions must all
    hold for one UPnP device (the root device or one embedded in it). Use ? for
    a space in a glob, e.g. manufacturer=Royal?Philips*|modelname=Philips?hue*.
    Uses only the Python standard library."""

    MULTICAST_ADDRESS = ("239.255.255.250", 1900)
    SEARCH_SECONDS = 3.0
    # Devices wait a random time up to MX seconds before answering
    SEARCH_MX = 2
    HEADER_KEYS = ("st", "usn", "server")
    DESCRIPTION_KEYS = (
        "devicetype",
        "friendlyname",
        "manufacturer",
        "manufacturerurl",
        "modelname",
        "modelnumber",
        "modeldescription",
        "modelurl",
        "serialnumber",
        "udn",
        "upc",
        "presentationurl",
    )
    DESCRIPTION_TIMEOUT_S = 2.0
    MAX_DESCRIPTION_BYTES = 256 * 1024
    # Some hosts (e.g. Windows) advertise several descriptions
    MAX_LOCATIONS_PER_HOST = 4
    DESCRIPTION_THREADS = 16

    def __init__(self, *matchers):
        super().__init__(*matchers)
        self.matchers = [self._parse_matcher(matcher) for matcher in matchers if matcher]

    @classmethod
    def _parse_matcher(cls, text):
        conditions = []
        for item in text.split("|"):
            key, separator, glob = item.partition("=")
            key = key.strip().lower()
            if not separator or key not in cls.HEADER_KEYS + cls.DESCRIPTION_KEYS:
                raise ValueError(
                    f"SSDP matcher '{text}' must be key=glob conditions joined with |, "
                    f"where the keys are {', '.join(cls.HEADER_KEYS + cls.DESCRIPTION_KEYS)}"
                )
            conditions.append((key, glob.strip().lower()))
        return conditions

    def match(self, device):
        if not self.matchers:
            return True
        return any(self._matches(device, matcher) for matcher in self.matchers)

    @classmethod
    def _matches(cls, device, matcher):
        description_conditions = []
        for key, glob in matcher:
            if key in cls.HEADER_KEYS:
                if not any(fnmatch(value.lower(), glob) for value in device.get(key) or []):
                    return False
            else:
                description_conditions.append((key, glob))
        if not description_conditions:
            return True
        return any(
            all(fnmatch((description.get(key) or "").lower(), glob) for key, glob in description_conditions)
            for description in device.get("devices") or []
        )

    def scan(self):
        responses = self._search()
        hosts = {}
        for address, headers in responses:
            host = hosts.setdefault(address, {"st": [], "usn": [], "server": [], "locations": []})
            for key in self.HEADER_KEYS:
                value = headers.get(key)
                if value and value not in host[key]:
                    host[key].append(value)
            location = headers.get("location")
            if (
                location
                and location not in host["locations"]
                and len(host["locations"]) < self.MAX_LOCATIONS_PER_HOST
                and self._location_allowed(location, address)
            ):
                host["locations"].append(location)

        fetches = [(address, location) for address, host in hosts.items() for location in host["locations"]]
        with ThreadPoolExecutor(max_workers=self.DESCRIPTION_THREADS) as executor:
            descriptions = list(executor.map(lambda fetch: self._describe(fetch[1]), fetches))
        devices_by_host = {}
        for (address, _), described in zip(fetches, descriptions, strict=True):
            devices_by_host.setdefault(address, []).extend(described)

        devices = []
        for address in sorted(hosts, key=self._address_key):
            host = hosts[address]
            described = devices_by_host.get(address, [])
            root = described[0] if described else {}
            name = root.get("friendlyname") or " ".join(
                part for part in (root.get("manufacturer"), root.get("modelname")) if part
            )
            name = name or (host["server"][0] if host["server"] else "UPnP device")
            devices.append(
                {
                    "value": address,
                    "text": f"{name} ({address})",
                    "st": host["st"],
                    "usn": host["usn"],
                    "server": host["server"],
                    "location": host["locations"][0] if host["locations"] else None,
                    "devices": described,
                }
            )
        return devices

    def _search(self):
        """Send an M-SEARCH for every device and collect the (address, headers) of the responses"""
        message = (
            "M-SEARCH * HTTP/1.1\r\n"
            f"HOST: {self.MULTICAST_ADDRESS[0]}:{self.MULTICAST_ADDRESS[1]}\r\n"
            'MAN: "ssdp:discover"\r\n'
            f"MX: {self.SEARCH_MX}\r\n"
            "ST: ssdp:all\r\n"
            "\r\n"
        ).encode()
        responses = []
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
        try:
            sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 2)
            sock.bind(("", 0))
            # Twice since UDP can be dropped
            sock.sendto(message, self.MULTICAST_ADDRESS)
            sock.sendto(message, self.MULTICAST_ADDRESS)
            deadline = time.monotonic() + self.SEARCH_SECONDS
            while (remaining := deadline - time.monotonic()) > 0:
                sock.settimeout(remaining)
                try:
                    data, (address, _port) = sock.recvfrom(65507)
                except TimeoutError:
                    break
                headers = self._parse_response(data)
                if headers is not None:
                    responses.append((address, headers))
        finally:
            sock.close()
        return responses

    @staticmethod
    def _parse_response(data):
        lines = data.decode(errors="replace").split("\r\n")
        if not lines[0].upper().startswith("HTTP/1.1 200"):
            return None
        headers = {}
        for line in lines[1:]:
            key, separator, value = line.partition(":")
            if separator:
                headers[key.strip().lower()] = value.strip()
        return headers

    @staticmethod
    def _location_allowed(location, address):
        """Only fetch descriptions from the device that answered, so another
        device can't make the host request other URLs"""
        try:
            url = urlparse(location)
        except ValueError:
            return False
        return url.scheme in ("http", "https") and url.hostname == address

    def _describe(self, location):
        """The UPnP devices in a device description: the root device then the
        devices embedded in it, each a dict of its fields"""
        try:
            opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), _NoRedirect())
            with opener.open(location, timeout=self.DESCRIPTION_TIMEOUT_S) as response:
                data = response.read(self.MAX_DESCRIPTION_BYTES + 1)
            if len(data) > self.MAX_DESCRIPTION_BYTES or b"<!DOCTYPE" in data.upper() or b"<!ENTITY" in data.upper():
                return []
            root = ElementTree.fromstring(data)
        except Exception:
            return []
        devices = []
        for element in root.iter():
            if self._tag(element) != "device":
                continue
            fields = {}
            for child in element:
                tag = self._tag(child).lower()
                if tag in self.DESCRIPTION_KEYS and child.text and child.text.strip():
                    fields[tag] = child.text.strip()
            if fields:
                devices.append(fields)
        return devices

    @staticmethod
    def _tag(element):
        return element.tag.rsplit("}", 1)[-1] if isinstance(element.tag, str) else ""

    @staticmethod
    def _address_key(address):
        try:
            return (0, int(ipaddress.ip_address(address)))
        except ValueError:
            return (1, address)

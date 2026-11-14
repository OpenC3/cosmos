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
import queue
import re
import socket
import subprocess
import sys
import threading
import time
from fnmatch import fnmatch
from pathlib import Path

from openc3.discovery.discovery import Discovery


class NeighborDiscovery(Discovery):
    """Lists the IP addresses of the devices on the local network that the host
    has recently communicated with, from its ARP (neighbor) table, so devices
    that don't advertise themselves can be found by the vendor prefix of their
    MAC address or their hostname. Nothing is sent to the devices: a device the
    host hasn't talked to recently isn't listed.

    Each parameter is a matcher made of key=glob conditions joined with |, all of
    which must match (case-insensitive): mac (the MAC address as hex digits,
    with or without separators, e.g. mac=00D02D* or mac=00:D0:2D*), hostname
    (the full name from reverse DNS or its first label, e.g. hostname=lyric-*)
    and ip. Uses only the Python standard library."""

    CONDITION_KEYS = ("mac", "hostname", "ip")
    ARP_TABLE = Path("/proc/net/arp")
    COMMAND_TIMEOUT_S = 5
    # Reverse DNS has no timeout of its own, so stop waiting for slow names
    HOSTNAME_TIMEOUT_S = 3.0
    HOSTNAME_THREADS = 16
    IPV4 = re.compile(r"\b(\d{1,3}(?:\.\d{1,3}){3})\b")
    MAC = re.compile(r"\b([0-9A-Fa-f]{1,2}(?:[:-][0-9A-Fa-f]{1,2}){5})\b")

    def __init__(self, *matchers):
        super().__init__(*matchers)
        self.matchers = [self._parse_matcher(matcher) for matcher in matchers if matcher]

    @classmethod
    def _parse_matcher(cls, text):
        conditions = []
        for item in text.split("|"):
            key, separator, glob = item.partition("=")
            key = key.strip().lower()
            if not separator or key not in cls.CONDITION_KEYS:
                raise ValueError(
                    f"Neighbor matcher '{text}' must be mac=glob, hostname=glob or ip=glob conditions joined with |"
                )
            glob = glob.strip().lower()
            if key == "mac":
                glob = glob.replace(":", "").replace("-", "")
            conditions.append((key, glob))
        return conditions

    def match(self, device):
        if not self.matchers:
            return True
        return any(
            all(self._condition_matches(device, *condition) for condition in matcher) for matcher in self.matchers
        )

    @staticmethod
    def _condition_matches(device, key, glob):
        if key == "mac":
            return fnmatch(device["mac"].replace(":", "").lower(), glob)
        if key == "ip":
            return fnmatch(device["value"], glob)
        hostname = (device.get("hostname") or "").lower()
        return bool(hostname) and (fnmatch(hostname, glob) or fnmatch(hostname.split(".")[0], glob))

    def scan(self):
        neighbors = {}
        for ip, mac, interface in self._read_table():
            mac = self._normalize_mac(mac)
            if mac and self._is_device(ip, mac) and ip not in neighbors:
                neighbors[ip] = (mac, interface)
        hostnames = self._hostnames(list(neighbors))
        devices = []
        for ip in sorted(neighbors, key=lambda ip: int(ipaddress.ip_address(ip))):
            mac, interface = neighbors[ip]
            hostname = hostnames.get(ip)
            devices.append(
                {
                    "value": ip,
                    "text": f"{hostname} ({ip})" if hostname else f"{ip} ({mac})",
                    "mac": mac,
                    "hostname": hostname,
                    "interface": interface,
                }
            )
        return devices

    def _read_table(self):
        """The (ip, mac, interface) entries of the host's IPv4 neighbor table"""
        if sys.platform.startswith("linux") and self.ARP_TABLE.exists():
            return self._parse_proc_arp(self.ARP_TABLE.read_text())
        command = ["arp", "-a"] if sys.platform == "win32" else ["arp", "-an"]
        try:
            output = subprocess.run(
                command, capture_output=True, text=True, timeout=self.COMMAND_TIMEOUT_S, check=False
            ).stdout
        except (OSError, subprocess.TimeoutExpired) as error:
            raise RuntimeError(f"Could not read the neighbor table with '{' '.join(command)}': {error}") from error
        return self._parse_arp_output(output)

    @staticmethod
    def _parse_proc_arp(text):
        # IP address  HW type  Flags  HW address  Mask  Device
        entries = []
        for line in text.splitlines()[1:]:
            fields = line.split()
            # Flags 0x0 is an incomplete entry
            if len(fields) >= 6 and fields[2] != "0x0":
                entries.append((fields[0], fields[3], fields[5]))
        return entries

    @classmethod
    def _parse_arp_output(cls, output):
        """Lines of arp -an (macOS: ? (192.168.1.1) at a4:2b:b0:1:2:3 on en0 ...) or
        arp -a (Windows: 192.168.1.1   a4-2b-b0-01-02-03   dynamic)"""
        entries = []
        for line in output.splitlines():
            ip = cls.IPV4.search(line)
            mac = cls.MAC.search(line)
            if not ip or not mac:
                continue
            interface = re.search(r"\bon (\S+)", line)
            entries.append((ip.group(1), mac.group(1), interface.group(1) if interface else None))
        return entries

    @staticmethod
    def _normalize_mac(mac):
        octets = re.split(r"[:-]", mac)
        if len(octets) != 6:
            return None
        try:
            return ":".join(f"{int(octet, 16):02X}" for octet in octets)
        except ValueError:
            return None

    @staticmethod
    def _is_device(ip, mac):
        try:
            address = ipaddress.ip_address(ip)
        except ValueError:
            return False
        if address.is_multicast or address.is_unspecified:
            return False
        # Unset, broadcast and multicast MAC addresses aren't devices
        first_octet = int(mac[:2], 16)
        return mac != "00:00:00:00:00:00" and not first_octet & 0x01

    def _hostnames(self, ips):
        """Reverse DNS names of the ips. Lookups run in daemon threads since they
        can't be cancelled and mustn't keep the scan from finishing."""
        hostnames = {}
        pending = queue.Queue()
        for ip in ips:
            pending.put(ip)

        def lookup():
            while True:
                try:
                    ip = pending.get_nowait()
                except queue.Empty:
                    return
                try:
                    name = socket.gethostbyaddr(ip)[0]
                except (OSError, UnicodeError):
                    continue
                if name and name != ip:
                    hostnames[ip] = name.rstrip(".")

        threads = [threading.Thread(target=lookup, daemon=True) for _ in range(min(self.HOSTNAME_THREADS, len(ips)))]
        for thread in threads:
            thread.start()
        deadline = time.monotonic() + self.HOSTNAME_TIMEOUT_S
        for thread in threads:
            thread.join(max(0, deadline - time.monotonic()))
        return dict(hostnames)

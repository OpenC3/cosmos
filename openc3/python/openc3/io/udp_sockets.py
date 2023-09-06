# Copyright 2023 OpenC3, Inc.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import socket
import select
import ipaddress


class UdpReadWriteSocket:
    # @param bind_port [Integer[ Port to write data out from and receive data on (0 = randomly assigned)
    # @param bind_address [String] Local address to bind to (0.0.0.0 = All local addresses)
    # @param external_port [Integer] External port to write to
    # @param external_address [String] External host to send data to
    # @param multicast_interface_address [String] Local outgoing interface to send multicast packets from
    # @param ttl [Integer] Time To Live for outgoing multicast packets
    # @param read_multicast [Boolean] Whether or not to try to read from the external address as multicast
    # @param write_multicast [Boolean] Whether or not to write to the external address as multicast
    def __init__(
        self,
        bind_port=0,
        bind_address="0.0.0.0",
        external_port=None,
        external_address=None,
        multicast_interface_address=None,
        ttl=1,
        read_multicast=True,
        write_multicast=True,
    ):
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

        # Basic setup to reuse address
        self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

        # Bind to local address and port - This sets recv port, write_src port, recv_address, and write_src_address
        if bind_address and bind_port:
            self.socket.bind((bind_address, bind_port))

        # Default send to the specified address and port
        if external_address and external_port:
            self.socket.connect((external_address, external_port))

        # Handle multicast
        if UdpReadWriteSocket.multicast(external_address, external_port):
            if write_multicast:
                # Basic setup set time to live
                self.socket.setsockopt(
                    socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, int(ttl)
                )

                if multicast_interface_address:
                    # Set outgoing interface
                    self.socket.setsockopt(
                        socket.SOL_IP,
                        socket.IP_MULTICAST_IF,
                        socket.inet_aton(multicast_interface_address),
                    )

            # Receive messages sent to the multicast address
            if read_multicast:
                if not multicast_interface_address:
                    multicast_interface_address = "0.0.0.0"
                membership = socket.inet_aton(external_address) + socket.inet_aton(
                    multicast_interface_address
                )
                self.socket.setsockopt(
                    socket.SOL_IP, socket.IP_ADD_MEMBERSHIP, membership
                )

    # @param data [String] Binary data to send
    # @param write_timeout [Float] Time in seconds to wait for the data to send
    def write(self, data, write_timeout=10.0):
        num_bytes_to_send = len(data)
        total_bytes_sent = 0
        bytes_sent = 0
        data_to_send = data

        while True:
            try:
                bytes_sent = self.socket.send(data_to_send)
            except socket.error as e:
                if e.args[0] == socket.EAGAIN or e.args[0] == socket.EWOULDBLOCK:
                    result = select.select([], [self.socket], [], write_timeout)
                    if (
                        len(result[0]) == 0
                        and len(result[1]) == 0
                        and len(result[2]) == 0
                    ):
                        raise socket.timeout
            total_bytes_sent += bytes_sent
            if total_bytes_sent >= num_bytes_to_send:
                break
        data_to_send = data[total_bytes_sent:]
        return data_to_send

    # @param read_timeout [Float] Time in seconds to wait for the read to
    #   complete
    def read(self, read_timeout=None):
        data = None
        while True:
            try:
                data, _ = self.socket.recvfrom(65536, socket.MSG_DONTWAIT)
                break
            except socket.error as e:
                if e.args[0] == socket.EAGAIN or e.args[0] == socket.EWOULDBLOCK:
                    result = select.select([self.socket], [], [], read_timeout)
                    if (
                        len(result[0]) == 0
                        and len(result[1]) == 0
                        and len(result[2]) == 0
                    ):
                        raise socket.timeout
        return data

    # Defer all methods to the UDPSocket
    def __getattr__(self, func):
        def method(*args, **kwargs):
            return getattr(self.socket, func)(*args, **kwargs)

        return method

    # @param host [String] Machine name or IP address
    # @param port [String] Port
    # @return [Boolean] Whether the hostname is multicast
    @classmethod
    def multicast(cls, host, port):
        if host is None or port is None:
            return False
        return ipaddress.ip_address(host) in ipaddress.ip_network("224.0.0.0/4")


# Creates a UDPSocket and implements a non-blocking write.
class UdpWriteSocket(UdpReadWriteSocket):
    # @param dest_address [String] Host to send data to
    # @param dest_port [Integer] Port to send data to
    # @param src_port [Integer[ Port to send data out from
    # @param multicast_interface_address [String] Local outgoing interface to send multicast packets from
    # @param ttl [Integer] Time To Live for outgoing packets
    # @param bind_address [String] Local address to bind to (0.0.0.0 = All local addresses)
    def __init__(
        self,
        dest_address,
        dest_port,
        src_port=None,
        multicast_interface_address=None,
        ttl=1,
        bind_address="0.0.0.0",
    ):
        super().__init__(
            src_port,
            bind_address,
            dest_port,
            dest_address,
            multicast_interface_address,
            ttl,
            False,
            True,
        )


# Creates a UDPSocket and implements a non-blocking read.
class UdpReadSocket(UdpReadWriteSocket):
    # @param recv_port [Integer] Port to receive data on
    # @param multicast_address [String] Address to add multicast
    # @param multicast_interface_address [String] Local incoming interface to receive multicast packets on
    # @param bind_address [String] Local address to bind to (0.0.0.0 = All local addresses)
    def __init__(
        self,
        recv_port=0,
        multicast_address=None,
        multicast_interface_address=None,
        bind_address="0.0.0.0",
    ):
        super().__init__(
            recv_port,
            bind_address,
            None,
            multicast_address,
            multicast_interface_address,
            1,
            True,
            False,
        )

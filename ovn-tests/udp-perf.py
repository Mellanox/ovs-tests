#!/usr/bin/python3

import argparse
import daemon
import logging
import os
import socket
import sys
import time


def parse_args():
    parser = argparse.ArgumentParser(formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    parser.add_argument('-s', '--server', help='Run as server', action='store_true')
    parser.add_argument('-c', '--client', help='Run as client', metavar='REMOTE')
    parser.add_argument('-p', '--port', help='Port', type=int, default=5555)
    parser.add_argument('-i', '--interval', help='Interval', type=float, default=0.1)
    parser.add_argument('-D', '--daemon', help='run the server as a daemon', action='store_true')
    parser.add_argument('-6', help='Run over IPv6', action='store_true')
    parser.add_argument('--packets', help='Number of packets to send', type=int, default=50)
    parser.add_argument('--pass-rate', help='Accepted packet pass rate', type=float, default=0.7)
    parser.add_argument('--retries', help='Client handshake retries', type=float, default=20)
    parser.add_argument('--logfile', help='Send output to a log file')

    args = parser.parse_args()
    if (args.server and args.client) or (not args.server and not args.client):
        raise AttributeError("Invalid args: Either use --server or --client")

    if args.daemon and not args.server:
        raise AttributeError("Invalid args: -D/--daemon is allowed for server only")

    if args.pass_rate <= 0 or args.pass_rate > 1:
        raise AttributeError("Invalid args: --pass-rate should be > 0 and <= 1")

    if args.interval < 0:
        raise AttributeError("Invalid args: --interval should be >= 0")

    return args


def wait_for_handshake(sock):
    # listen packet
    data, client = sock.recvfrom(10)
    logger.info(f'Server: Received packet from {client}')

    packets = int.from_bytes(data, 'big')
    logger.info(f'Server: Packets to send {packets}')

    # Send Ack
    sock.sendto(bytes([0]), client)

    return client, packets


def listen(port, is_ipv6):
    while True:
        try:
            socket_family = socket.AF_INET if not is_ipv6 else socket.AF_INET6
            udp_socket = socket.socket(socket_family, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
            udp_socket.bind(('', port))

            client, packets = wait_for_handshake(udp_socket)
        except Exception as ex:
            logger.error(ex)
            return 1

        udp_socket.settimeout(0.2)
        for _ in range(packets):
            try:
                udp_socket.sendto(bytes([0]), client)
                udp_socket.recvfrom(1)
            except Exception as ex:
                logger.error(ex)


def handshake(sock, server_address, port, packets, retries, interval):
    for _ in range(retries):
        try:
            time.sleep(interval)
            # Send "packets" arg to server
            bytes_needed = (packets.bit_length() + 7) // 8
            data = packets.to_bytes(bytes_needed, 'big')
            sock.sendto(data, (server_address, port))

            # listen for Ack
            _, server = sock.recvfrom(1)
            logger.info(f'Client: Received Ack from {server}')
            return

        except Exception as ex:
            logger.error(ex)
            pass

    raise RuntimeError(f'No Ack received after {retries} retries')


def send(server_address, port, packets, retries, pass_rate, is_ipv6, interval):
    try:
        socket_family = socket.AF_INET if not is_ipv6 else socket.AF_INET6
        udp_socket = socket.socket(socket_family, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
        udp_socket.settimeout(0.2)
        handshake(udp_socket, server_address, port, packets, retries, interval)
    except Exception as ex:
        logger.error(ex)
        return 1

    received_packets = 0

    for _ in range(packets):
        try:
            time.sleep(interval)
            udp_socket.sendto(bytes([0]), (server_address, port))
            udp_socket.recvfrom(1)
            received_packets += 1
            if received_packets % 10 == 0:
                logger.info(f'Client: sent %d packets' % received_packets)
        except Exception as ex:
            logger.error(ex)

    return 0 if received_packets / packets >= pass_rate else 1


def main():
    try:
        args = parse_args()
        logging.basicConfig(filename=args.logfile, level=logging.INFO)
        is_pv6 = args.__getattribute__('6')
        if args.server:
            logger.info(f'Server listening on {args.port}, IPv{6 if is_pv6 else 4}')
            if args.daemon:
                logger.info("Running server in daemon mode")
                with daemon.DaemonContext():
                    listen(args.port, is_pv6)
            else:
                listen(args.port, is_pv6)
        else:
            logger.info(f'Connecting {args.client}:{args.port}, IPv{6 if is_pv6 else 4}')
            return send(args.client, args.port, args.packets, args.retries, args.pass_rate, is_pv6, args.interval)
    except KeyboardInterrupt:
        logger.error("Terminated")
        return 1
    except Exception as ex:
        logger.error(ex)
        return 1

    return 0


if __name__ == "__main__":
    logger = logging.getLogger(os.path.basename(__file__))
    rc = main()
    sys.exit(rc)

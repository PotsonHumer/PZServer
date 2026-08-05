#!/usr/bin/env python3

import os
from pathlib import Path
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import unittest


ROOT = Path(__file__).resolve().parent.parent
DOCKERFILE = ROOT / "Dockerfile"
INFO_REQUEST = b"\xff\xff\xff\xffTSource Engine Query\x00"
PACKET_HEADER = b"\xff\xff\xff\xff"


def extract_query_command(destination):
    start_marker = "COPY --chmod=755 <<'EOF' /usr/local/bin/pz-query\n"
    source = DOCKERFILE.read_text(encoding="utf-8")
    start = source.index(start_marker) + len(start_marker)
    end = source.index("\nEOF\n", start)
    destination.write_text(source[start:end] + "\n", encoding="utf-8")
    destination.chmod(0o755)


def info_reply(players, max_players):
    return (
        PACKET_HEADER
        + b"I"
        + b"\x11"
        + b"Test server\x00Muldraugh\x00zomboid\x00Project Zomboid\x00"
        + struct.pack("<H", 1234)
        + bytes((players, max_players, 0))
        + b"d"
        + b"l"
        + b"\x00"
        + b"\x01"
        + b"42.0\x00"
    )


class FakeA2SServer:
    def __init__(self, response, challenge=None):
        self.response = response
        self.challenge = challenge
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.socket.bind(("127.0.0.1", 0))
        self.port = self.socket.getsockname()[1]
        self.error = None
        self.thread = threading.Thread(target=self.serve, daemon=True)

    def __enter__(self):
        self.thread.start()
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        self.thread.join(timeout=2)
        self.socket.close()
        if self.error:
            raise self.error

    def serve(self):
        try:
            self.socket.settimeout(2)
            request, address = self.socket.recvfrom(1400)
            if request != INFO_REQUEST:
                raise AssertionError("unexpected initial A2S request")
            if self.challenge is not None:
                challenge = struct.pack("<i", self.challenge)
                self.socket.sendto(PACKET_HEADER + b"A" + challenge, address)
                retry, retry_address = self.socket.recvfrom(1400)
                if retry_address != address or retry != INFO_REQUEST + challenge:
                    raise AssertionError("unexpected A2S challenge retry")
            self.socket.sendto(self.response, address)
        except Exception as error:  # surfaced by __exit__
            self.error = error


class PzQueryTest(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.data_dir = Path(self.temporary_directory.name) / "Zomboid"
        self.config_dir = self.data_dir / "Server"
        self.config_dir.mkdir(parents=True)
        self.command = Path(self.temporary_directory.name) / "pz-query"
        extract_query_command(self.command)

    def tearDown(self):
        self.temporary_directory.cleanup()

    def write_port(self, port):
        (self.config_dir / "servertest.ini").write_text(
            "DefaultPort=" + str(port) + "\n", encoding="utf-8"
        )

    def run_query(self):
        environment = os.environ.copy()
        environment.update(
            {
                "HOME": self.temporary_directory.name,
                "PZ_DATA_DIR": str(self.data_dir),
                "PZ_SERVER_NAME": "servertest",
            }
        )
        return subprocess.run(
            [sys.executable, str(self.command)],
            capture_output=True,
            check=False,
            env=environment,
            text=True,
            timeout=5,
        )

    def test_direct_reply_prints_counts(self):
        with FakeA2SServer(info_reply(3, 32)) as server:
            self.write_port(server.port)
            result = self.run_query()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "players=3\nmax_players=32\n")

    def test_zero_player_reply_is_explicit(self):
        with FakeA2SServer(info_reply(0, 32)) as server:
            self.write_port(server.port)
            result = self.run_query()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "players=0\nmax_players=32\n")

    def test_challenge_response_and_custom_port(self):
        with FakeA2SServer(info_reply(1, 64), challenge=0x12345678) as server:
            self.write_port(server.port)
            result = self.run_query()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "players=1\nmax_players=64\n")

    def test_invalid_port_does_not_report_players(self):
        self.write_port(0)
        result = self.run_query()

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("DefaultPort is invalid", result.stderr)
        self.assertNotIn("players=", result.stdout)

    def test_malformed_reply_does_not_report_players(self):
        with FakeA2SServer(PACKET_HEADER + b"I\x11broken") as server:
            self.write_port(server.port)
            result = self.run_query()

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("pz-query:", result.stderr)
        self.assertNotIn("players=", result.stdout)

    def test_timeout_does_not_report_players(self):
        timeout_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        timeout_socket.bind(("127.0.0.1", 0))
        self.addCleanup(timeout_socket.close)
        self.write_port(timeout_socket.getsockname()[1])

        result = self.run_query()

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("A2S query timed out", result.stderr)
        self.assertNotIn("players=", result.stdout)


if __name__ == "__main__":
    unittest.main()

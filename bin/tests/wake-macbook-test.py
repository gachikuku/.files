#!/usr/bin/env python3
"""Offline checks for the Pi wake relay; subprocesses and sockets are blocked."""

import contextlib
import importlib.machinery
import importlib.util
import io
import ipaddress
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


SOURCE = Path(__file__).resolve().parents[1] / "bin" / "wake-macbook"
sys.dont_write_bytecode = True
LOADER = importlib.machinery.SourceFileLoader("wake_macbook", str(SOURCE))
SPEC = importlib.util.spec_from_loader(LOADER.name, LOADER)
WAKE = importlib.util.module_from_spec(SPEC)
LOADER.exec_module(WAKE)

HARDWARE = "84:2f:57:3e:80:c6"
PRIVATE = "6a:22:6a:06:31:d1"
LAN = ipaddress.IPv4Interface("192.168.1.20/24")
BROADCAST = "192.168.1.255"


class WakeMacBookTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="wake-macbook-test-")
        self.addCleanup(temporary.cleanup)
        self.config_path = Path(temporary.name) / "config.json"
        self.patch("CONFIG", self.config_path)
        # An unstubbed subprocess or network attempt fails instead of escaping.
        self.process = self.patch("subprocess.run", side_effect=AssertionError("Live subprocess forbidden"))
        self.socket = self.patch("socket.socket", side_effect=AssertionError("Live socket forbidden"))
        self.pause = self.patch("time.sleep")

    def patch(self, name, *args, **kwargs):
        target = WAKE
        parts = name.split(".")
        for part in parts[:-1]:
            target = getattr(target, part)
        patcher = mock.patch.object(target, parts[-1], *args, **kwargs)
        result = patcher.start()
        self.addCleanup(patcher.stop)
        return result

    def write_config(self, macs=None):
        config = {
            "macs": macs if macs is not None else [HARDWARE, PRIVATE],
            "network": "192.168.1.0/24",
            "registered_at": "2026-11-09T00:00:00+00:00",
        }
        self.config_path.write_text(json.dumps(config), encoding="utf-8")
        return self.config_path.read_bytes()

    def main(self, arguments, request=None):
        stdout, stderr = io.StringIO(), io.StringIO()
        with mock.patch.object(WAKE.sys, "argv", [str(SOURCE), *arguments]), \
                mock.patch.object(WAKE.sys, "stdin", io.StringIO(json.dumps(request))), \
                contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            status = WAKE.main()
        return status, stdout.getvalue(), stderr.getvalue()

    def use_lan(self):
        return self.patch("lan_address", return_value=("eth0", LAN, BROADCAST))

    def allow_neighbor(self, mac):
        self.process.side_effect = None
        self.process.return_value = subprocess.CompletedProcess([], 0, b"", b"")
        return self.patch("command_json", return_value=[{"lladdr": mac, "state": ["REACHABLE"]}])

    def test_magic_packet_has_exact_102_byte_payload(self):
        packet = WAKE.magic_packet(HARDWARE.upper())
        self.assertEqual(len(packet), 102)
        self.assertEqual(packet, b"\xff" * 6 + bytes.fromhex("842f573e80c6") * 16)

    def test_registration_normalizes_and_deduplicates(self):
        self.use_lan()
        neighbor = self.allow_neighbor(PRIVATE.upper())
        for hardware, wifi, expected in (
            (HARDWARE.upper(), PRIVATE.upper(), [HARDWARE, PRIVATE]),
            (PRIVATE.upper(), PRIVATE, [PRIVATE]),
        ):
            with self.subTest(expected=expected):
                status, _, error = self.main(["--register"], {
                    "hardware_mac": hardware, "wifi_mac": wifi, "ipv4": "192.168.1.42",
                })
                self.assertEqual(status, 0, error)
                saved = json.loads(self.config_path.read_text())
                self.assertEqual(saved["macs"], expected)
                self.assertEqual(saved["mac_ipv4"], "192.168.1.42")
                self.assertEqual(saved["network"], "192.168.1.0/24")
                self.assertTrue(saved["registered_at"])
        neighbor.assert_called_with(["ip", "-j", "neigh", "show", "to", "192.168.1.42", "dev", "eth0"])
        self.socket.assert_not_called()

    def test_work_network_registration_preserves_existing_config(self):
        self.use_lan()
        original = self.write_config()
        status, _, error = self.main(["--register"], {
            "hardware_mac": HARDWARE, "wifi_mac": PRIVATE, "ipv4": "10.10.10.28",
        })
        self.assertEqual(status, 1)
        self.assertIn("not on the Pi's home LAN", error)
        self.assertEqual(self.config_path.read_bytes(), original)
        self.process.assert_not_called()
        self.socket.assert_not_called()

    def test_neighbor_mismatch_preserves_existing_config(self):
        self.use_lan()
        original = self.write_config()
        self.allow_neighbor("02:00:00:00:00:99")
        status, _, error = self.main(["--register"], {
            "hardware_mac": HARDWARE, "wifi_mac": PRIVATE, "ipv4": "192.168.1.42",
        })
        self.assertEqual(status, 1)
        self.assertIn("could not verify", error)
        self.assertEqual(self.config_path.read_bytes(), original)
        self.socket.assert_not_called()

    def test_dry_run_never_opens_socket(self):
        self.use_lan()
        self.write_config()
        status, output, error = self.main(["--dry-run"])
        self.assertEqual(status, 0, error)
        self.assertIn("192.168.1.255:9", output)
        self.assertIn("would send 3 rounds of 2 x 102-byte", output)
        self.socket.assert_not_called()
        self.process.assert_not_called()
        self.pause.assert_not_called()

    def test_sender_emits_three_rounds_to_lan_broadcast(self):
        self.use_lan()
        self.write_config([HARDWARE, PRIVATE, HARDWARE.upper()])
        sender = mock.MagicMock()
        self.socket.side_effect = None
        self.socket.return_value.__enter__.return_value = sender
        status, output, error = self.main([])
        self.assertEqual(status, 0, error)
        self.socket.assert_called_once_with(WAKE.socket.AF_INET, WAKE.socket.SOCK_DGRAM)
        sender.bind.assert_called_once_with(("192.168.1.20", 0))
        sender.setsockopt.assert_called_once_with(WAKE.socket.SOL_SOCKET, WAKE.socket.SO_BROADCAST, 1)
        expected = [mock.call(WAKE.magic_packet(mac), (BROADCAST, 9))
                    for _ in range(3) for mac in (HARDWARE, PRIVATE)]
        self.assertEqual(sender.sendto.call_args_list, expected)
        self.assertEqual(self.pause.call_args_list, [mock.call(0.2), mock.call(0.2)])
        self.assertIn("Sent 6 wake packets", output)
        self.assertIn("does not confirm", output)

    def test_virtual_or_missing_default_interfaces_are_rejected(self):
        query = self.patch("command_json")
        for routes in (
            [], [{"gateway": "192.168.1.1"}],
            *[[{"dev": device}] for device in
              ("lo", "tailscale0", "docker0", "veth012", "wg0", "tun0", "br-123")],
        ):
            with self.subTest(routes=routes):
                query.reset_mock()
                query.return_value = routes
                with self.assertRaisesRegex(ValueError, "No active LAN interface"):
                    WAKE.lan_address()
                query.assert_called_once_with(["ip", "-j", "-4", "route", "show", "table", "main", "default"])

    def test_default_route_without_usable_broadcast_address_is_rejected(self):
        query = self.patch("command_json")
        for interface in (
            {"flags": ["UP", "BROADCAST"], "addr_info": []},
            {"flags": ["UP"], "addr_info": []},
            {"flags": ["BROADCAST"], "addr_info": []},
            {"flags": ["UP", "BROADCAST"], "addr_info": [
                {"family": "inet", "scope": "global", "local": "192.168.1.20", "prefixlen": 24},
            ]},
        ):
            with self.subTest(interface=interface):
                query.side_effect = [[{"dev": "eth0"}], [interface]]
                with self.assertRaisesRegex(ValueError, "No active LAN interface"):
                    WAKE.lan_address()

    def test_lan_discovery_skips_virtual_route_and_uses_physical_subnet(self):
        query = self.patch("command_json", side_effect=[
            [{"dev": "tailscale0", "metric": 0}, {"dev": "eth0", "metric": 100}],
            [{"flags": ["UP", "BROADCAST"], "addr_info": [
                {"family": "inet", "scope": "global", "local": "192.168.1.20",
                 "prefixlen": 24, "broadcast": BROADCAST},
            ]}],
        ])
        self.assertEqual(WAKE.lan_address(), ("eth0", LAN, BROADCAST))
        self.assertEqual(query.call_args_list[-1], mock.call(["ip", "-j", "-4", "address", "show", "dev", "eth0"]))


if __name__ == "__main__":
    unittest.main(verbosity=2)

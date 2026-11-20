#!/usr/bin/env python3
"""Compile isolated SDK importer probes with a configured Wi-Fi build's flags.

No local configuration source is read or compiled by these probes. Run after
configuring a Ninja Pico 2 W build: python3 tools/check_wifi_interop.py build
"""
import argparse
import json
import shlex
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("build_directory", type=Path)
options = parser.parse_args()
build = options.build_directory.resolve()
cache = (build / "CMakeCache.txt").read_text()
ninja = next(line.split("=", 1)[1] for line in cache.splitlines()
             if line.startswith("CMAKE_MAKE_PROGRAM:"))
commands = subprocess.check_output([ninja, "-C", str(build), "-t", "commands"], text=True)
command = next(shlex.split(line) for line in commands.splitlines() if "/swiftc " in line)
flags = [command[0]]
index = 1
while index < len(command):
    argument = command[index]
    if argument in ("-output-file-map", "-o", "-j", "-num-threads"):
        index += 2
        continue
    if argument.endswith(".swift") or argument in ("-c", "-emit-dependencies"):
        index += 1
        continue
    flags.append(argument)
    index += 1
if "-DSK_RADIO_CLOCK_WIFI" not in flags:
    parser.error("the build must have SK_RADIO_CLOCK_WIFI=ON")

probes = {
    "direct": ("""
func probe(_ ssid: UnsafePointer<CChar>, _ password: UnsafePointer<CChar>) -> UInt32 {
  _ = cyw43_arch_init_with_country(radio_clock_country_uk)
  cyw43_arch_lwip_begin()
  defer { cyw43_arch_lwip_end() }
  cyw43_arch_enable_sta_mode()
  cyw43_arch_disable_sta_mode()
  _ = cyw43_arch_wifi_connect_async(ssid, password, UInt32(CYW43_AUTH_WPA2_AES_PSK))
  _ = cyw43_wifi_link_status(&cyw43_state, Int32(CYW43_ITF_STA))
  _ = cyw43_tcpip_link_status(&cyw43_state, Int32(CYW43_ITF_STA))
  return withUnsafePointer(to: &cyw43_state.netif.0) { interface in
    guard dhcp_supplied_address(interface) != 0 else { return 0 }
    return UInt32(bigEndian: interface.pointee.ip_addr.addr)
  }
}
""", None),
    "country_macro": ("func probe() { _ = CYW43_COUNTRY_UK }", "cannot find 'CYW43_COUNTRY_UK'"),
    "address_macros": ("""
func probe(_ interface: UnsafeMutablePointer<netif>) {
  _ = lwip_ntohl(ip4_addr_get_u32(netif_ip4_addr(interface)))
}
""", "cannot find 'netif_ip4_addr'"),
    "variadic_printf": ('func probe() { printf("WiFi %d", Int32(1)) }', "Variadic function is unavailable"),
}
output = build / "wifi-interop-checks"
output.mkdir(exist_ok=True)
results = {}
for name, (source, expected_error) in probes.items():
    path = output / (name + ".swift")
    path.write_text(source)
    result = subprocess.run([*flags, "-c", str(path), "-o", str(output / (name + ".o"))],
                            cwd=build, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (output / (name + ".log")).write_text(result.stdout)
    passed = result.returncode == 0 if expected_error is None else (
        result.returncode != 0 and expected_error in result.stdout)
    results[name] = passed
    print(("PASS: " if passed else "FAIL: ") + name)
(output / "results.json").write_text(json.dumps(results, indent=2) + "\n")
raise SystemExit(0 if all(results.values()) else 1)

#!/usr/bin/env python3
"""Stateful firewall integration test. Never modifies the host firewall."""

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

INSTALL = Path(__file__).resolve().parent
PREVIEW = INSTALL / "hotspot-preview"

FIREWALL = PREVIEW / "nomad-wifi-isolation.sh"
REMOVAL = PREVIEW / "nomad-wifi-isolation-remove.sh"

MOCK = r'''#!/usr/bin/env python3
import json
import os
import sys
from pathlib import Path

name = Path(sys.argv[0]).name
args = sys.argv[1:]
state_path = Path(os.environ["NOMAD_MOCK_STATE"])

state = json.loads(state_path.read_text())
chains = state[name]

def save():
    state_path.write_text(json.dumps(state, indent=2))

def finish(code):
    save()
    sys.exit(code)

if not args:
    finish(1)

operation = args[0]
chain = args[1] if len(args) > 1 else ""

# Simulate a command failure before changing mock state.
fail_match = os.environ.get("NOMAD_MOCK_FAIL_MATCH", "")
if fail_match and fail_match in " ".join(args):
    sys.exit(42)

if operation == "-L":
    finish(0 if chain in chains else 1)

if operation == "-S":
    if chain not in chains:
        finish(1)

    print("-N " + chain)
    for rule in chains[chain]:
        print("-A " + chain + " " + " ".join(rule))
    finish(0)

if operation == "-N":
    if chain in chains:
        finish(1)
    chains[chain] = []
    finish(0)

if chain not in chains:
    finish(1)

if operation == "-F":
    chains[chain] = []
    finish(0)

if operation == "-X":
    if chains[chain]:
        finish(1)
    for rules in chains.values():
        if any("-j" in r and r[r.index("-j")+1] == chain
               for r in rules):
            finish(1)
    del chains[chain]
    finish(0)

rule = args[2:]

if operation == "-I":
    position = 0
    if rule and rule[0].isdigit():
        position = max(0, int(rule.pop(0)) - 1)
    chains[chain].insert(position, rule)
    finish(0)

if operation == "-A":
    chains[chain].append(rule)
    finish(0)

if operation == "-C":
    finish(0 if rule in chains[chain] else 1)

if operation == "-D":
    if rule not in chains[chain]:
        finish(1)
    chains[chain].remove(rule)
    finish(0)

finish(1)
'''

def require(condition, message):
    if not condition:
        raise AssertionError(message)
    print(f"PASS: {message}")

def contains_rule(rules, *tokens):
    return any(all(token in rule for token in tokens) for rule in rules)

def run_script(path, env):
    subprocess.run(["bash", str(path)], env=env, check=True, timeout=15)

def main():
    for path in (FIREWALL, REMOVAL):
        require(path.is_file(), f"{path.name} exists")

    with tempfile.TemporaryDirectory(prefix="nomad-fw-test-") as tmp:
        root = Path(tmp)
        bin_dir = root / "bin"
        bin_dir.mkdir()

        for name in ("iptables", "ip6tables"):
            mock_path = bin_dir / name
            mock_path.write_text(MOCK)
            mock_path.chmod(0o700)

        original = {
            "iptables": {
                "INPUT": [["-j", "EXISTING_INPUT_RULE"]],
                "FORWARD": [],
                "DOCKER-USER": [["-j", "EXISTING_DOCKER_RULE"]],
            },
            "ip6tables": {
                "INPUT": [["-j", "EXISTING_IPV6_RULE"]],
                "FORWARD": [],
            },
        }

        state_path = root / "state.json"
        state_path.write_text(json.dumps(original))

        env = os.environ.copy()
        env["PATH"] = str(bin_dir) + os.pathsep + env["PATH"]
        env["NOMAD_MOCK_STATE"] = str(state_path)

        def load():
            return json.loads(state_path.read_text())

        print("\n===== MOCK INSTALLATION =====")
        run_script(FIREWALL, env)
        installed = load()

        v4 = installed["iptables"]
        v6 = installed["ip6tables"]

        require(
            "NOMAD-WIFI-INPUT" in v4,
            "IPv4 INPUT isolation chain created",
        )
        require(
            "NOMAD-WIFI-FORWARD" in v4,
            "IPv4 forwarding isolation chain created",
        )
        require(
            contains_rule(
                v4["INPUT"], "wlan0", "NOMAD-WIFI-INPUT"
            ),
            "IPv4 INPUT hook installed",
        )
        require(
            contains_rule(
                v4["DOCKER-USER"],
                "wlan0", "NOMAD-WIFI-FORWARD"
            ),
            "Docker forwarding hook installed",
        )
        require(
            contains_rule(
                v4["NOMAD-WIFI-INPUT"], "--dport", "67", "ACCEPT"
            ),
            "DHCP allowance installed",
        )
        require(
            contains_rule(
                v4["NOMAD-WIFI-INPUT"], "--dport", "80", "ACCEPT"
            ),
            "Captive portal allowance installed",
        )
        require(
            contains_rule(
                v4["NOMAD-WIFI-FORWARD"],
                "--ctstate", "DNAT",
                "--ctorigdst", "192.168.50.1"
            ),
            "Docker DNAT restriction installed",
        )
        require(
            "NOMAD-WIFI-INPUT" in v6
            and "NOMAD-WIFI-FORWARD" in v6,
            "IPv6 isolation chains created",
        )

        print("\n===== MOCK REPEATED INSTALL =====")
        repeated = subprocess.run(
            ["bash", str(FIREWALL)],
            env=env,
            capture_output=True,
            text=True,
            check=False,
        )
        require(
            repeated.returncode != 0,
            "Repeated installation refused without ownership verification",
        )
        require(
            load() == installed,
            "Repeated installation preserved all existing rules",
        )

        print("\n===== MOCK CLEANUP =====")
        run_script(REMOVAL, env)
        recovered = load()

        require(
            recovered == original,
            "Cleanup restores the original mock firewall state",
        )

        print("\n===== REPEATED CLEANUP =====")
        run_script(REMOVAL, env)
        require(
            load() == original,
            "Repeated cleanup leaves existing rules untouched",
        )

        print("\n===== SIMULATED PARTIAL INSTALLATION FAILURE =====")

        # Start with the original simulated firewall.
        state_path.write_text(json.dumps(original))

        fault_env = env.copy()
        fault_env["NOMAD_MOCK_FAIL_MATCH"] = (
            "-A NOMAD-WIFI-INPUT -p tcp -d"
        )

        result = subprocess.run(
            ["bash", str(FIREWALL)],
            env=fault_env,
            check=False,
        )

        require(
            result.returncode != 0,
            "Injected firewall failure stops installation",
        )

        partial = load()

        require(
            partial == original,
            "Automatic rollback restores original firewall state",
        )

        # Cleanup should remain harmless after automatic recovery.
        run_script(REMOVAL, env)

        require(
            load() == original,
            "Cleanup after automatic recovery preserves existing rules",
        )

        print("\n===== PRE-EXISTING CHAIN PROTECTION =====")

        collision = json.loads(json.dumps(original))

        collision["iptables"]["NOMAD-WIFI-INPUT"] = [
            ["-j", "PREEXISTING_SECURITY_RULE"]
        ]

        state_path.write_text(json.dumps(collision))

        result = subprocess.run(
            ["bash", str(FIREWALL)],
            env=env,
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

        after_collision = load()

        preserved = (
            after_collision["iptables"].get("NOMAD-WIFI-INPUT")
            == [["-j", "PREEXISTING_SECURITY_RULE"]]
        )

        rejected = result.returncode != 0

        require(
            rejected,
            "Installation refused the pre-existing chain",
        )
        require(
            preserved,
            "Pre-existing chain contents preserved",
        )
        require(
            after_collision == collision,
            "Ownership conflict caused no firewall modifications",
        )

        print("\n===== CLEANUP OWNERSHIP PROTECTION =====")

        # Simulate a chain belonging to someone else.
        foreign = json.loads(json.dumps(original))
        foreign["iptables"]["NOMAD-WIFI-INPUT"] = [
            ["-j", "FOREIGN_SECURITY_RULE"]
        ]
        state_path.write_text(json.dumps(foreign))

        cleanup = subprocess.run(
            ["bash", str(REMOVAL)],
            env=env,
            capture_output=True,
            text=True,
            check=False,
        )

        after_cleanup = load()

        if after_cleanup == foreign:
            print("PASS: Foreign firewall chain preserved.")
        else:
            print("KNOWN FAILURE: Cleanup modified a foreign chain.")
            print("Production cleanup requires ownership verification.")

        print("\n===== ARBITRARY FOREIGN RULE PROTECTION =====")

        arbitrary_foreign = json.loads(json.dumps(original))
        arbitrary_foreign["iptables"]["NOMAD-WIFI-INPUT"] = [
            ["-p", "tcp", "--dport", "45678", "-j", "DROP"]
        ]

        state_path.write_text(json.dumps(arbitrary_foreign))

        arbitrary_cleanup = subprocess.run(
            ["bash", str(REMOVAL)],
            env=env,
            capture_output=True,
            text=True,
            check=False,
            timeout=15,
        )

        arbitrary_preserved = load() == arbitrary_foreign

        if arbitrary_preserved:
            print("PASS: Arbitrary foreign rule preserved.")
        else:
            print("SECURITY FAILURE: Arbitrary foreign rule was modified.")

        print("\n===== AUTOMATIC FAILURE RECOVERY =====")

        state_path.write_text(json.dumps(original))

        fault_env = env.copy()
        fault_env["NOMAD_MOCK_FAIL_MATCH"] = (
            "-A NOMAD-WIFI-INPUT -p tcp -d"
        )

        failed_install = subprocess.run(
            ["bash", str(FIREWALL)],
            env=fault_env,
            capture_output=True,
            text=True,
            check=False,
        )

        if failed_install.returncode != 0 and load() == original:
            print("PASS: Failed installation automatically recovered.")
        else:
            print("KNOWN FAILURE: Partial rules remain after failure.")
            print("Failure exit code:", failed_install.returncode)
            print("Failure stderr:")
            print(failed_install.stderr.strip() or "(empty)")

            current = load()
            for family in ("iptables", "ip6tables"):
                expected_chains = original[family]
                actual_chains = current[family]

                for chain in sorted(set(expected_chains) | set(actual_chains)):
                    before = expected_chains.get(chain)
                    after = actual_chains.get(chain)
                    if before != after:
                        print(f"REMAINING DIFFERENCE: {family} {chain}")
                        print("  Expected:", before)
                        print("  Actual:  ", after)

        print("\n===== SECURITY RELEASE GATE =====")

        cleanup_safe = after_cleanup == foreign
        recovery_safe = (
            failed_install.returncode != 0
            and load() == original
        )

        if not cleanup_safe or not recovery_safe or not arbitrary_preserved:
            print("BLOCKED: Firewall security requirements not met.")
            print("Foreign-chain cleanup protection:", cleanup_safe)
            print("Automatic failure recovery:", recovery_safe)
            print("No live firewall rules were modified.")
            raise AssertionError("Firewall is not production-ready")

        print("ALL STATEFUL FIREWALL TESTS PASSED")
        print("No live firewall rules were modified.")

if __name__ == "__main__":
    try:
        main()
    except (AssertionError, OSError, subprocess.CalledProcessError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        sys.exit(1)

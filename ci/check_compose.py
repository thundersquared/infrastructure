#!/usr/bin/env python3
"""Enforce the container contract documented in CLAUDE.md.

The prose rules in CLAUDE.md only help if something checks them. This script
turns them into a gate, and every exemption is an explicit entry with a
written reason — so a service needing an exception shows up in a code review
rather than being discovered during an incident.

Exemptions are keyed by `(compose path glob, service name)` rather than by
service name alone, because names are ambiguous across stacks: `worker` is the
Docker-socket-holding authentik worker in one stack and an ordinary hardened
twenty.crm worker in another.

Usage:
    python3 ci/check_compose.py [ROOT]

Exit codes: 0 = compliant, 1 = violations, 2 = bad invocation or parse error.
"""

from __future__ import annotations

import fnmatch
import sys
from pathlib import Path

try:
    import yaml
except ImportError:  # pragma: no cover - CI always has PyYAML via ansible
    print("PyYAML is required: pip install pyyaml", file=sys.stderr)
    raise SystemExit(2)

# (compose path glob, service name) -> why this service is exempt from the
# default cap_drop/no-new-privileges policy.
EXEMPTIONS: dict[tuple[str, str], str] = {
    # Data stores: their entrypoints start as root and use gosu to drop to the
    # database user, which needs CAP_SETUID/CAP_SETGID. Both cap_drop: [ALL]
    # and no-new-privileges prevent the container from ever starting.
    ("*/stalwart/*", "postgres"): "data store: gosu entrypoint needs CAP_SETUID/CAP_SETGID",
    ("*/stalwart/*", "keydb"): "data store: gosu entrypoint needs CAP_SETUID/CAP_SETGID",
    ("*/stalwart/*", "opensearch"): "data store: gosu entrypoint needs CAP_SETUID/CAP_SETGID",
    ("*/authentik/*", "database"): "data store: gosu entrypoint needs CAP_SETUID/CAP_SETGID",
    ("*/calcom/*", "database"): "data store: gosu entrypoint needs CAP_SETUID/CAP_SETGID",
    ("*/twenty/*", "db"): "data store: gosu entrypoint needs CAP_SETUID/CAP_SETGID",
    ("*/twenty/*", "redis"): "data store: gosu entrypoint needs CAP_SETUID/CAP_SETGID",
    ("*/opencloud/*", "garage"): "data store: gosu entrypoint needs CAP_SETUID/CAP_SETGID",
    ("*/hypebun-web/*", "db"): "data store: gosu entrypoint needs CAP_SETUID/CAP_SETGID",
    ("*/n8n/*", "postgres"): "data store: gosu entrypoint needs CAP_SETUID/CAP_SETGID",
    ("*/fleet/*", "database"): "data store: gosu entrypoint needs CAP_SETUID/CAP_SETGID",
    ("*/fleet/*", "kv"): "data store: gosu entrypoint needs CAP_SETUID/CAP_SETGID",
    # Docker-socket consumer: runs as root with the socket mounted so it can
    # apply blueprints. Dropping caps breaks it.
    ("*/authentik/*", "worker"): "authentik worker: needs Docker socket for blueprints",
    # Apache/PHP image: breaks outright with cap_drop: [ALL]. Gets tmpfs only.
    ("*/roundcube/*", "roundcubemail"): "Apache+PHP image breaks with cap_drop: [ALL]",
    # Init container whose sole job is chowning volume paths; needs CAP_CHOWN.
    ("*/fleet/*", "fleet-init"): "init container: sole job is chown, needs CAP_CHOWN",
}

# Services that publish a port on all interfaces on purpose, with the reason.
# Everything else must bind to loopback and let a reverse proxy do the exposing.
PUBLIC_PUBLISHERS: dict[tuple[str, str], str] = {
    # MX: the mail server's whole purpose is receiving SMTP/IMAP from the
    # internet, so these must be reachable directly.
    ("*/stalwart/*", "stalwart"): "MX: SMTP/IMAP must be internet-reachable",
    # Headscale is the WireGuard endpoint; clients connect from outside.
    ("*/headscale/*", "headscale"): "WireGuard/Norelay endpoint must be reachable",
    # frankenphp terminates ACME (HTTP-01) and serves the site directly.
    ("*/hypebun-web/*", "frankenphp"): "terminates ACME HTTP-01 and serves the site",
}

# Stateless services that must run read-only. Mirrors the "Applied to:" list
# in CLAUDE.md.
READ_ONLY_REQUIRED = {"cloudflared", "webmail", "runner", "cobalt-api"}

# Capabilities that may be re-added via cap_add. Anything else is a finding: a
# new cap_add should be a conscious, documented decision.
ALLOWED_CAP_ADD = {
    "NET_BIND_SERVICE",  # binds a privileged port directly
    "NET_ADMIN",         # VPN / network management
    "SYS_NICE",          # real-time scheduling (MySQL)
    "CHOWN",             # init containers that chown volume paths
    # Paired with CHOWN on the init containers that also drop privileges.
    "SETUID", "SETGID", "DAC_OVERRIDE", "FOWNER", "KILL",
}


def as_list(value) -> list:
    if value is None:
        return []
    return value if isinstance(value, list) else [value]


def has_nnp(svc: dict) -> bool:
    return any("no-new-privileges" in str(o) for o in as_list(svc.get("security_opt")))


def lookup(table: dict, rel: str, name: str) -> str | None:
    for (pattern, service), reason in table.items():
        if service == name and fnmatch.fnmatch(rel, pattern):
            return reason
    return None


def check_compose(path: Path, root: Path) -> list[str]:
    problems: list[str] = []
    rel = str(path.relative_to(root))

    try:
        doc = yaml.safe_load(path.read_text())
    except yaml.YAMLError as exc:
        return [f"{rel}: cannot parse: {exc}"]

    if not isinstance(doc, dict):
        return [f"{rel}: top level is not a mapping"]

    if "version" in doc:
        problems.append(
            f"{rel}: top-level `version:` is deprecated in Compose V2 — remove it"
        )

    app_infra = (doc.get("networks") or {}).get("app-infra") or {}
    if not app_infra.get("external"):
        problems.append(
            f"{rel}: missing `networks.app-infra.external: true` — every stack "
            "joins the shared external network"
        )

    for name, svc in (doc.get("services") or {}).items():
        where = f"{rel}: service `{name}`"
        if not isinstance(svc, dict):
            problems.append(f"{where}: definition is not a mapping")
            continue

        if not svc.get("image"):
            problems.append(f"{where}: no `image:` key")
        else:
            ref = str(svc["image"]).split("@", 1)[0]
            if ref.endswith(":latest"):
                problems.append(
                    f"{where}: image `{svc['image']}` uses a floating `latest` tag"
                )

        if svc.get("privileged"):
            problems.append(f"{where}: `privileged: true` is never allowed")

        problems.extend(check_ports(where, name, rel, svc))

        reason = lookup(EXEMPTIONS, rel, name)
        cap_drop = [str(c) for c in as_list(svc.get("cap_drop"))]

        if reason is None:
            if "ALL" not in cap_drop:
                problems.append(f"{where}: missing `cap_drop: [ALL]`")
            if not has_nnp(svc):
                problems.append(
                    f"{where}: missing `security_opt: [no-new-privileges:true]`"
                )
        elif cap_drop or has_nnp(svc):
            problems.append(
                f"{where}: exempt ({reason}) yet also sets cap_drop/security_opt — "
                "drop the stale exemption or the redundant keys"
            )

        cap_add = {str(c) for c in as_list(svc.get("cap_add"))}
        unexpected = sorted(cap_add - ALLOWED_CAP_ADD)
        if unexpected:
            noun = "capability" if len(unexpected) == 1 else "capabilities"
            problems.append(
                f"{where}: cap_add has undocumented {noun} {unexpected} — add to "
                "ALLOWED_CAP_ADD in ci/check_compose.py and document the reason "
                "in CLAUDE.md first"
            )
        if cap_add and reason is None and "ALL" not in cap_drop:
            problems.append(f"{where}: `cap_add` must be paired with `cap_drop: [ALL]`")

        read_only = bool(svc.get("read_only"))
        if name in READ_ONLY_REQUIRED and not read_only:
            problems.append(
                f"{where}: stateless service must set `read_only: true` plus tmpfs "
                "for writable paths"
            )
        if read_only and name not in READ_ONLY_REQUIRED and reason is None:
            problems.append(
                f"{where}: sets `read_only: true` but is not in READ_ONLY_REQUIRED "
                "— record the intent there"
            )

    return problems


def check_ports(where: str, name: str, rel: str, svc: dict) -> list[str]:
    problems: list[str] = []
    publisher = lookup(PUBLIC_PUBLISHERS, rel, name)
    for port in as_list(svc.get("ports")):
        text = str(port)
        if ":" not in text:
            problems.append(f"{where}: port `{text}` has no host mapping")
            continue
        host = text.split(":", 1)[0]
        if host in ("127.0.0.1", "localhost", "::1"):
            continue
        if publisher is None:
            problems.append(
                f"{where}: port `{text}` is not bound to loopback — use "
                "127.0.0.1:<port>:<port> and let a reverse proxy publish it, or "
                "add a PUBLIC_PUBLISHERS entry in ci/check_compose.py explaining why"
            )
    return problems


def main(argv: list[str]) -> int:
    root = Path(argv[1] if len(argv) > 1 else ".").resolve()
    files = sorted(root.glob("*/containers/*/docker-compose*.yml"))
    if not files:
        print(f"no compose files found under {root}", file=sys.stderr)
        return 2

    problems: list[str] = []
    services = 0
    for path in files:
        problems.extend(check_compose(path, root))
        doc = yaml.safe_load(path.read_text()) or {}
        services += len(doc.get("services") or {})

    if problems:
        print(f"compose policy: {len(problems)} violation(s)\n", file=sys.stderr)
        for problem in problems:
            print(f"  {problem}", file=sys.stderr)
        print("", file=sys.stderr)
        return 1

    print(
        f"compose policy: OK ({len(files)} files, {services} services, "
        f"{len(EXEMPTIONS)} exemptions, {len(PUBLIC_PUBLISHERS)} public publishers)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))

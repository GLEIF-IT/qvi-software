from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path
from typing import Any

from keri.app.keeping import Algos
from keri.core import eventing, serdering
from keri.core import signing as csigning
from keri.core.coring import Tiers
from requests import HTTPError

from signify.app.clienting import SignifyClient


ADMIN_URL = os.environ.get("KERIA_ADMIN_URL", "http://keria:3901")
BOOT_URL = os.environ.get("KERIA_BOOT_URL", "http://keria:3903")
QVI_DATA_DIR = Path(os.environ.get("QVI_DATA_DIR", "/qvi-data"))
SCENARIO = os.environ.get("SCENARIO", "signifypy")
ARTIFACT = QVI_DATA_DIR / f"{SCENARIO}-delegation.json"

GEDA_PRE = os.environ.get("GEDA_PRE")
GEDA_OOBI = os.environ.get("GEDA_OOBI")

WIL_PRE = "BLskRTInXnMxWaGqcpSyMgo0nYbalW99cGZESrz3zapM"
WIL_OOBI = f"http://witness-demo:5643/oobi/{WIL_PRE}/controller?name=Wil&tag=witness"
QVI_WITS = [WIL_PRE]

QVI_NAME = "signifypy-qvi"
MEMBERS = [
    ("signifypy-qar1", "pyqar1abcdefghijklmno"),
    ("signifypy-qar2", "pyqar2abcdefghijklmno"),
    ("signifypy-qar3", "pyqar3abcdefghijklmno"),
]

POLL_INTERVAL = float(os.environ.get("SIGNIFYPY_DELEGATION_POLL_INTERVAL", "0.5"))
DEFAULT_TIMEOUT = float(os.environ.get("SIGNIFYPY_DELEGATION_TIMEOUT", "180"))


def log(message: str) -> None:
    print(f"[signifypy] {message}", flush=True)


def require_env() -> tuple[str, str]:
    if not GEDA_PRE:
        raise RuntimeError("GEDA_PRE is required")
    if not GEDA_OOBI:
        raise RuntimeError("GEDA_OOBI is required")
    return GEDA_PRE, GEDA_OOBI


def wait_until(fetch, ready, *, describe: str, timeout: float = DEFAULT_TIMEOUT):
    deadline = time.monotonic() + timeout
    last_value: Any = None
    last_error: str | None = None
    while True:
        try:
            value = fetch()
        except HTTPError as err:
            last_error = str(err)
        else:
            last_value = value
            if ready(value):
                return value

        if time.monotonic() >= deadline:
            raise TimeoutError(
                f"timed out waiting for {describe}; "
                f"last_error={last_error!r}; last_value={last_value!r}"
            )
        time.sleep(POLL_INTERVAL)


def connect_client(passcode: str) -> SignifyClient:
    client = SignifyClient(
        passcode=passcode,
        tier=Tiers.low,
        url=ADMIN_URL,
        boot_url=BOOT_URL,
    )
    try:
        client.connect()
    except Exception:
        client.boot()
        client.connect()
    return client


def clients() -> list[SignifyClient]:
    return [connect_client(passcode) for _, passcode in MEMBERS]


def wait_operation(client: SignifyClient, operation: dict | str, *, timeout: float = DEFAULT_TIMEOUT) -> dict:
    if isinstance(operation, str):
        operation = client.operations().get(operation)
    result = client.operations().wait(
        operation,
        timeout=timeout,
        interval=POLL_INTERVAL,
        max_interval=POLL_INTERVAL,
        backoff=1.0,
    )
    name = result.get("name")
    if name:
        try:
            client.operations().delete(name)
        except HTTPError:
            pass
    return result


def resolve_oobi(client: SignifyClient, oobi: str, alias: str) -> dict:
    return wait_operation(client, client.oobis().resolve(oobi, alias=alias))


def matching_unread_notes(client: SignifyClient, route: str) -> list[dict]:
    return [
        note
        for note in client.notifications().list()["notes"]
        if note.get("r") is False and note.get("a", {}).get("r") == route
    ]


def wait_for_multisig_request(client: SignifyClient, route: str) -> list[dict]:
    note = wait_until(
        lambda: matching_unread_notes(client, route),
        bool,
        describe=f"{route} notification",
    )[-1]
    client.notifications().mark(note["i"])
    return wait_until(
        lambda: client.groups().get_request(note["a"]["d"]),
        lambda request: bool(request) and request[0]["exn"]["r"] == route,
        describe=f"{route} request payload",
    )


def normalize_state(value):
    if isinstance(value, list):
        if len(value) != 1:
            raise AssertionError(f"expected one key state, got {len(value)}")
        return value[0]
    return value


def get_states(client: SignifyClient, prefixes: list[str]) -> list[dict]:
    return [normalize_state(client.keyStates().get(prefix)) for prefix in prefixes]


def wait_for_identifier_oobi(client: SignifyClient, name: str, role: str) -> str:
    return wait_until(
        lambda: client.oobis().get(name, role=role)["oobis"],
        bool,
        describe=f"{role} OOBI for {name}",
    )[0]


def wait_for_end_role(client: SignifyClient, name: str, eid: str) -> None:
    wait_until(
        lambda: client.endroles().list(name=name, role="agent"),
        lambda roles: any(role.get("eid") == eid for role in roles),
        describe=f"agent end role for {name}",
    )


def ensure_witness(client: SignifyClient) -> None:
    resolved = getattr(client, "_qvi_witnesses", set())
    if WIL_PRE not in resolved:
        resolve_oobi(client, WIL_OOBI, "wil")
        resolved.add(WIL_PRE)
        client._qvi_witnesses = resolved


def create_identifier(client: SignifyClient, name: str) -> dict:
    try:
        return client.identifiers().get(name)
    except HTTPError:
        pass

    ensure_witness(client)
    _, _, operation = client.identifiers().create(name, toad="1", wits=QVI_WITS)
    wait_operation(client, operation)
    _, _, endrole_op = client.identifiers().addEndRole(name=name, eid=client.agent.pre)
    wait_operation(client, endrole_op)
    wait_for_end_role(client, name, client.agent.pre)
    wait_for_identifier_oobi(client, name, "agent")
    aid = client.identifiers().get(name)
    log(f"created member {name}: {aid['prefix']}")
    return aid


def resolve_agent_oobi(source: SignifyClient, source_name: str, target: SignifyClient) -> None:
    oobi = wait_for_identifier_oobi(source, source_name, "agent")
    resolve_oobi(target, oobi, source_name)


def exchange_agent_oobis(participants: list[tuple[SignifyClient, str]]) -> None:
    for i, (source, source_name) in enumerate(participants):
        for target, target_name in participants[i + 1 :]:
            resolve_agent_oobi(source, source_name, target)
            resolve_agent_oobi(target, target_name, source)


def messagize(serder, sigs, *, seal=None):
    sigers = [csigning.Siger(qb64=sig) for sig in sigs]
    return eventing.messagize(serder=serder, sigers=sigers, seal=seal)


def start_multisig_incept(
    client: SignifyClient,
    *,
    group_name: str,
    local_member_name: str,
    participants: list[str],
    delpre: str,
) -> tuple[dict, serdering.SerderKERI]:
    member = client.identifiers().get(local_member_name)
    states = get_states(client, participants)
    serder, sigs, operation = client.identifiers().create(
        group_name,
        algo=Algos.group,
        mhab=member,
        isith=["1/3", "1/3", "1/3"],
        nsith=["1/3", "1/3", "1/3"],
        toad=1,
        wits=QVI_WITS,
        delpre=delpre,
        states=states,
        rstates=states,
    )
    smids = [state["i"] for state in states]
    recipients = [prefix for prefix in participants if prefix != member["prefix"]]
    client.exchanges().send(
        local_member_name,
        "multisig",
        sender=member,
        route="/multisig/icp",
        payload={"gid": serder.pre, "smids": smids, "rmids": smids},
        embeds={"icp": messagize(serder, sigs)},
        recipients=recipients,
    )
    return operation, serder


def accept_multisig_incept(
    client: SignifyClient,
    *,
    group_name: str,
    local_member_name: str,
) -> dict:
    request = wait_for_multisig_request(client, "/multisig/icp")
    exn = request[0]["exn"]
    icp = exn["e"]["icp"]
    smids = exn["a"]["smids"]
    rmids = exn["a"].get("rmids", smids)
    member = client.identifiers().get(local_member_name)
    states = get_states(client, smids)
    rstates = get_states(client, rmids)
    serder, sigs, operation = client.identifiers().create(
        group_name,
        algo=Algos.group,
        mhab=member,
        isith=icp["kt"],
        nsith=icp["nt"],
        toad=int(icp["bt"]),
        wits=icp["b"],
        delpre=icp.get("di"),
        states=states,
        rstates=rstates,
    )
    recipients = [prefix for prefix in smids if prefix != member["prefix"]]
    client.exchanges().send(
        local_member_name,
        "multisig",
        sender=member,
        route="/multisig/icp",
        payload={"gid": serder.pre, "smids": smids, "rmids": rmids},
        embeds={"icp": messagize(serder, sigs)},
        recipients=recipients,
    )
    return operation


def assert_multisig_members(client: SignifyClient, group_name: str, expected: list[str]) -> None:
    members = client.identifiers().members(group_name)
    signing = {member["aid"] for member in members["signing"]}
    rotation = {member["aid"] for member in members["rotation"]}
    if signing != set(expected):
        raise AssertionError(f"unexpected signing members: {signing}")
    if rotation != set(expected):
        raise AssertionError(f"unexpected rotation members: {rotation}")


def wait_for_group_state(client: SignifyClient, group_name: str, qvi_pre: str, geda_pre: str) -> dict:
    return wait_until(
        lambda: client.identifiers().get(group_name),
        lambda group: (
            group["prefix"] == qvi_pre
            and group["state"]["di"] == geda_pre
            and group["state"]["s"] == "0"
        ),
        describe=f"delegated group state for {group_name}",
    )


def clear_group_operation(client: SignifyClient, operation_name: str, group_name: str, qvi_pre: str, geda_pre: str) -> None:
    wait_for_group_state(client, group_name, qvi_pre, geda_pre)
    try:
        operation = client.operations().get(operation_name)
    except HTTPError:
        return

    if operation.get("done") is True:
        wait_operation(client, operation)
        return

    # KERIA 0.4.x can leave the group op pending after the identifier state is
    # materialized. The state check above is the convergence proof for this test.
    client.operations().delete(operation_name)


def unfinished_operations(client: SignifyClient) -> list[dict]:
    operations = client.operations().list()
    if isinstance(operations, dict):
        operations = operations.get("ops", operations.get("operations", []))
    return [operation for operation in operations if operation.get("done") is False]


def setup() -> None:
    geda_pre, geda_oobi = require_env()
    QVI_DATA_DIR.mkdir(parents=True, exist_ok=True)
    cs = clients()
    names = [name for name, _ in MEMBERS]

    member_aids = [create_identifier(client, name) for client, name in zip(cs, names)]
    exchange_agent_oobis(list(zip(cs, names)))
    for client in cs:
        resolve_oobi(client, geda_oobi, "geda")

    participants = [aid["prefix"] for aid in member_aids]
    operation0, serder = start_multisig_incept(
        cs[0],
        group_name=QVI_NAME,
        local_member_name=names[0],
        participants=participants,
        delpre=geda_pre,
    )
    operations = [operation0]
    for client, name in zip(cs[1:], names[1:]):
        operations.append(
            accept_multisig_incept(
                client,
                group_name=QVI_NAME,
                local_member_name=name,
            )
        )

    artifact = {
        "client": "signifypy",
        "gedaPre": geda_pre,
        "qviPre": serder.pre,
        "members": participants,
        "anchor": {"i": serder.pre, "s": "0", "d": serder.pre},
        "operations": [operation["name"] for operation in operations],
    }
    ARTIFACT.write_text(json.dumps(artifact, indent=2, sort_keys=True) + "\n")
    log(f"wrote delegated inception artifact for {serder.pre}")


def complete() -> None:
    if not ARTIFACT.exists():
        raise RuntimeError(f"missing artifact {ARTIFACT}")
    artifact = json.loads(ARTIFACT.read_text())
    cs = clients()
    names = [name for name, _ in MEMBERS]
    geda_pre = artifact["gedaPre"]
    qvi_pre = artifact["qviPre"]
    expected_anchor = {"i": qvi_pre, "s": "0", "d": qvi_pre}
    if artifact.get("anchor") != expected_anchor:
        raise AssertionError(f"unexpected delegation anchor: {artifact.get('anchor')}")

    for client in cs:
        state = normalize_state(wait_operation(client, client.keyStates().query(pre=geda_pre, sn="1"))["response"])
        if state["i"] != geda_pre or int(state["s"]) < 1:
            raise AssertionError(f"GEDA query did not converge on approval interaction: {state}")
    for client, operation_name in zip(cs, artifact["operations"]):
        clear_group_operation(client, operation_name, QVI_NAME, qvi_pre, geda_pre)

    groups = [client.identifiers().get(QVI_NAME) for client in cs]
    prefixes = {group["prefix"] for group in groups}
    if prefixes != {qvi_pre}:
        raise AssertionError(f"QVI prefixes did not converge: {prefixes}")
    for group in groups:
        if group["state"]["di"] != geda_pre:
            raise AssertionError(f"QVI {group['prefix']} has di={group['state']['di']}, expected {geda_pre}")
        if group["state"]["s"] != "0":
            raise AssertionError(f"QVI {group['prefix']} sequence is {group['state']['s']}, expected 0")

    assert_multisig_members(cs[0], QVI_NAME, artifact["members"])
    incomplete = {name: unfinished_operations(client) for client, name in zip(cs, names)}
    incomplete = {name: ops for name, ops in incomplete.items() if ops}
    if incomplete:
        raise AssertionError(f"incomplete operations remain: {incomplete}")
    log("PASS: SignifyPy multisig delegate approved by KERIpy multisig KLI delegator")


def main() -> None:
    if len(sys.argv) != 2 or sys.argv[1] not in {"setup", "complete"}:
        raise SystemExit("usage: delegation.py setup|complete")
    if sys.argv[1] == "setup":
        setup()
    else:
        complete()


if __name__ == "__main__":
    main()

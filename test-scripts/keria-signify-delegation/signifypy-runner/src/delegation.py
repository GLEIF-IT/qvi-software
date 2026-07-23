import json
import os
import sys
import time
from pathlib import Path

from keri.app.keeping import Algos
from keri.core import eventing, serdering
from keri.core import signing as csigning
from keri.core.coring import Tiers
from requests import HTTPError
from signify.app.clienting import SignifyClient


ADMIN_URL = os.environ.get("KERIA_ADMIN_URL", "http://keria:3901")
BOOT_URL = os.environ.get("KERIA_BOOT_URL", "http://keria:3903")
ARTIFACT = Path(os.environ.get("QVI_DATA_DIR", "/qvi-data")) / "signifypy-delegation.json"

WIL_PRE = "BLskRTInXnMxWaGqcpSyMgo0nYbalW99cGZESrz3zapM"
WIL_OOBI = f"http://witness-demo:5643/oobi/{WIL_PRE}/controller?name=Wil&tag=witness"
QVI_WITS = [WIL_PRE]
QVI_THRESHOLD = ["1/2", "1/2", "1/2"]
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


def wait_until(fetch, ready, *, describe: str, timeout: float = DEFAULT_TIMEOUT):
    deadline = time.monotonic() + timeout
    last_value = None
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
    return result


def resolve_oobi(client: SignifyClient, oobi: str, alias: str) -> None:
    wait_operation(client, client.oobis().resolve(oobi, alias=alias))


def wait_for_multisig_request(client: SignifyClient, route: str) -> list[dict]:
    note = wait_until(
        lambda: [
            note
            for note in client.notifications().list()["notes"]
            if note.get("r") is False and note.get("a", {}).get("r") == route
        ],
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


def wait_for_identifier_oobi(client: SignifyClient, name: str) -> str:
    return wait_until(
        lambda: client.oobis().get(name, role="agent")["oobis"],
        bool,
        describe=f"agent OOBI for {name}",
    )[0]


def create_identifier(client: SignifyClient, name: str) -> dict:
    resolve_oobi(client, WIL_OOBI, "wil")
    _, _, operation = client.identifiers().create(name, toad="1", wits=QVI_WITS)
    wait_operation(client, operation)
    _, _, operation = client.identifiers().addEndRole(name=name, eid=client.agent.pre)
    wait_operation(client, operation)
    wait_for_identifier_oobi(client, name)
    aid = client.identifiers().get(name)
    log(f"created member {name}: {aid['prefix']}")
    return aid


def exchange_agent_oobis(participants: list[tuple[SignifyClient, str]]) -> None:
    for i, (source, source_name) in enumerate(participants):
        for target, target_name in participants[i + 1 :]:
            resolve_oobi(target, wait_for_identifier_oobi(source, source_name), source_name)
            resolve_oobi(source, wait_for_identifier_oobi(target, target_name), target_name)


def messagize(serder, sigs):
    sigers = [csigning.Siger(qb64=sig) for sig in sigs]
    return eventing.messagize(serder=serder, sigers=sigers)


def start_multisig_incept(
    client: SignifyClient, local_member_name: str, participants: list[str], delpre: str
) -> serdering.SerderKERI:
    member = client.identifiers().get(local_member_name)
    states = get_states(client, participants)
    serder, sigs, _ = client.identifiers().create(
        QVI_NAME,
        algo=Algos.group,
        mhab=member,
        isith=QVI_THRESHOLD,
        nsith=QVI_THRESHOLD,
        toad=1,
        wits=QVI_WITS,
        delpre=delpre,
        states=states,
        rstates=states,
    )
    smids = [state["i"] for state in states]
    client.exchanges().send(
        local_member_name,
        "multisig",
        sender=member,
        route="/multisig/icp",
        payload={"gid": serder.pre, "smids": smids, "rmids": smids},
        embeds={"icp": messagize(serder, sigs)},
        recipients=[prefix for prefix in participants if prefix != member["prefix"]],
    )
    return serder


def accept_multisig_incept(client: SignifyClient, local_member_name: str) -> None:
    request = wait_for_multisig_request(client, "/multisig/icp")
    exn = request[0]["exn"]
    icp = exn["e"]["icp"]
    smids = exn["a"]["smids"]
    rmids = exn["a"].get("rmids", smids)
    member = client.identifiers().get(local_member_name)
    serder, sigs, _ = client.identifiers().create(
        QVI_NAME,
        algo=Algos.group,
        mhab=member,
        isith=icp["kt"],
        nsith=icp["nt"],
        toad=int(icp["bt"]),
        wits=icp["b"],
        delpre=icp.get("di"),
        states=get_states(client, smids),
        rstates=get_states(client, rmids),
    )
    client.exchanges().send(
        local_member_name,
        "multisig",
        sender=member,
        route="/multisig/icp",
        payload={"gid": serder.pre, "smids": smids, "rmids": rmids},
        embeds={"icp": messagize(serder, sigs)},
        recipients=[prefix for prefix in smids if prefix != member["prefix"]],
    )


def wait_for_group_state(client: SignifyClient, qvi_pre: str, geda_pre: str) -> dict:
    return wait_until(
        lambda: client.identifiers().get(QVI_NAME),
        lambda group: (
            group["prefix"] == qvi_pre
            and group["state"]["di"] == geda_pre
            and group["state"]["s"] == "0"
            and group["state"]["kt"] == QVI_THRESHOLD
            and group["state"]["nt"] == QVI_THRESHOLD
        ),
        describe=f"2-of-3 delegated group state for {QVI_NAME}",
    )


def assert_multisig_members(client: SignifyClient, expected: list[str]) -> None:
    members = client.identifiers().members(QVI_NAME)
    for role in ("signing", "rotation"):
        actual = {member["aid"] for member in members[role]}
        if actual != set(expected):
            raise AssertionError(f"unexpected {role} members: {actual}, expected={set(expected)}")


def setup() -> None:
    geda_pre = os.environ.get("GEDA_PRE")
    geda_oobi = os.environ.get("GEDA_OOBI")
    if not geda_pre or not geda_oobi:
        raise RuntimeError("GEDA_PRE and GEDA_OOBI are required")
    cs = clients()
    names = [name for name, _ in MEMBERS]
    aids = [create_identifier(client, name) for client, name in zip(cs, names)]
    exchange_agent_oobis(list(zip(cs, names)))
    for client in cs:
        resolve_oobi(client, geda_oobi, "geda")

    participants = [aid["prefix"] for aid in aids]
    serder = start_multisig_incept(cs[0], names[0], participants, geda_pre)
    for client, name in zip(cs[1:], names[1:]):
        accept_multisig_incept(client, name)

    artifact = {"gedaPre": geda_pre, "qviPre": serder.pre, "members": participants}
    ARTIFACT.write_text(json.dumps(artifact, indent=2, sort_keys=True) + "\n")
    log(f"wrote delegated inception artifact for {serder.pre}")


def complete() -> None:
    if not ARTIFACT.exists():
        raise RuntimeError(f"missing artifact {ARTIFACT}")
    artifact = json.loads(ARTIFACT.read_text())
    cs = clients()
    geda_pre = artifact["gedaPre"]
    qvi_pre = artifact["qviPre"]

    for client in cs:
        state = normalize_state(
            wait_operation(client, client.keyStates().query(pre=geda_pre, sn="1"))["response"]
        )
        if state["i"] != geda_pre or int(state["s"]) < 1:
            raise AssertionError(f"GEDA query did not converge on approval interaction: {state}")

    groups = [wait_for_group_state(client, qvi_pre, geda_pre) for client in cs]
    for (name, _), group in zip(MEMBERS, groups):
        state = group["state"]
        log(
            f"verified {name}: prefix={group['prefix']} di={state['di']} "
            f"s={state['s']} kt={state['kt']} nt={state['nt']}"
        )
    assert_multisig_members(cs[0], artifact["members"])
    log("PASS: SignifyPy 2-of-3 multisig delegate approved by KERIpy multisig KLI delegator")


def main() -> None:
    if len(sys.argv) != 2 or sys.argv[1] not in {"setup", "complete"}:
        raise SystemExit("usage: delegation.py setup|complete")
    setup() if sys.argv[1] == "setup" else complete()


if __name__ == "__main__":
    main()

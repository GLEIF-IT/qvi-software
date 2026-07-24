import {
    assertMultisigExn,
    assertMultisigIcp,
    assertMultisigIss,
    assertMultisigRev,
    assertMultisigRot,
    assertMultisigRpy,
    assertMultisigVcp,
    MULTISIG_EXN_ROUTE,
    MULTISIG_ICP_ROUTE,
    MULTISIG_ISS_ROUTE,
    MULTISIG_REV_ROUTE,
    MULTISIG_ROT_ROUTE,
    MULTISIG_RPY_ROUTE,
    MULTISIG_VCP_ROUTE,
    type ExchangeResourceV1,
} from 'signify-ts';

export type CoordinatedEventRoute =
    | typeof MULTISIG_ICP_ROUTE
    | typeof MULTISIG_ROT_ROUTE
    | typeof MULTISIG_RPY_ROUTE
    | typeof MULTISIG_VCP_ROUTE
    | typeof MULTISIG_ISS_ROUTE
    | typeof MULTISIG_REV_ROUTE
    | typeof MULTISIG_EXN_ROUTE;

export function coordinatedEventDigest(
    exchange: ExchangeResourceV1,
    route: CoordinatedEventRoute
): string {
    switch (route) {
        case MULTISIG_ICP_ROUTE:
            return assertMultisigIcp(exchange).exn.e.icp.d;
        case MULTISIG_ROT_ROUTE:
            return assertMultisigRot(exchange).exn.e.rot.d;
        case MULTISIG_RPY_ROUTE:
            return assertMultisigRpy(exchange).exn.e.rpy.d;
        case MULTISIG_VCP_ROUTE:
            return assertMultisigVcp(exchange).exn.e.vcp.d;
        case MULTISIG_ISS_ROUTE:
            return assertMultisigIss(exchange).exn.e.iss.d;
        case MULTISIG_REV_ROUTE:
            return assertMultisigRev(exchange).exn.e.rev.d;
        case MULTISIG_EXN_ROUTE:
            return assertMultisigExn(exchange).exn.e.exn.d;
    }
}

export function assertCoordinatedEventDigest(
    exchange: ExchangeResourceV1,
    route: CoordinatedEventRoute,
    expectedDigest: string
): void {
    const actualDigest = coordinatedEventDigest(exchange, route);
    const eventMatches = actualDigest === expectedDigest;
    if (eventMatches === false) {
        throw new Error(
            `${route} coordinated event ${actualDigest} does not match local event ${expectedDigest}`
        );
    }
}

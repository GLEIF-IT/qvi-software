interface AgentEndpointReference {
    eid: string;
}

function compareText(left: string, right: string): number {
    return left.localeCompare(right);
}

function compareAgentEndpointsByEid<
    Endpoint extends AgentEndpointReference,
>(left: Endpoint, right: Endpoint): number {
    return compareText(left.eid, right.eid);
}

export function sortAids(aids: readonly string[]): string[] {
    return [...aids].sort(compareText);
}

export function sortOobis(oobis: readonly string[]): string[] {
    return [...oobis].sort(compareText);
}

export function sortAgentEndpointsByEid<
    Endpoint extends AgentEndpointReference,
>(endpoints: readonly Endpoint[]): Endpoint[] {
    return [...endpoints].sort(compareAgentEndpointsByEid);
}

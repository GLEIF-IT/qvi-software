const EXPECTED_OBSERVER_COUNT = 3;

function sorted(values: string[]): string[] {
    return [...values].sort();
}

export function assertExactObserverSet(
    observedAids: string[],
    expectedAids: string[],
    evidenceName: string
): void {
    const expectedObserversAreInvalid =
        expectedAids.length !== EXPECTED_OBSERVER_COUNT ||
        new Set(expectedAids).size !== EXPECTED_OBSERVER_COUNT ||
        expectedAids.some((aid) => aid.length === 0);
    if (expectedObserversAreInvalid) {
        throw new Error(
            `${evidenceName} requires exactly three unique expected observer AIDs`
        );
    }

    const observedObserversAreInvalid =
        observedAids.length !== EXPECTED_OBSERVER_COUNT ||
        new Set(observedAids).size !== EXPECTED_OBSERVER_COUNT ||
        observedAids.some((aid) => aid.length === 0);
    const observerSetsMatch =
        JSON.stringify(sorted(observedAids)) ===
        JSON.stringify(sorted(expectedAids));
    if (observedObserversAreInvalid || observerSetsMatch === false) {
        throw new Error(
            `${evidenceName} observers ${JSON.stringify(observedAids)} do not match expected member AIDs ${JSON.stringify(expectedAids)}`
        );
    }
}

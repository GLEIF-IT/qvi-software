export type ChallengeParticipant =
    | 'gar1'
    | 'gar2'
    | 'lar1'
    | 'lar2'
    | 'qar1'
    | 'qar2'
    | 'qar3'
    | 'person';

export interface ChallengeRelationship {
    name: string;
    participants: readonly [
        ChallengeParticipant,
        ChallengeParticipant,
    ];
}

export interface ChallengeDirection {
    relationship: string;
    from: ChallengeParticipant;
    to: ChallengeParticipant;
    key: string;
}

export interface ChallengeDirectionReceipt {
    relationship: string;
    from: ChallengeParticipant;
    to: ChallengeParticipant;
}

export const CHALLENGE_RELATIONSHIPS: readonly ChallengeRelationship[] = [
    {name: 'GAR1-GAR2', participants: ['gar1', 'gar2']},
    {name: 'LAR1-LAR2', participants: ['lar1', 'lar2']},
    {name: 'QAR1-QAR2', participants: ['qar1', 'qar2']},
    {name: 'QAR1-QAR3', participants: ['qar1', 'qar3']},
    {name: 'QAR2-QAR3', participants: ['qar2', 'qar3']},
    {name: 'GAR1-QAR1', participants: ['gar1', 'qar1']},
    {name: 'QAR1-LAR1', participants: ['qar1', 'lar1']},
    {name: 'QAR1-Person', participants: ['qar1', 'person']},
] as const;

export function challengeDirectionKey(
    from: ChallengeParticipant,
    to: ChallengeParticipant
): string {
    return `${from}->${to}`;
}

export function expectedChallengeDirections(): ChallengeDirection[] {
    return CHALLENGE_RELATIONSHIPS.flatMap((relationship) => {
        const [first, second] = relationship.participants;
        return [
            {
                relationship: relationship.name,
                from: first,
                to: second,
                key: challengeDirectionKey(first, second),
            },
            {
                relationship: relationship.name,
                from: second,
                to: first,
                key: challengeDirectionKey(second, first),
            },
        ];
    });
}

export function validateChallengeReceipts(
    receipts: ChallengeDirectionReceipt[]
): ChallengeDirection[] {
    const expected = expectedChallengeDirections();
    const actualKeys = receipts.map(
        (receipt) =>
            `${receipt.relationship}:${challengeDirectionKey(receipt.from, receipt.to)}`
    );
    const expectedReceiptKeys = new Set(
        expected.map(
            (direction) =>
                `${direction.relationship}:${direction.key}`
        )
    );
    const uniqueActualKeys = new Set(actualKeys);

    const receiptCountIsInvalid =
        receipts.length !== expected.length;
    const receiptIsDuplicated =
        uniqueActualKeys.size !== actualKeys.length;
    const unexpectedDirectionExists = actualKeys.some(
        (key) => expectedReceiptKeys.has(key) === false
    );
    const expectedDirectionIsMissing = [...expectedReceiptKeys].some(
        (key) => uniqueActualKeys.has(key) === false
    );

    const graphIsInvalid =
        receiptCountIsInvalid ||
        receiptIsDuplicated ||
        unexpectedDirectionExists ||
        expectedDirectionIsMissing;
    if (graphIsInvalid) {
        throw new Error(
            `Challenge receipts do not match the required 8 relationships and 16 directed exchanges: ${actualKeys.join(',')}`
        );
    }

    return expected;
}

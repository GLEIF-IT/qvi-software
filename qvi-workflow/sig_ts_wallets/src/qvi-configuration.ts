export const QVI_MEMBER_COUNT = 3;
export const QVI_INITIAL_SEQUENCE = '0';
export const QVI_SIGNING_THRESHOLD = [
    '1/3',
    '1/3',
    '1/3',
] as const;
export const QVI_NEXT_THRESHOLD = [
    '1/3',
    '1/3',
    '1/3',
] as const;

export function qviSigningThreshold(): string[] {
    return [...QVI_SIGNING_THRESHOLD];
}

export function qviNextThreshold(): string[] {
    return [...QVI_NEXT_THRESHOLD];
}

import {AidInfo} from './qvi-data';
import {readParticipantConfig} from './cli.ts';

export function parseAidInfo(aidInfoArg: string) {
    const argumentIsConfigPath = aidInfoArg.includes('|') === false;
    if (argumentIsConfigPath) {
        const config = readParticipantConfig(aidInfoArg);
        return {
            QAR1: config.participants.qar1,
            QAR2: config.participants.qar2,
            QAR3: config.participants.qar3,
            PERSON: config.participants.person,
        };
    }

    const aids = aidInfoArg.split(','); // expect format: "qar1|Alice|salt1,qar2|Bob|salt2,qar3|Charlie|salt3,person|David|salt4"
    const aidObjs: AidInfo[] = aids.map((aidInfo) => {
        const [position, name, salt] = aidInfo.split('|'); // expect format: "qar1|Alice|salt1"
        return {position, name, salt};
    });

    const QAR1 = requireAid(aidObjs, 'qar1');
    const QAR2 = requireAid(aidObjs, 'qar2');
    const QAR3 = requireAid(aidObjs, 'qar3');
    const PERSON = requireAid(aidObjs, 'person');
    return {QAR1, QAR2, QAR3, PERSON};
}

function requireAid(aids: AidInfo[], position: string): AidInfo {
    const aid = aids.find((candidate) => candidate.position === position);
    const aidIsMissing =
        aid === undefined || aid.name.length === 0 || aid.salt.length === 0;
    if (aidIsMissing) {
        throw new Error(`Missing or invalid participant ${position}`);
    }
    return aid;
}

export function parseAidInfoSingleSig(aidInfoArg: string) {
    const aids = aidInfoArg.split(','); // expect format: "qar|Alice|salt,person|David|salt,qvi|QVI|salt"
    const aidObjs: AidInfo[] = aids.map((aidInfo) => {
        const [position, name, salt] = aidInfo.split('|'); // expect format: "qar1|Alice|salt1"
        return {position, name, salt};
    });

    const QAR = requireAid(aidObjs, 'qar');
    const PERSON = requireAid(aidObjs, 'person');
    const QVI = requireAid(aidObjs, 'qvi');
    return {QAR, PERSON, QVI};
}

export function createTimestamp() {
    return new Date().toISOString().replace('Z', '000+00:00');
}

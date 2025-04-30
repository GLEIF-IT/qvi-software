import {AidInfo} from './qvi-data';

export function parseAidInfo(aidInfoArg: string) {
    const aids = aidInfoArg.split(','); // expect format: "qar1|Alice|salt1,qar2|Bob|salt2,qar3|Charlie|salt3,person|David|salt4"
    const aidObjs: AidInfo[] = aids.map((aidInfo) => {
        const [position, name, salt] = aidInfo.split('|'); // expect format: "qar1|Alice|salt1"
        return {position, name, salt};
    });

    const QAR1 = aidObjs.find((aid) => aid.position === 'qar1') as AidInfo;
    const QAR2 = aidObjs.find((aid) => aid.position === 'qar2') as AidInfo;
    const QAR3 = aidObjs.find((aid) => aid.position === 'qar3') as AidInfo;
    const PERSON = aidObjs.find((aid) => aid.position === 'person') as AidInfo;
    return {QAR1, QAR2, QAR3, PERSON};
}

export function createTimestamp() {
    return new Date().toISOString().replace('Z', '000+00:00');
}
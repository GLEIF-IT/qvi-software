// parse the OOBIs for the GEDA, GIDA, and Sally needed for initial setup
import {OobiInfo} from "../qvi-data.ts";

export function parseOobiInfoSingleSig(oobiInfoArg: string) {
    const oobiInfos = oobiInfoArg.split(','); // expect format: "gar|OOBI,lar|OOBI,direct-sally|OOBI"
    const oobiObjs: OobiInfo[] = oobiInfos.map((aidInfo) => {
        const [position, oobi] = aidInfo.split('|'); // expect format: "gar1|OOBI"
        return {position, oobi};
    });

    const GAR = oobiObjs.find((oobiInfo) => oobiInfo.position === 'gar') as OobiInfo;
    const LAR = oobiObjs.find((oobiInfo) => oobiInfo.position === 'lar') as OobiInfo;
    const SALLY = oobiObjs.find((oobiInfo) => oobiInfo.position === 'direct-sally') as OobiInfo;
    return {GAR, LAR, SALLY};
}

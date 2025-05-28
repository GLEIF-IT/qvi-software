// parse the OOBIs for the GEDA, GIDA, and Sally needed for initial setup
import {OobiInfo} from "../qvi-data.ts";

export function parseOobiInfoSingleSig(oobiInfoArg: string) {
    const oobiInfos = oobiInfoArg.split(','); // expect format: "gar1|OOBI,gar2|OOBI,lar1|OOBI,lar1|OOBI,sally|OOBI"
    const oobiObjs: OobiInfo[] = oobiInfos.map((aidInfo) => {
        const [position, oobi] = aidInfo.split('|'); // expect format: "gar1|OOBI"
        return {position, oobi};
    });

    const GAR = oobiObjs.find((oobiInfo) => oobiInfo.position === 'gar') as OobiInfo;
    const LAR = oobiObjs.find((oobiInfo) => oobiInfo.position === 'lar') as OobiInfo;
    const SALLY = oobiObjs.find((oobiInfo) => oobiInfo.position === 'directSally') as OobiInfo;
    return {GAR, LAR, SALLY};
}
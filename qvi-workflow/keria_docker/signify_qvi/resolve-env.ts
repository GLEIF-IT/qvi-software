export type TestEnvironmentPreset = 'local' | 'docker' | 'docker-witness-split';

export interface TestEnvironment {
    preset: TestEnvironmentPreset;
    url: string;
    bootUrl: string;
    vleiServerUrl: string;
    witnessUrls: string[];
    witnessIds: string[];
}

// All six demo witnesses
const WAN = 'BBilc4-L3tFUnfM_wJr4S4OJanAv_VmF_dJNN6vkf2Ha';
const WIL = 'BLskRTInXnMxWaGqcpSyMgo0nYbalW99cGZESrz3zapM';
const WES = 'BIKKuvBwpmDVA4Ds-EpL5bt9OqPzWPja2LigFYZN2YfX';
const WIT = 'BM35JN8XeJSEfpxopjn5jr7tAHCE5749f0OobhMLCorE';
const WUB = 'BIj15u5V11bkbtAxMA7gcNJZcax-7TgaBMLsQnMHpYHP';
const WYZ = 'BF2rZTW79z4IXocYRQnjjsOuvFUQv-ptCf8Yltd7PfsM';

export function resolveEnvironment(
    input?: TestEnvironmentPreset
): TestEnvironment {
    const preset = input ?? process.env.TEST_ENVIRONMENT ?? 'docker';
    const host = 'http://127.0.0.1'
    switch (preset) {
        case 'local':    
            return {
                preset: preset,
                url: `${host}:3901`,
                bootUrl: `${host}:3903`,
                vleiServerUrl: `${host}:7723`,
                witnessUrls: [
                    `${host}:5642`,
                    `${host}:5643`,
                    `${host}:5644`,
                ],
                witnessIds: [WAN, WIL, WES],
            };
        case 'docker':
            return {
                preset: preset,
                url: `${host}:3901`,     //Because keria is called from the
                bootUrl: `${host}:3903`, //host not from within the docker network
                witnessUrls: [
                    'http://witness-demo:5642',
                    'http://witness-demo:5643',
                    'http://witness-demo:5644',
                ],
                witnessIds: [WAN, WIL, WES],
                vleiServerUrl: 'http://vlei-server:7723',
            };
        case 'docker-witness-split':
            return {
                preset: preset,
                url: `${host}:3901`,     // Because keria is called from the
                bootUrl: `${host}:3903`, // host not from within the docker network
                witnessUrls: [
                    'http://gar-witnesses:5642',    // wan
                    'http://qar-witnesses:5643',    // wil
                    'http://person-witnesses:5644', // wes
                    'http://sally-witnesses:5645'   // wit
                ],
                witnessIds: [WAN, WIL, WES, WIT],
                vleiServerUrl: 'http://vlei-server:7723',
            };
        default:
            throw new Error(`Unknown test environment preset '${preset}'`);
    }
}

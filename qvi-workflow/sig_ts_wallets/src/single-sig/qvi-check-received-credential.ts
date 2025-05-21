import {checkReceivedCredentialSingleSig} from "./qvi-operations-single-sig.ts";

/*
Checks the specified multisig with the first QAR to see if a credential has been received
 */

// process arguments
const args = process.argv.slice(2);
const env = args[0] as 'local' | 'docker';
const aidInfoArg = args[1]
const credSAID = args[2]

const exists: string = await checkReceivedCredentialSingleSig(aidInfoArg, credSAID, env);
console.log(exists);

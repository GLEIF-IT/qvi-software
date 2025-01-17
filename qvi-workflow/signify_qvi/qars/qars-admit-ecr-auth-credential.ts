import {checkReceivedCredential} from "../qvi-operations.ts";

// process arguments
const args = process.argv.slice(2);
const env = args[0] as 'local' | 'docker';
const multisigName = args[1]
const aidInfoArg = args[2]
const credSAID = args[3]

const exists: string = await checkReceivedCredential(multisigName, aidInfoArg, credSAID, env);
console.log(exists);

import {checkIssuedCredential, checkReceivedCredential} from "../qvi-operations.ts";

/*
Checks the specified multisig with the first QAR to see if a credential has been received
 */

// process arguments
const args = process.argv.slice(2);
const env = args[0] as 'local' | 'docker';
const multisigName = args[1]
const aidInfoArg = args[2]
const issueePre = args[3]
const schemaSAID = args[4]

const exists: string = await checkIssuedCredential(multisigName, aidInfoArg, schemaSAID, issueePre, env);
console.log(exists);

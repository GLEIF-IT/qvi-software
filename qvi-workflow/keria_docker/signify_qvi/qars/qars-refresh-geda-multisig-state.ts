import {refreshGedaMultisigstate} from "../qvi-operations.ts";

const args = process.argv.slice(2);
const env = args[0] as 'local' | 'docker';
const aidInfoArg = args[1];
const gedaPrefix = args[2];

await refreshGedaMultisigstate(aidInfoArg, gedaPrefix, env);
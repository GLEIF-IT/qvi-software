# Tested Stacks - Running Tests README

Stack A:
- Compose file: `stack_A-docker-compose.yaml`
- KERIpy 1.1.30
- KERIA 0.2.0-rc2
- vLEI-server 0.2.2
- SignifyTS 0.3.0-rc1

# Important Points

## Running a Test Stack

1. Navigate to the `qvi-software/tested-stacks` directory.
2. Choose a compose file and run the following command:
    ```bash
    docker-compose -f stack_A-docker-compose.yaml up
    ```
3. Go to your SignifyTS repository and configure the environment with the following URLs:
   ```typescript
   // from the resolve-env.ts file
   // change WAN, WIL, and WES to the eps, kap, and phi witness AIDs:
   const WAN = 'BGWIB2O7akfFYh6VSnbMaYqD8YEWxo84bCYv3guBYGkc';
   const WIL = 'BAhH1rBtSc4sNrSkaQLm4V7hw6xRRXsvX-kiSyC2VbdN';
   const WES = 'BE7Q6dQRkft4R_4g7yfiEZKOnRLzT6duQHdRnWqALRRU';
   // Change the vLEI server URL and the witness URLs to the below:
   vleiServerUrl: 'http://vlei-server:7723',
   witnessUrls: [
       'http://wit-eps:5642',
       'http://wit-kap:5643',
       'http://wit-phi:5644',
   ],
   ```
4. In the witness.test.ts file change the WITNESS_AID to the "eps" witness AID: 
   ```typescript
   const WITNESS_AID = 'BGWIB2O7akfFYh6VSnbMaYqD8YEWxo84bCYv3guBYGkc';
   ```
5. Then set the TEST_ENVIRONMENT variable appropriately for your environment. \
   I am using the `local` so in my WebStorm run configuration I set the following: \
   `TEST_ENVIRONMENT=local`
6. Then run the test with either NodeJS or your run configuration in your IDE.
7. The test should complete successfully.
8. To clean up after running a test run the following command to delete all containers and the volumes they depend on:
    ```bash
    docker-compose -f stack_A-docker-compose.yaml down -v
    ```

## Use Custom Witness Salts and Passcodes

WARNING: If you are using this repository as a template for your own deployment then **remember** to change the witness salts and passcodes, otherwise your deployment will be insecure.

# References
## Docker Hub Images
- [weboftrust/keria][HUB_KERIA] 
  - The KERIA Agent server compatible with the signing-at-the-edge library SignifyTS.
- [weboftrust/keri][HUB_KERI] 
  - The KERIpy core library including the KLI command line interface and witnesses.
- [gleif/vlei][HUB_VLEI]
  - The ACDC schema caching server. Could be replaced with an NGINX server or something similar that can host static JSON files. 
- [weboftrust/signify-ts][LIB_SIGNIFY]
  -  The signing-at-the-edge library compatible with the KERIA agent server.

[DOCKER_HOST_NET]: https://docs.docker.com/engine/network/drivers/host/
[HUB_KERIA]: https://hub.docker.com/r/weboftrust/keria
[HUB_KERI]: https://hub.docker.com/r/weboftrust/keri
[HUB_VLEI]: https://hub.docker.com/r/gleif/vlei
[LIB_SIGNIFY]: https://github.com/WebOfTrust/signify-ts
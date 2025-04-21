# KLI Only QVI Workflow Script

### Overview

This script simulates the QVI workflow end to end including creating delegated identifiers, key 
rotation, issuing credentials, and presenting credentials to the vLEI Reporting API.

### Using this Script

This is designed to work with a local installation of the necessary components.
This script uses only KERIpy keystores for all participants.
It does not use KERIA or SignifyTS for the QVI and Person AIDs, rather it uses KERIpy.

To run this script you need to run local witnesses and a local vLEI-Server as shown below.
You also need the Sally CLI installed and available on your path.

#### Witnesses

This command runs the six demonstration witnesses.

WARNING: This script REQUIRES KERIpy 1.2.6 witnesses. Due to the delegation ceremony change of 2024 this script will not work with 1.1.x KERIpy witnesses.

```bash
# From within a dedicated Python virtual environment (virtualenv)
# From the root directory of the KERIpy repo
kli witness demo
```

#### vLEI-Server

To provide a local vLEI ACDC Schema host so that ACDC Schema OOBIs resolve then from the vLEI repo run:
```bash
# From within a dedicated Python virtual environment (virtualenv)
# From the root directory of the vlei repo
vLEI-server -s ./schema/acdc -c ./samples/acdc/ -o ./samples/oobis/
```

This script runs the "sally" program so it must be installed and available on the path

## Workflow Steps

In the `qvi-workflow-kli.sh` file, using the KERIpy KLI, the Sally CLI, and the vLEI-Server binary the following steps are performed:
1. Script initializes with keystore names, passcodes, and salts, identifier aliases, credential registry names, and ACDC Schema SAIDs. 
2. Preconfigures each keystore during identifier creation with the OOBI URLs for the following
   witnesses and ACDC schemas:
   - Witness Wan with identifier `BBilc4-L3tFUnfM_wJr4S4OJanAv_VmF_dJNN6vkf2Ha` on port 5642
   - Witness Wil with idendifier `BLskRTInXnMxWaGqcpSyMgo0nYbalW99cGZESrz3zapM` on port 5643
   - Witness Wes with identifier `BIKKuvBwpmDVA4Ds-EpL5bt9OqPzWPja2LigFYZN2YfX` on port 5644
   - ACDC Schema for QVI Credential with SAID `EBfdlu8R27Fbx-ehrqwImnK-8Cm79sqbAQ4MmvEAYqao`
   - ACDC Schema for LE Credential with SAID `ENPXp1vQzRF6JwIuS-mp2U8Uf1MoADoP_GqQ62VsDZWY`
   - ACDC Schema for OOR Authorization Credential with SAID `EKA57bKBKxr_kN7iN5i7lMUxpMG-s19dRcmov1iDxz-E`
   - ACDC Schema for ECR Authorization Credential with SAID `EH6ekLjSr8V32WyFbGe1zXjTzFs9PkTYmupJ9H65O14g`
   - ACDC Schema for OOR Credential with SAID `EBNaNu-M9P5cgrnfl2Fvymy4E_jvxxyjb70PRtiANlJy`
   - ACDC Schema for ECR Credential with SAID `EEy9PkikFcANV1l7EHukCeXqrzT1hNZjGlUk7wuMO5jw`
3. Creates single signature identifiers including the following:
   - GLEIF Authorized Representative #1 (GAR1): accolon
   - GLEIF Authorized Representative #2 (GAR2): bedivere
   - Legal Entity Authorized Representative #1 (LAR1): elaine
   - Legal Entity Authorized Representative #2 (LAR2): finn
   - QVI Authorized Representative #1 (QAR1): galahad
   - QVI Authorized Representative #2 (QAR2): lancelot
   - Person receiving OOR and ECR credentials: mordred
4. Connects all keystores to each other by resolving witness mailbox OOBI URLs.
5. Performs challenge and response between GARs, QARs, and LARs to simulate out of band identifier control verification.
6. Creates the multisignature identity for the GLEIF External Delegated AID (GEDA).
7. 
# Required Hackathon Participant Capabilities

The following capability sets are required for various technology integration levels for hackathon participants ranging from minimal to advanced.

## Capability Levels

- **Minimal**: (Receiving only) Participants run only a verifier yet no issuers and use 3rd party wallet, witness, and issuer infrastructure. 
    - Example: Use vLEI QVI wallet (Provenant Origin, or other) and a LAR as issuer of OORs and ECRs and present these credentials through Origin to the minimal verifier.
- **Basic Issuance**: Participants run their own issuers, yet may leverage a 3rd party wallet and associated infrastructure such as
    - Example: Using Provenant's Origin software participants may issue their own type of credential chained to a LE, OOR, or ECR credential and present that to a verifier.
- **Advanced Self-Managed Issuance**: Participants build their own wallet software and run their own infrastructure, either receiving LE, OOR, and ECR credentials or chaining to those credentials and presenting them to a verifier.
    - Example: Using self-developed, self-managed wallet software along with open source, common infrastructure component deployment a participant uses a highly customized credential workflow building upon the vLEI ecosystem credentials including one or more of QVI, LE, OOR, or ECR credentials in an advanced issuance and presentation workflow. 
- **Expert Thresholded Authorization**: Participants use a mix of multisig signing, witness receipting, or watcher verification thresholds (under development) to perform advanced, multi-party verification and authorization workflows.
    - Example: Building on the Advanced Self-Managed Issuance a participant uses multi-signature wallets for multi-party workflows where multiple parties, such as 2 of 3 or other M of N, sign events, along with witness thresholds for event receipting and verification, and (when available later in 2025) watcher verification thresholds for advanced verification above and beyond the minimal verifier.
        - Caution: This advanced workflow, if watchers are desired, is under development. It is recommended for 2025 to omit usage of advanced watcher threshold verification unless you know exactly what you are doing and can assist in the open source development of watchers, which are expected in Q3-Q4 2025. It is best if you avoid this unless an absolute requirement for your use case. Talk to someone at GLEIF or in the KERI community about your use case if you think you need this. You most likely do not need this for the hackathon, yet it would be useful for a production deployment to scale thresholded (highly secure) verifications.

## Capability Sets by Level (See the Capability List Reference)

### Minimal

This minimal setup maximally relies upon 3rd party infrastructure and software. 
Participants run only a verifier yet no issuers and use 3rd party wallet, witness, and issuer infrastructure.

#### Self-managed (one)
- Verifier Deployment (customized by participant)

#### 3rd Party Provided (most)
- Passcodes
- Identifier creation and rotation, including multisig
- Witness Infrastructure Deployment
- Mailbox Infrastructure Deployment (usually combined with witnesses)
- Watcher Deployment
- Observer Deployment (under development)
- OOBI generation and resolution
- Signing challenges and responses
- Key State Refreshes (when keys are rotated)
- Delegation
- Credential Registries and Credential Issuances, Presentations, and Revocations
- Issuance of OOR, and ECR credentials

### Basic Issuance

Under basic issuance the participant assumes the responsibility of issuing either vLEI credentials or credentials chained to those credentials.
All the wallet software and infrastructure is still provided by 3rd parties while the participant is responsible for the verifier. 

#### Self-managed (some)
- Verifier Deployment (customized by participant)
- **Issuance of OOR, and ECR credentials, or other credentials chained to these credentials**

#### 3rd Party Provided (most)
- Passcodes
- Identifier creation and rotation, including multisig
- Witness Infrastructure Deployment
- Mailbox Infrastructure Deployment (usually combined with witnesses)
- Watcher Deployment
- Observer Deployment (under development)
- OOBI generation and resolution
- Signing challenges and responses
- Key State Refreshes (when keys are rotated)
- Delegation
- Credential Registries and Credential Issuances, Presentations, and Revocations

### Advanced Self-Managed Issuance

With advanced issuance the learning and effort curve are much steeper as the responsibility for wallet software and infrastructure deployment shifts from the 3rd party to the participant.
Only those teams with significant experience and resources should consider attempting this level of integration.

#### Self-managed (all)
- Passcodes
- Identifier creation and rotation, including multisig
- Witness Infrastructure Deployment
- Mailbox Infrastructure Deployment (usually combined with witnesses)
- OOBI generation and resolution
- Signing challenges and responses
- Key State Refreshes (when keys are rotated)
- Delegation
- Credential Registries and Credential Issuances, Presentations, and Revocations
- Verifier Deployment (customized by participant)
- Issuance of OOR, and ECR credentials, or other credentials chained to these credentials

#### 3rd Party Provided (none)

### Expert Thresholded Authorization

At the expert level the participant is expected to be able to deploy and manage all the infrastructure 
and software components necessary to run a fully functional vLEI ecosystem that builds upon the existing vLEI credentials.

The main reason participants may want this level of integration is to leverage advanced multi-party workflows and advanced verification workflows and scaling patterns.
This is a very advanced level of integration and should only be attempted by those with significant experience and resources.

You may notice that only the watcher and observer capabilities are added to the expert level. It uses mostly the same capabilities as the advanced level yet the largest differences here will be with
multisignature signing and thresholded verification capabilities.

#### Self-managed (all)
- Passcodes
- Identifier creation and rotation, including multisig
- Witness Infrastructure Deployment
- Mailbox Infrastructure Deployment (usually combined with witnesses)
- **Watcher Deployment**
- **Observer Deployment (under development)**
- OOBI generation and resolution
- Signing challenges and responses
- Key State Refreshes (when keys are rotated)
- Delegation
- Credential Registries and Credential Issuances, Presentations, and Revocations
- Verifier Deployment (customized by participant)
- Issuance of OOR, and ECR credentials, or other credentials chained to these credentials


#### 3rd Party Provided (none)

# Capability List Reference

#### Passcodes
  - Securely generate cryptographic passcode
  - Provide ability to securely enter cryptographic passcode into Signify in a web application
#### Identities
  - Create Single Signature Identity
  - Rotate keys for single signature identity
  - Create Multi Signature Identifier with appropriate signing weights per multi-sig member.
  - Rotate keys for multi signature identifier
#### OOBIs
  - Generate OOBI URL for single signature identity
  - Resolve an OOBI URL for a single signature identity
  - Generate OOBI URL for a multi signature identity
  - Resolve an OOBI URL for a multi signature identity
#### Signing Challenges and Responses
  - Generate a signing challenge with a single signature identity
  - Respond to a signing challenge with a single signature identity
#### Key State Refreshes
  - Perform key state refresh for single signature identity
  - Perform key state refresh for multi signature identity
#### Delegation
  - Perform delegation request from multi signature delegate identity to multi signature delegator identity.
#### ACDC Registries and Credentials
  - Create a credential registry for a single signature identity
  - Create credential registry for a multi signature identity
  - Resolve schema OOBI URLs for ACDC Credential Schemas (specifically the QVI, LE, OOR Auth, ECR Auth, OOR, and ECR ACDC schemas)
  - Create and issue an ACDC credential for QVI, LE, OOR Auth, ECR Auth, OOR, and ECR credentials
  - Present (IPEX Grant) an ACDC credential to an recipient (verifier or other identity)
  - Receive (IPEX Admit) an ACDC credential as a recipient
  - Revoke an ACDC credential and present the revoked credential to a recipient (verifier or other identity)

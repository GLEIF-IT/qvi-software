# Required QVI Capabilities

The following capabilities are required for the QVI workflow:

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

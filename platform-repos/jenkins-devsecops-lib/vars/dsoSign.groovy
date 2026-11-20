// DSO-10 / DSO-11 Sign and verify with Cosign and a cloud KMS key.
//
// JENKINS-ONLY difference: public Sigstore (Fulcio) trusts a fixed list of
// OIDC issuers (GitHub Actions, GitLab.com, ...). A self-hosted Jenkins issuer
// is not on it, so keyless signing is not available. The private key stays in
// the cloud KMS; Jenkins only gets permission to ask KMS to sign, through the
// short-lived OIDC credentials from dsoCloud().
//
// KMS URIs Cosign understands:
//   awskms:///alias/devsecops-signing
//   azurekms://<vault>.vault.azure.net/devsecops-signing
//   gcpkms://projects/<p>/locations/<l>/keyRings/<r>/cryptoKeys/<k>
//   hashivault://devsecops-signing     (use for OCI Vault setups via Vault transit)

def sign(String ref, String kmsKey, Map attest = [:]) {
    sh "cosign sign --yes --key '${kmsKey}' '${ref}'"
    attest.each { type, file ->
        sh "cosign attest --yes --key '${kmsKey}' --type '${type}' --predicate '${file}' '${ref}'"
    }
}

def verify(String ref, String kmsKey, List attestTypes = []) {
    sh "cosign verify --key '${kmsKey}' '${ref}' > /dev/null"
    attestTypes.each { type ->
        sh "cosign verify-attestation --key '${kmsKey}' --type '${type}' '${ref}' > /dev/null"
    }
}

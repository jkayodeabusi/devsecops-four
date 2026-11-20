// DSO-13 Short-lived cloud credentials from a Jenkins-issued OIDC token.
//
// JENKINS-ONLY: Jenkins itself is the identity provider. The OpenID Connect
// Provider plugin mints a fresh id token per withCredentials block, signed by
// this controller, with issuer https://<jenkins-url>/oidc. You publish that
// issuer, design the `sub` claim (Manage Jenkins > Security > OpenID Connect >
// Claim templates), and each cloud trusts it like any external IdP.
// Keep the plugin current: CVE-2025-47884 (versions up to 96.vee8ed882ec4d)
// let crafted builds influence token claims.
//
// Credentials (kind "OpenID Connect id token as file"), one per cloud:
//   oidc-aws    audience sts.amazonaws.com
//   oidc-azure  audience api://AzureADTokenExchange
//   oidc-gcp    audience https://iam.googleapis.com/projects/<n>/locations/global/workloadIdentityPools/<pool>/providers/<provider>
//   oidc-oci    audience as configured on the OCI identity domain token exchange
//
// Usage: dsoCloud('aws', [roleArn: '...']) { sh 'aws eks update-kubeconfig ...' }

def call(String cloud, Map cfg = [:], Closure body) {
    switch (cloud) {
        case 'aws':
            // The AWS CLI and SDKs read these two variables and call
            // AssumeRoleWithWebIdentity themselves.
            withCredentials([file(credentialsId: 'oidc-aws', variable: 'AWS_WEB_IDENTITY_TOKEN_FILE')]) {
                withEnv(["AWS_ROLE_ARN=${cfg.roleArn}", "AWS_ROLE_SESSION_NAME=jenkins-${env.BUILD_TAG}"]) {
                    body()
                }
            }
            break
        case 'azure':
            withCredentials([file(credentialsId: 'oidc-azure', variable: 'AZ_TOKEN_FILE')]) {
                sh """
                    az login --service-principal -u '${cfg.clientId}' -t '${cfg.tenantId}' \\
                      --federated-token "\$(cat "\$AZ_TOKEN_FILE")" --output none
                """
                body()
            }
            break
        case 'gcp':
            withCredentials([file(credentialsId: 'oidc-gcp', variable: 'ID_TOKEN_FILE')]) {
                writeFile file: "${env.WORKSPACE_TMP}/gcp-creds.json", text: """{
  "type": "external_account",
  "audience": "${cfg.audience}",
  "subject_token_type": "urn:ietf:params:oauth:token-type:jwt",
  "token_url": "https://sts.googleapis.com/v1/token",
  "service_account_impersonation_url": "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${cfg.serviceAccount}:generateAccessToken",
  "credential_source": { "file": "${ID_TOKEN_FILE}", "format": { "type": "text" } }
}"""
                withEnv(["GOOGLE_APPLICATION_CREDENTIALS=${env.WORKSPACE_TMP}/gcp-creds.json"]) {
                    sh 'gcloud auth login --brief --cred-file="$GOOGLE_APPLICATION_CREDENTIALS"'
                    body()
                }
            }
            break
        case 'oci':
            // OCI IAM token exchange: trade the Jenkins JWT for a short-lived
            // OCI user principal session token, then call the OCI CLI with it.
            withCredentials([file(credentialsId: 'oidc-oci', variable: 'OCI_JWT_FILE')]) {
                body()
            }
            break
        default:
            error "dsoCloud: unknown cloud '${cloud}'"
    }
}

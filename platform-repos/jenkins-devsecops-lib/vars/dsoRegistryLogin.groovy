// Registry login with short-lived credentials (no stored registry password).
// Writes a Docker config into the workspace and points DOCKER_CONFIG at it,
// so every container in the pod (BuildKit, Trivy, Cosign) shares the login;
// each container has its own $HOME, so ~/.docker would not be shared.
// Run inside container('cloud'). Example for Amazon ECR; for ACR, GAR or OCIR
// swap the token command (az acr login --expose-token, gcloud auth
// print-access-token, OCI auth token).
def call(String roleArn, String region, String registry) {
    dsoCloud('aws', [roleArn: roleArn]) {
        sh """
            set -eu
            mkdir -p "\$DOCKER_CONFIG"
            pw=\$(aws ecr get-login-password --region '${region}')
            printf '{"auths":{"%s":{"auth":"%s"}}}' '${registry}' \\
              "\$(printf 'AWS:%s' "\$pw" | base64 -w0)" > "\$DOCKER_CONFIG/config.json"
        """
    }
}

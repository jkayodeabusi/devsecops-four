#!/usr/bin/env bash
# =============================================================================
#  cloud-login.sh <aws|azure|gcp|oci>      (DSO-13)
#  SOURCE this file (". scripts/cloud-login.sh aws"), don't run it: it exports
#  KUBECONFIG and cloud credentials into the calling shell.
#
#  Swaps the pipeline's OIDC token for short-lived cloud credentials, then
#  writes a kubeconfig for the cluster. No cloud key is stored anywhere.
#  All files go into a private temp dir that the caller deletes on exit.
# =============================================================================
set -euo pipefail

CLOUD="${1:?usage: . scripts/cloud-login.sh aws|azure|gcp|oci}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

LOGIN_DIR="$(mktemp -d)"
chmod 700 "$LOGIN_DIR"
trap 'rm -rf "$LOGIN_DIR"' EXIT     # tokens and keys never outlive the job
export KUBECONFIG="$LOGIN_DIR/kubeconfig"

need() { command -v "$1" >/dev/null || { echo "cloud-login: '$1' is not installed in this job image" >&2; exit 3; }; }
need kubectl
need jq

# Azure DevOps + Azure: AzureCLI@2 has already logged in with the service
# connection, so there is no token to swap.
if [ "$CLOUD" = "azure" ] && [ -n "${TF_BUILD:-}" ]; then
  JWT=""
else
  JWT="$("$HERE/ci-jwt.sh" "$CLOUD")"
fi

case "$CLOUD" in
  # ---------------------------------------------------------------------------
  aws)
    need aws
    : "${AWS_ROLE_ARN:?}" "${AWS_REGION:?}" "${EKS_CLUSTER:?}"
    # The AWS CLI calls sts:AssumeRoleWithWebIdentity itself when these are set,
    # and refreshes the credentials for every later command (including kubectl).
    printf '%s' "$JWT" > "$LOGIN_DIR/aws.jwt"
    export AWS_WEB_IDENTITY_TOKEN_FILE="$LOGIN_DIR/aws.jwt"
    AWS_ROLE_SESSION_NAME="ci-deploy-$(date +%s)"
    export AWS_ROLE_SESSION_NAME
    aws sts get-caller-identity --query Arn --output text
    aws eks update-kubeconfig --name "$EKS_CLUSTER" --region "$AWS_REGION" --kubeconfig "$KUBECONFIG"
    ;;

  # ---------------------------------------------------------------------------
  azure)
    need az
    : "${AKS_RESOURCE_GROUP:?}" "${AKS_CLUSTER:?}"
    if [ -n "$JWT" ]; then
      : "${AZURE_CLIENT_ID:?}" "${AZURE_TENANT_ID:?}"
      export AZURE_CONFIG_DIR="$LOGIN_DIR/azure"       # keep the login out of $HOME
      az login --service-principal -u "$AZURE_CLIENT_ID" -t "$AZURE_TENANT_ID" \
        --federated-token "$JWT" --output none
    fi
    [ -n "${AZURE_SUBSCRIPTION_ID:-}" ] && az account set --subscription "$AZURE_SUBSCRIPTION_ID"
    az aks get-credentials -g "$AKS_RESOURCE_GROUP" -n "$AKS_CLUSTER" --file "$KUBECONFIG" --overwrite-existing
    # Entra ID-enabled clusters: let kubectl reuse the az login for its token.
    if command -v kubelogin >/dev/null; then kubelogin convert-kubeconfig -l azurecli; fi
    ;;

  # ---------------------------------------------------------------------------
  gcp)
    need gcloud
    : "${GCP_WIF_AUDIENCE:?}" "${GCP_SERVICE_ACCOUNT:?}" "${GCP_PROJECT_ID:?}" "${GKE_CLUSTER:?}" "${GKE_LOCATION:?}"
    export CLOUDSDK_CONFIG="$LOGIN_DIR/gcloud"         # keep the login out of $HOME
    printf '%s' "$JWT" > "$LOGIN_DIR/gcp.jwt"
    # An "external_account" credential: Google STS swaps the JWT for a token,
    # then impersonates the deploy service account.
    jq -n --arg aud "$GCP_WIF_AUDIENCE" --arg sa "$GCP_SERVICE_ACCOUNT" --arg f "$LOGIN_DIR/gcp.jwt" '{
      type: "external_account",
      audience: $aud,
      subject_token_type: "urn:ietf:params:oauth:token-type:jwt",
      token_url: "https://sts.googleapis.com/v1/token",
      service_account_impersonation_url: ("https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/" + $sa + ":generateAccessToken"),
      credential_source: { file: $f, format: { type: "text" } }
    }' > "$LOGIN_DIR/gcp-creds.json"
    gcloud auth login --brief --cred-file="$LOGIN_DIR/gcp-creds.json"
    gcloud container clusters get-credentials "$GKE_CLUSTER" --location "$GKE_LOCATION" --project "$GCP_PROJECT_ID"
    ;;

  # ---------------------------------------------------------------------------
  oci)
    need oci
    need openssl
    : "${OCI_DOMAIN_URL:?}" "${OCI_EXCHANGE_CLIENT_ID:?}" "${OCI_EXCHANGE_CLIENT_SECRET:?}"
    : "${OCI_TENANCY_OCID:?}" "${OCI_REGION:?}" "${OKE_CLUSTER_OCID:?}"
    # 1. A throwaway key pair; OCI binds the session token to its public key.
    openssl genrsa -out "$LOGIN_DIR/oci.pem" 2048 2>/dev/null
    chmod 600 "$LOGIN_DIR/oci.pem"
    pub="$(openssl rsa -in "$LOGIN_DIR/oci.pem" -pubout 2>/dev/null | sed '1d;$d' | tr -d '\n')"
    # 2. Token exchange: JWT in, UPST (user principal session token) out.
    #    The client ID/secret belong to the identity domain's exchange app; they
    #    can only exchange tokens through the trust, not call OCI APIs.
    curl -sSf "${OCI_DOMAIN_URL%/}/oauth2/v1/token" \
      -u "${OCI_EXCHANGE_CLIENT_ID}:${OCI_EXCHANGE_CLIENT_SECRET}" \
      --data-urlencode 'grant_type=urn:ietf:params:oauth:grant-type:token-exchange' \
      --data-urlencode 'requested_token_type=urn:oci:token-type:oci-upst' \
      --data-urlencode "public_key=${pub}" \
      --data-urlencode "subject_token=${JWT}" \
      --data-urlencode 'subject_token_type=jwt' | jq -er .token > "$LOGIN_DIR/oci.token"
    # 3. An OCI CLI profile that uses the session token.
    fp="$(openssl rsa -in "$LOGIN_DIR/oci.pem" -pubout -outform DER 2>/dev/null | openssl md5 -c | awk '{print $2}')"
    cat > "$LOGIN_DIR/oci.config" <<EOF
[DEFAULT]
tenancy=${OCI_TENANCY_OCID}
region=${OCI_REGION}
key_file=${LOGIN_DIR}/oci.pem
fingerprint=${fp}
security_token_file=${LOGIN_DIR}/oci.token
EOF
    chmod 600 "$LOGIN_DIR/oci.config"
    export OCI_CLI_CONFIG_FILE="$LOGIN_DIR/oci.config"
    export OCI_CLI_AUTH=security_token
    oci ce cluster create-kubeconfig --cluster-id "$OKE_CLUSTER_OCID" --file "$KUBECONFIG" \
      --region "$OCI_REGION" --token-version 2.0.0 --kube-endpoint PUBLIC_ENDPOINT
    ;;

  *)
    echo "cloud-login: unknown cloud '$CLOUD'" >&2
    exit 2
    ;;
esac

unset JWT
echo "cloud-login: logged in to $CLOUD; kubectl context: $(kubectl config current-context)"

#!/usr/bin/env bash
# =============================================================================
#  ci-jwt.sh <aws|azure|gcp|oci>
#  Prints this pipeline run's OIDC token (a JWT) for the given cloud.
#  It is the ONLY platform-specific piece of the deploy: everything after it
#  (cloud-login.sh, deploy.sh) is identical on all four CI/CD platforms.
# =============================================================================
set -euo pipefail

cloud="${1:?usage: ci-jwt.sh aws|azure|gcp|oci}"

# Each cloud expects its own audience ("aud" claim) in the token.
case "$cloud" in
  aws)   aud="sts.amazonaws.com" ;;
  azure) aud="api://AzureADTokenExchange" ;;
  gcp)   aud="${GCP_WIF_AUDIENCE:?set GCP_WIF_AUDIENCE to //iam.googleapis.com/projects/<n>/locations/global/workloadIdentityPools/<pool>/providers/<provider>}" ;;
  oci)   aud="${OCI_JWT_AUDIENCE:?set OCI_JWT_AUDIENCE to the audience on your OCI identity propagation trust}" ;;
  *)     echo "ci-jwt.sh: unknown cloud '$cloud'" >&2; exit 2 ;;
esac

if [ -n "${GITHUB_ACTIONS:-}" ]; then
  # GitHub: the runner exposes a token endpoint when the job has `id-token: write`.
  : "${ACTIONS_ID_TOKEN_REQUEST_URL:?add 'permissions: id-token: write' to this job}"
  curl -sSf -H "Authorization: bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" \
    "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=$(jq -rn --arg a "$aud" '$a|@uri')" | jq -r .value

elif [ -n "${GITLAB_CI:-}" ]; then
  # GitLab: the job declares `id_tokens: CLOUD_ID_TOKEN: aud: $OIDC_AUDIENCE`.
  printf '%s' "${CLOUD_ID_TOKEN:?declare id_tokens: CLOUD_ID_TOKEN in this job}"

elif [ -n "${TF_BUILD:-}" ]; then
  # Azure DevOps: AzureCLI@2 with addSpnToEnvironment: true exposes $idToken.
  # Its audience is always api://AzureADTokenExchange, so AWS, GCP and OCI
  # must trust that audience for the service connection's issuer and subject.
  if [ "$aud" != "api://AzureADTokenExchange" ]; then
    echo "ci-jwt.sh: note: Azure DevOps tokens use audience api://AzureADTokenExchange" >&2
  fi
  printf '%s' "${idToken:?run inside AzureCLI@2 with addSpnToEnvironment: true}"

elif [ -n "${JENKINS_URL:-}" ]; then
  # Jenkins: withCredentials([file(credentialsId: "oidc-${cloud}", variable: 'OIDC_TOKEN_FILE')])
  cat "${OIDC_TOKEN_FILE:?wrap this step in withCredentials with an OIDC id token file}"

else
  echo "ci-jwt.sh: not running on GitHub Actions, GitLab CI, Azure DevOps or Jenkins" >&2
  exit 2
fi

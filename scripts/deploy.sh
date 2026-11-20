#!/usr/bin/env bash
# =============================================================================
#  deploy.sh <aws|azure|gcp|oci> <image@sha256:digest>      (DSO-13)
#  The same deploy on every CI/CD platform and every cloud:
#    1. refuse anything that is not a digest reference
#    2. log in to the cloud with the pipeline's OIDC token
#    3. apply the manifests with the signed digest
#    4. wait for the rollout; roll back automatically if it fails
#  Signature verification (DSO-11) runs BEFORE this script, in the pipeline.
# =============================================================================
set -euo pipefail

CLOUD="${1:?usage: deploy.sh aws|azure|gcp|oci IMAGE@sha256:DIGEST}"
REF="${2:?usage: deploy.sh aws|azure|gcp|oci IMAGE@sha256:DIGEST}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S="$HERE/../deploy/k8s"

# 1. Digest only. A tag can be moved to other content after it was scanned and signed.
if ! [[ "$REF" =~ @sha256:[0-9a-f]{64}$ ]]; then
  echo "deploy: refusing '$REF': deploy by digest (image@sha256:...), never by tag" >&2
  exit 1
fi

# 2. Short-lived credentials + kubeconfig (exports KUBECONFIG into this shell).
# shellcheck source-path=SCRIPTDIR source=cloud-login.sh
. "$HERE/cloud-login.sh" "$CLOUD"

# 3. Everything except the deployment first, then the deployment with the digest.
kubectl apply -f "$K8S/namespace.yaml"
kubectl apply -f "$K8S/serviceaccount.yaml" -f "$K8S/service.yaml" -f "$K8S/networkpolicy.yaml"

if [ "$(grep -c '^ *image: ' "$K8S/deployment.yaml")" -ne 1 ]; then
  echo "deploy: expected exactly one image line in deployment.yaml" >&2
  exit 1
fi
sed -E "s#^( *image: ).*#\1${REF}#" "$K8S/deployment.yaml" | kubectl apply -f -

# 4. Wait, and undo a rollout that never becomes healthy.
if ! kubectl -n app rollout status deployment/classic --timeout=5m; then
  echo "deploy: rollout failed; rolling back to the previous version" >&2
  kubectl -n app describe deployment/classic | tail -20 >&2 || true
  kubectl -n app rollout undo deployment/classic
  exit 1
fi

echo "deploy: running $(kubectl -n app get deployment classic -o jsonpath='{.spec.template.spec.containers[0].image}')"

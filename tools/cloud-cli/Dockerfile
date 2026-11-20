# syntax=docker/dockerfile:1
# =============================================================================
#  cloud-cli: the deploy-job image for GitLab and Jenkins (DSO-13)
#  One pinned image with every tool scripts/deploy.sh can need on any cloud:
#  aws, az, gcloud (+ GKE auth plugin), oci, kubectl, kubelogin, cosign, jq.
#  Build it once, push it to your registry, and reference it by digest.
#  Update the versions together, test, then tag a new image version.
# =============================================================================
FROM python:3.12-slim-bookworm@sha256:935c3c5b12357a7e10caa9c1e6ca5692344d97cf229832ef584be2cec9fc03df

ARG KUBECTL_VERSION=1.33.4
ARG KUBELOGIN_VERSION=0.2.10
ARG AWSCLI_VERSION=2.27.0
ARG AZURE_CLI_VERSION=2.75.0
ARG OCI_CLI_VERSION=3.62.0
ARG GCLOUD_VERSION=530.0.0
ARG COSIGN_VERSION=3.1.4

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl jq openssl unzip git \
 && rm -rf /var/lib/apt/lists/*

# kubectl, checked against the published SHA-256
RUN curl -sSfLo /usr/local/bin/kubectl "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
 && echo "$(curl -sSfL "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256")  /usr/local/bin/kubectl" | sha256sum -c - \
 && chmod +x /usr/local/bin/kubectl

# kubelogin (Entra ID login for AKS), checked against its release checksum
RUN curl -sSfLo /tmp/kubelogin.zip "https://github.com/Azure/kubelogin/releases/download/v${KUBELOGIN_VERSION}/kubelogin-linux-amd64.zip" \
 && curl -sSfLo /tmp/kubelogin.sha256 "https://github.com/Azure/kubelogin/releases/download/v${KUBELOGIN_VERSION}/kubelogin-linux-amd64.zip.sha256" \
 && (cd /tmp && sha256sum -c kubelogin.sha256) \
 && unzip -q /tmp/kubelogin.zip -d /tmp/kubelogin \
 && install /tmp/kubelogin/bin/linux_amd64/kubelogin /usr/local/bin/kubelogin \
 && rm -rf /tmp/kubelogin*

# cosign, checked against the release checksum file
RUN base="https://github.com/sigstore/cosign/releases/download/v${COSIGN_VERSION}" \
 && curl -sSfLo /usr/local/bin/cosign "$base/cosign-linux-amd64" \
 && curl -sSfLo /tmp/cosign_checksums.txt "$base/cosign_checksums.txt" \
 && echo "$(grep ' cosign-linux-amd64$' /tmp/cosign_checksums.txt | cut -d' ' -f1)  /usr/local/bin/cosign" | sha256sum -c - \
 && chmod +x /usr/local/bin/cosign && rm /tmp/cosign_checksums.txt

# AWS CLI v2 (verify the PGP signature too if your policy requires it)
RUN curl -sSfLo /tmp/awscli.zip "https://awscli.amazonaws.com/awscli-exe-linux-x86_64-${AWSCLI_VERSION}.zip" \
 && unzip -q /tmp/awscli.zip -d /tmp && /tmp/aws/install && rm -rf /tmp/aws /tmp/awscli.zip

# Azure CLI and OCI CLI from PyPI, exact versions
RUN pip install --no-cache-dir "azure-cli==${AZURE_CLI_VERSION}" "oci-cli==${OCI_CLI_VERSION}"

# Google Cloud CLI + the GKE auth plugin kubectl needs
RUN curl -sSfLo /tmp/gcloud.tgz "https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-${GCLOUD_VERSION}-linux-x86_64.tar.gz" \
 && tar -xzf /tmp/gcloud.tgz -C /opt && rm /tmp/gcloud.tgz \
 && /opt/google-cloud-sdk/install.sh --quiet --usage-reporting=false --path-update=false \
 && /opt/google-cloud-sdk/bin/gcloud components install gke-gcloud-auth-plugin --quiet \
 && rm -rf /opt/google-cloud-sdk/.install/.backup
ENV PATH="/opt/google-cloud-sdk/bin:${PATH}"

# Never run the deploy as root
RUN useradd --uid 10001 --create-home deployer
USER 10001
WORKDIR /home/deployer

# A CI tool image runs one job and exits; there is no service to health-check.
HEALTHCHECK NONE

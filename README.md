# DevSecOps demo: one app, four CI/CD platforms, four clouds

**By John Kayode-Abusi, cybersecurity practitioner · @SecureTechWithJKA**

The demo project for *Doing DevSecOps Engineering Across Leading CI/CD Workflow*. It's one small Java API (the Order Tracking API) with the same 8-stage secure pipeline on GitHub Actions, GitLab CI/CD, Azure DevOps and Jenkins. It deploys by signed digest to EKS, AKS, GKE or OKE, with no stored cloud keys.

## Layout

| Path | What it is |
|---|---|
| `app-classic/` | The Java 21 API, its tests and its Dockerfile |
| `deploy/k8s/` | Hardened Kubernetes manifests (namespace, deployment, service, network policy) |
| `scripts/` | `deploy.sh`, `cloud-login.sh` and `ci-jwt.sh`: one deploy for every platform and cloud. Also `pin-digests.py` |
| `.github/` | GitHub Actions workflow + Dependabot |
| `.gitlab-ci.yml`, `ci/` | GitLab CI/CD pipeline |
| `azure-pipelines.yml`, `azure-devops/` | Azure DevOps pipeline (extends the security template) + Notation trust policy |
| `Jenkinsfile`, `jenkins/` | Jenkins pipeline + Kubernetes agent pod |
| `platform-repos/` | Files that live in **separate** repos: Azure DevOps template, GitLab policy project, Jenkins shared library and controller config |
| `tools/cloud-cli/` | Deploy-job image with aws, az, gcloud, oci, kubectl, kubelogin, cosign |
| `demo/break-it.sh` | Makes one bad change per scenario so a gate can stop it on camera |
| `Makefile` | Runs every gate locally with Docker |

## Quick start

```bash
make gates            # secrets, SAST, SCA, IaC, tests (same tools and flags as CI)
make release          # build the image, scan it, write the SBOM
make run              # http://localhost:8080/orders/ORD-100001
make pin              # pin every image tag to its digest before the first push
demo/break-it.sh list # the break-it scenarios
```

Then follow the step-by-step guide (the "Demo project" tab in the series guide) to connect one platform and one cloud.

## Status

- Checked here: the app compiles, and the API was exercised over HTTP. Checkov and Trivy config pass on every Dockerfile and manifest (after `make pin`). gitleaks found no secrets. shellcheck, actionlint, yamllint, npm-groovy-lint and a GitLab job-graph check pass.
- Not run here: Maven Central, Semgrep's rule registry and Trivy's vulnerability database were unreachable, so `mvn verify`, `make sast` and `make sca` need a first run on your machine. No pipeline has run on a live platform yet.

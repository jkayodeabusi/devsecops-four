# =============================================================================
#  Run every pipeline gate on your laptop, with the same tools, versions and
#  flags the pipelines use. Only Docker is required.
#    make help        list targets
#    make gates       stages 2 + 3: secrets, SAST, SCA, IaC, tests
#    make release     stage 4: build, image scan, SBOM
#    make run         start the API on http://localhost:8080
# =============================================================================
GITLEAKS_IMAGE ?= ghcr.io/gitleaks/gitleaks:v8.30.1
SEMGREP_IMAGE  ?= semgrep/semgrep:1.185.0
TRIVY_IMAGE    ?= aquasec/trivy:0.76.2
CHECKOV_IMAGE  ?= bridgecrew/checkov:3.4.5
MAVEN_IMAGE    ?= maven:3.9.9-eclipse-temurin-21

APP    := app-classic
IMAGE  ?= order-tracking:local
RUN    := docker run --rm -v "$(CURDIR):/src" -w /src
TRIVY  := docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v "$(CURDIR):/src" -v trivy-cache:/root/.cache -w /src $(TRIVY_IMAGE)

.DEFAULT_GOAL := help
.PHONY: help gates secrets sast sca iac test release image image-scan sbom run pin check-pins clean

help:  ## list targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-12s %s\n", $$1, $$2}'

gates: secrets sast sca iac test  ## stages 2 + 3: every gate a pull request must pass

secrets:  ## DSO-02 gitleaks on the working tree (the pipeline scans the new commits)
	$(RUN) $(GITLEAKS_IMAGE) dir --redact --exit-code 1 --verbose /src

sast:  ## DSO-03 Semgrep with the same pinned rulesets
	$(RUN) -e SEMGREP_SEND_METRICS=off $(SEMGREP_IMAGE) semgrep scan \
	  --config p/default --config p/owasp-top-ten --severity ERROR --error $(APP)

sca:  ## DSO-04 Trivy: fail on fixable High/Critical in dependencies
	$(TRIVY) fs --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 $(APP)

iac:  ## DSO-05 Checkov on the Dockerfiles, Kubernetes manifests and Terraform
	$(RUN) $(CHECKOV_IMAGE) -d /src --framework dockerfile kubernetes terraform --compact

test:  ## DSO-06 unit + integration tests
	$(RUN) -v maven-repo:/root/.m2 $(MAVEN_IMAGE) mvn -B --no-transfer-progress -f $(APP)/pom.xml verify

release: image image-scan sbom  ## stage 4: build the image, scan it, write the SBOM

image:  ## DSO-07 build the container image
	docker build -t $(IMAGE) $(APP)

image-scan:  ## DSO-08 Trivy image scan, same threshold as the pipeline
	$(TRIVY) image --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 $(IMAGE)

sbom:  ## DSO-09 CycloneDX SBOM of the image -> sbom.cdx.json
	$(TRIVY) image --format cyclonedx --output /src/sbom.cdx.json $(IMAGE)

run:  ## start the API locally with the same restrictions as the cluster
	docker run --rm -p 8080:8080 --read-only --tmpfs /tmp --cap-drop ALL \
	  --security-opt no-new-privileges $(IMAGE)

pin:  ## DSO-01 add @sha256 digests to every image tag in the repo
	python3 scripts/pin-digests.py

check-pins:  ## DSO-01 fail if any image is still unpinned
	python3 scripts/pin-digests.py --check

clean:  ## remove build output and the local SBOM
	rm -rf $(APP)/target sbom.cdx.json

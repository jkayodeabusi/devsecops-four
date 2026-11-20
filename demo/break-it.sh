#!/usr/bin/env bash
# =============================================================================
#  demo/break-it.sh <scenario>
#  Makes ONE bad change on its own branch (break/<scenario>) and commits it,
#  so you can push it and show the matching gate stopping it on camera.
#
#    leaked-key       DSO-02  a canary-style AWS key in a config file
#    vuln-lib         DSO-04  log4j-core 2.14.1 (Log4Shell, CVE-2021-44228)
#    open-bucket      DSO-05  Terraform for a public S3 bucket
#    bad-base-image   DSO-08  an old JRE base image with fixable CVEs
#    unpinned-action  GitHub  actions/checkout by tag instead of SHA
#    skip-scan        GitLab  developer disables gitleaks AND leaks a key
#    no-extends       Azure   pipeline stops extending the secure template
#    library-main     Jenkins Jenkinsfile asks for the unreviewed library branch
#    list             show this list
#
#  Undo: git switch main && git branch -D break/<scenario>
#  Run on a throwaway fork or branch; never merge a break/ branch.
# =============================================================================
set -euo pipefail

scenario="${1:-list}"
cd "$(git rev-parse --show-toplevel)"

if [ "$scenario" = "list" ]; then
  sed -n '/^#    [a-z]/s/^#    /  /p' "$0"
  exit 0
fi

if [ -n "$(git status --porcelain)" ]; then
  echo "break-it: commit or stash your changes first" >&2
  exit 1
fi

git switch --quiet -c "break/${scenario}"

# A random key in AWS's format. It is not a real credential, but secret
# scanners cannot tell, which is the point. (gitleaks deliberately ignores
# AWS's documented ...EXAMPLE key, so that one would not trip the gate.)
fake_key() {
  local id secret
  # (pipefail off inside: `head` closing the pipe early is expected here)
  id="AKIA$(set +o pipefail; LC_ALL=C tr -dc 'A-Z2-7' </dev/urandom | head -c 16)"
  secret="$(set +o pipefail; LC_ALL=C tr -dc 'A-Za-z0-9/+' </dev/urandom | head -c 40)"
  mkdir -p app-classic/src/main/resources
  printf 'aws.accessKeyId=%s\naws.secretAccessKey=%s\n' "$id" "$secret" \
    > app-classic/src/main/resources/application.properties
}

case "$scenario" in
  leaked-key)
    fake_key
    gate="DSO-02 gitleaks fails at Source (GitHub push protection may block the push itself)"
    ;;

  vuln-lib)
    # Insert a known-vulnerable dependency right before </dependencies>.
    sed -i 's#^  </dependencies>#    <dependency>\n      <groupId>org.apache.logging.log4j</groupId>\n      <artifactId>log4j-core</artifactId>\n      <version>2.14.1</version>\n    </dependency>\n  </dependencies>#' app-classic/pom.xml
    gate="DSO-04 dependency review / Trivy fs fails on CVE-2021-44228 (Critical)"
    ;;

  open-bucket)
    mkdir -p infra
    cat > infra/public-bucket.tf <<'EOF'
# Demo only: a bucket anyone on the internet can read.
resource "aws_s3_bucket" "reports" {
  bucket = "order-tracking-reports-demo"
}

resource "aws_s3_bucket_public_access_block" "reports" {
  bucket                  = aws_s3_bucket.reports.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_acl" "reports" {
  bucket = aws_s3_bucket.reports.id
  acl    = "public-read"
}
EOF
    gate="DSO-05 Checkov / Trivy config fails on the public bucket"
    ;;

  bad-base-image)
    # Swap only the runtime FROM line for a 2023 JRE full of fixable OS CVEs.
    sed -i -E 's#^FROM gcr\.io/distroless/java21-debian12:nonroot.*#FROM eclipse-temurin:21.0.1_12-jre#' app-classic/Dockerfile
    sed -i -E 's#^USER nonroot#USER 65532#' app-classic/Dockerfile
    gate="DSO-08 Trivy image scan fails at Package; nothing is signed or deployed"
    ;;

  unpinned-action)
    sed -i -E '0,/actions\/checkout@[0-9a-f]{40}.*/s//actions\/checkout@v7/' .github/workflows/devsecops-classic.yml
    gate="GitHub org policy 'require SHA pinning' fails the run before any step executes"
    ;;

  skip-scan)
    # The developer "turns off" the scan in their own file, then leaks a key.
    python3 - <<'EOF'
import re, pathlib
p = pathlib.Path("ci/source.yml")
s = p.read_text()
s = re.sub(r"    - gitleaks git .*?\n(        .*\n)*", "    - echo \"secret scan skipped\"\n", s, count=1)
p.write_text(s)
EOF
    fake_key
    gate="Project gitleaks job passes, but the policy job policy:gitleaks still fails (GitLab Ultimate)"
    ;;

  no-extends)
    cat > azure-pipelines.yml <<'EOF'
# Demo only: a pipeline that skips the security template and deploys directly.
trigger:
  branches:
    include: [main]
stages:
  - stage: Deploy
    jobs:
      - deployment: deploy
        pool:
          vmImage: ubuntu-24.04
        environment: production
        strategy:
          runOnce:
            deploy:
              steps:
                - script: echo "deploying without any security stage"
EOF
    gate="Azure DevOps 'Required template' check on production blocks the deploy"
    ;;

  library-main)
    sed -i "s#@Library('devsecops-lib@v1.4.0') _#@Library('devsecops-lib@main') _#" Jenkinsfile
    gate="Jenkins refuses the library version (allowVersionOverride: false)"
    ;;

  *)
    git switch --quiet - && git branch -D "break/${scenario}" >/dev/null
    echo "break-it: unknown scenario '$scenario' (try: demo/break-it.sh list)" >&2
    exit 2
    ;;
esac

git add -A
git commit --quiet -m "demo(break-it): ${scenario}" -m "Expected: ${gate}"
echo "Committed on branch break/${scenario}"
echo "Expected: ${gate}"
echo "Next: git push -u origin break/${scenario}   then open a pull/merge request into main"

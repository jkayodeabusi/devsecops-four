// DSO-02 Secret scan with gitleaks, run inside container('gitleaks').
// JENKINS-ONLY: this step lives in the security team's shared library, loaded
// with @Library('devsecops-lib@<tag>'). Teams call dsoSecrets(); they cannot
// weaken the flags without a reviewed library release.
def call(Map args = [:]) {
    // Multibranch PR builds set CHANGE_TARGET; scan only the PR's commits there.
    String range = env.CHANGE_TARGET ? "origin/${env.CHANGE_TARGET}..HEAD" : 'HEAD~1..HEAD'
    sh """
        set -eu
        mkdir -p reports
        git config --global --add safe.directory "\$PWD"
        ${env.CHANGE_TARGET ? "git fetch --no-tags origin ${env.CHANGE_TARGET}:refs/remotes/origin/${env.CHANGE_TARGET}" : ''}
        gitleaks git --log-opts='${range}' --redact --exit-code 1 \\
          --report-format sarif --report-path reports/gitleaks.sarif .
    """
}

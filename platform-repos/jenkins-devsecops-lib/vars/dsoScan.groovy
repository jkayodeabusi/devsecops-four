// DSO-03..05 and DSO-08..09 scanners, one entry per tool.
// Each runs inside the matching container of pod-templates/devsecops.yaml and
// writes SARIF to reports/, which recordIssues (Warnings NG) displays.
// The tool's exit code is the gate; the SARIF is the evidence.

def sast() {                                    // DSO-03, container('semgrep')
    sh '''
        mkdir -p reports
        semgrep scan --config p/default --config p/owasp-top-ten \
          --severity ERROR --error --sarif --output reports/semgrep.sarif
    '''
}

def sca(String dir) {                           // DSO-04, container('trivy')
    sh """
        mkdir -p reports
        trivy fs --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 \\
          --format sarif --output reports/trivy-fs.sarif '${dir}'
    """
}

def iac() {                                     // DSO-05, container('checkov')
    sh '''
        mkdir -p reports
        checkov -d . --framework dockerfile kubernetes terraform \
          -o cli -o sarif --output-file-path console,reports
    '''
}

def image(String ref) {                         // DSO-08 + DSO-09, container('trivy')
    sh """
        trivy image --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 '${ref}'
        trivy image --format cyclonedx --output sbom.cdx.json '${ref}'
    """
}

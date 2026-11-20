// =============================================================================
//  DevSecOps demo - Jenkins, classic pipeline (Order Tracking API)
//  Multibranch Pipeline job, Kubernetes agents, declarative syntax.
//
//  Same 8 stages and control IDs as GitHub, GitLab and Azure DevOps:
//    1 Pre-flight DSO-01 · 2 Source DSO-02..05 · 3 Test DSO-06
//    4 Package DSO-07..10 · 5 Release DSO-11..12 · 6 Deploy DSO-13
//    7 Verify DSO-14 · 8 Operate DSO-15 (outside CI)
//
//  JENKINS-ONLY points are marked. The biggest one: you run the platform.
//  Controller hardening, plugin updates, fork-PR trust and the OIDC issuer
//  are your responsibility (see casc/jenkins.yaml and the README).
// =============================================================================

// DSO-01: the security steps come from the shared library, pinned to a
// reviewed release tag. JCasC sets allowVersionOverride: false, so a
// Jenkinsfile cannot swap in an unreviewed branch of the library.
@Library('devsecops-lib@v1.4.0') _

pipeline {
    agent none                       // pods are requested per stage; the approval wait holds no pod

    options {
        // A newer build of the same branch aborts the older one.
        disableConcurrentBuilds(abortPrevious: true)
        buildDiscarder(logRotator(numToKeepStr: '50', artifactNumToKeepStr: '20'))
        timestamps()
        // Fork PRs: in the job's branch source, set "Trust" to users with
        // write permission, so a fork's Jenkinsfile changes are NOT executed.
    }

    environment {
        APP_DIR   = 'app-classic'
        IMAGE     = '123456789012.dkr.ecr.ca-central-1.amazonaws.com/devsecops/classic'
        SIGN_KEY  = 'awskms:///alias/devsecops-signing'
        AWS_ROLE  = 'arn:aws:iam::123456789012:role/jenkins-devsecops'
        AWS_REGION = 'ca-central-1'
        // DSO-13 target. Settings for azure / gcp / oci come from folder properties
        // (see scripts/cloud-login.sh for the variable names each cloud needs).
        CLOUD        = 'aws'
        AWS_ROLE_ARN = 'arn:aws:iam::123456789012:role/jenkins-devsecops'
        EKS_CLUSTER  = 'prod'
    }

    stages {
        stage('CI') {
            agent {
                kubernetes {
                    yamlFile 'jenkins/pod-templates/devsecops.yaml'
                }
            }
            options { timeout(time: 45, unit: 'MINUTES') }
            environment { DOCKER_CONFIG = "${env.WORKSPACE}/.docker" }   // shared by all containers
            stages {
                // =============================================================
                //  STAGE 2 - SOURCE (DSO-02..05): four scanners in parallel
                // =============================================================
                stage('Source') {
                    parallel {
                        stage('DSO-02 gitleaks') {
                            steps { container('gitleaks') { dsoSecrets() } }
                        }
                        stage('DSO-03 Semgrep') {
                            steps { container('semgrep') { script { dsoScan.sast() } } }
                        }
                        stage('DSO-04 Trivy fs') {
                            steps { container('trivy') { script { dsoScan.sca(env.APP_DIR) } } }
                        }
                        stage('DSO-05 Checkov') {
                            steps { container('checkov') { script { dsoScan.iac() } } }
                        }
                    }
                    post {
                        always {
                            // JENKINS-ONLY: no built-in findings view. Warnings NG
                            // renders every SARIF file as one "Security findings"
                            // report with trends across builds.
                            recordIssues(enabledForFailure: true,
                                         tools: [sarif(pattern: 'reports/*.sarif', id: 'security', name: 'Security findings')])
                        }
                    }
                }

                // =============================================================
                //  STAGE 3 - TEST (DSO-06)
                // =============================================================
                stage('Test') {
                    steps {
                        container('maven') {
                            sh 'mvn -B -f "$APP_DIR/pom.xml" verify'
                        }
                    }
                    post {
                        always { junit testResults: 'app-classic/target/surefire-reports/TEST-*.xml', allowEmptyResults: false }
                    }
                }

                // =============================================================
                //  STAGE 4 - PACKAGE (DSO-07..10): main branch only
                // =============================================================
                stage('Package') {
                    when { branch 'main' }
                    steps {
                        container('cloud') { dsoRegistryLogin(env.AWS_ROLE, env.AWS_REGION, env.IMAGE.tokenize('/')[0]) }
                        container('buildkit') {
                            // DSO-07 rootless BuildKit; the metadata file holds the pushed digest.
                            sh '''
                                buildctl-daemonless.sh build --frontend dockerfile.v0 \
                                  --local context="$APP_DIR" --local dockerfile="$APP_DIR" \
                                  --output type=image,name="$IMAGE:$BUILD_NUMBER",push=true \
                                  --metadata-file metadata.json
                            '''
                        }
                        script {
                            def digest = readJSON(file: 'metadata.json')['containerimage.digest']
                            env.IMAGE_REF = "${env.IMAGE}@${digest}"
                            // Everything from here on uses IMAGE_REF, never a tag.
                        }
                        container('trivy') { script { dsoScan.image(env.IMAGE_REF) } }   // DSO-08, DSO-09
                        container('cosign') {
                            // DSO-10 JENKINS-ONLY: KMS key, not keyless (see dsoSign.groovy).
                            dsoCloud('aws', [roleArn: env.AWS_ROLE]) {
                                script { dsoSign.sign(env.IMAGE_REF, env.SIGN_KEY, [cyclonedx: 'sbom.cdx.json']) }
                            }
                        }
                        // JENKINS-ONLY: fingerprints record exactly which build
                        // produced this SBOM; any later job that uses it is linked.
                        archiveArtifacts artifacts: 'sbom.cdx.json', fingerprint: true
                        writeFile file: 'image-ref.txt', text: env.IMAGE_REF
                        stash name: 'release', includes: 'image-ref.txt'
                    }
                }
            }
        }

        // =====================================================================
        //  STAGE 5 - RELEASE GATE (DSO-12). No agent: waiting costs nothing.
        //  JENKINS-ONLY: the approval is pipeline code. What stops a developer
        //  from approving their own change is folder-level RBAC: only the
        //  release-approvers group has the permission to submit this input.
        // =====================================================================
        stage('Release gate') {
            when { branch 'main' }
            options { timeout(time: 4, unit: 'HOURS') }      // unanswered = aborted
            input {
                message 'Deploy the signed image to production?'
                ok 'Deploy'
                submitter 'release-approvers'
            }
            steps {
                milestone(ordinal: 10, label: 'approved')     // older builds cannot pass this point later
            }
        }

        // =====================================================================
        //  STAGES 5-6 - VERIFY + DEPLOY (DSO-11, DSO-13)
        // =====================================================================
        stage('Deploy') {
            when { branch 'main' }
            agent {
                kubernetes {
                    yamlFile 'jenkins/pod-templates/devsecops.yaml'
                }
            }
            options {
                lock(resource: 'production')                  // one deployment at a time
                timeout(time: 30, unit: 'MINUTES')
            }
            environment { DOCKER_CONFIG = "${env.WORKSPACE}/.docker" }
            steps {
                unstash 'release'
                script { env.IMAGE_REF = readFile('image-ref.txt').trim() }
                container('cloud') { dsoRegistryLogin(env.AWS_ROLE, env.AWS_REGION, env.IMAGE.tokenize('/')[0]) }
                container('cosign') {
                    dsoCloud('aws', [roleArn: env.AWS_ROLE]) {
                        // DSO-11: refuse anything not signed by our KMS key.
                        script { dsoSign.verify(env.IMAGE_REF, env.SIGN_KEY, ['cyclonedx']) }
                    }
                }
                container('cloud') {
                    // DSO-13: the same deploy script as GitHub, GitLab and Azure DevOps.
                    // The Jenkins OIDC token for this cloud is handed over as a file.
                    script {
                        def creds = [file(credentialsId: "oidc-${env.CLOUD}", variable: 'OIDC_TOKEN_FILE')]
                        if (env.CLOUD == 'oci') {
                            creds << string(credentialsId: 'oci-exchange-client-secret', variable: 'OCI_EXCHANGE_CLIENT_SECRET')
                        }
                        withCredentials(creds) {
                            sh './scripts/deploy.sh "$CLOUD" "$IMAGE_REF"'
                        }
                    }
                }
            }
        }

        // =====================================================================
        //  STAGE 7 - VERIFY: DAST against staging (DSO-14)
        // =====================================================================
        stage('DAST') {
            when { branch 'main' }
            agent {
                kubernetes {
                    yamlFile 'jenkins/pod-templates/devsecops.yaml'
                }
            }
            steps {
                container('zap') {
                    sh 'mkdir -p zap && zap-baseline.py -t "$STAGING_URL" -r zap/zap-report.html -J zap/zap-report.json'
                }
            }
            post {
                always { archiveArtifacts artifacts: 'zap/**', allowEmptyArchive: true }
            }
        }
    }
}

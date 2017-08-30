import org.centos.pipeline.PipelineUtils

def pipelineUtils = new PipelineUtils()

properties(
        [
                buildDiscarder(logRotator(artifactDaysToKeepStr: '30', artifactNumToKeepStr: '', daysToKeepStr: '90', numToKeepStr: '')),
                disableConcurrentBuilds(),
                parameters(
                        [
                                string(description: 'CI Message that triggered the pipeline', name: 'CI_MESSAGE'),
                                string(defaultValue: 'f26', description: 'Fedora target branch', name: 'TARGET_BRANCH'),
                                string(defaultValue: 'http://artifacts.ci.centos.org/artifacts/fedora-atomic', description: 'URL for rsync content', name: 'HTTP_BASE'),
                                string(defaultValue: 'fedora-atomic', description: 'RSync User', name: 'RSYNC_USER'),
                                string(defaultValue: 'artifacts.ci.centos.org', description: 'RSync Server', name: 'RSYNC_SERVER'),
                                string(defaultValue: 'fedora-atomic', description: 'RSync Dir', name: 'RSYNC_DIR'),
                                string(defaultValue: 'ci-pipeline', description: 'Main project repo', name: 'PROJECT_REPO'),
                                string(defaultValue: 'org.centos.stage', description: 'Main topic to publish on', name: 'MAIN_TOPIC'),
                                string(defaultValue: 'fedora-fedmsg', description: 'Main provider to send messages on', name: 'MSG_PROVIDER'),
                                string(defaultValue: 'bpeck/jenkins-continuous-infra.apps.ci.centos.org@FEDORAPROJECT.ORG', description: 'Principal for authenticating with fedora build system', name: 'FEDORA_PRINCIPAL'),
                                booleanParam(defaultValue: false, description: 'Force generation of the image', name: 'GENERATE_IMAGE'),
                        ]
                ),
        ]
)

podTemplate(name: 'fedora-atomic-inline', label: 'fedora-atomic-inline', cloud: 'openshift', serviceAccount: 'jenkins',
        idleMinutes: 1,  namespace: 'continuous-infra',
        containers: [
                // This adds the custom slave container to the pod. Must be first with name 'jnlp'
                containerTemplate(name: 'jnlp',
                        image: '172.30.254.79:5000/continuous-infra/jenkins-continuous-infra-slave',
                        ttyEnabled: false,
                        args: '${computer.jnlpmac} ${computer.name}',
                        command: '',
                        workingDir: '/tmp'),
        ])

node('fedora-atomic-inline') {
    ansiColor('xterm') {
        timestamps {
            def currentStage = ""
            try {
                deleteDir()

                // Set our default env variables
                pipelineUtils.setDefaultEnvVars()

                // Parse the CI_MESSAGE and inject it as env vars
                pipelineUtils.injectFedmsgVars()

                // Set our current stage value
                currentStage = "ci-pipeline-rpmbuild"
                stage(currentStage) {

                    // SCM
                    dir('ci-pipeline') {
                        git 'https://github.com/CentOS-PaaS-SIG/ci-pipeline'
                    }
                    dir('cciskel') {
                        git 'https://github.com/cgwalters/centos-ci-skeleton'
                    }
                    dir('sig-atomic-buildscripts') {
                        git 'https://github.com/CentOS/sig-atomic-buildscripts'
                    }

                    // Set stage specific vars
                    pipelineUtils.setStageEnvVars(currentStage)

                    //Set our message topic, properties, and content
                    (topic, messageProperties, messageContent) = pipelineUtils.setMessageFields("package.running")

                    // Send message org.centos.prod.ci.pipeline.package.running on fedmsg
                    sendMessage(messageProperties, messageContent)

                    // Provision of resources
                    pipelineUtils.provisionResources(currentStage)

                    // Stage resources - RPM build system
                    pipelineUtils.setupStage(current_stage, 'fedora-atomic-key')

                    // Rsync Data
                    pipelineUtils.rsyncData(currentStage)

                    def package_props = "${ORIGIN_WORKSPACE}/logs/package_props.txt"
                    def package_props_groovy = "${ORIGIN_WORKSPACE}/package_props.groovy"
                    pipelineUtils.convertProps(package_props, package_props_groovy)
                    load(package_props_groovy)

                    // Teardown resources
                    pipelineUtils.teardownResources(currentStage)

                    // Set our message topic, properties, and content
                    (topic, messageProperties, messageContent) = pipelineUtils.setMessageFields("package.complete")

                    // Send message org.centos.prod.ci.pipeline.package.complete on fedmsg
                    sendMessage(messageProperties, messageContent)

                    pipelineUtils.checkLastImage(currentStage, checkRsyncDataDir=false)

                }

                currentStage = "ci-pipeline-ostree-compose"
                stage(currentStage) {
                    // Set stage specific vars
                    pipelineUtils.setStageEnvVars(currentStage)

                    //Set our message topic, properties, and content
                    (topic, messageProperties, messageContent) = pipelineUtils.setMessageFields("compose.running")

                    // Send message org.centos.prod.ci.pipeline.compose.running on fedmsg
                    sendMessage(messageProperties, messageContent)

                    // Provision resources
                    pipelineUtils.provisionResources(currentStage)

                    // Stage resources - ostree compose
                    pipelineUtils.setupStage(current_stage, 'fedora-atomic-key')

                    // Rsync Data
                    pipelineUtils.rsyncData(currentStage)

                    def ostree_props = "${env.ORIGIN_WORKSPACE}/logs/ostree.props"
                    def ostree_props_groovy = "${env.ORIGIN_WORKSPACE}/ostree.props.groovy"
                    pipelineUtils.convertProps(ostree_props, ostree_props_groovy)
                    load(ostree_props_groovy)

                    // Teardown resource
                    pipelineUtils.teardownResources(currentStage)

                    // Set our message topic, properties, and content
                    (topic, messageProperties, messageContent) = pipelineUtils.setMessageFields("package.complete")

                    // Send message org.centos.prod.ci.pipeline.package.complete on fedmsg
                    sendMessage(messageProperties, messageContent)

                    checkLastImage(currentStage)
                }

                currentStage = "ci-pipeline-ostree-image-compose"
                stage(currentStage) {
                    // Check if a new ostree image compose is needed
                    if (fileExists("${env.WORKSPACE}/NeedNewImage.txt") || ("${env.GENERATE_IMAGE}" == "true")) {
                        // Set stage specific vars
                        pipelineUtils.setStageEnvVars(currentStage)

                        // Set our message topic, properties, and content
                        (topic, messageProperties, messageContent) = pipelineUtils.setMessageFields("image.running")

                        // Send message org.centos.prod.ci.pipeline.image.running on fedmsg
                        sendMessage(messageProperties, messageContent)

                        // Provision resources
                        pipelineUtils.provisionResources(currentStage)

                        // Stage resources - ostree image compose
                        pipelineUtils.setupStage(current_stage, 'fedora-atomic-key')

                        // Rsync Data
                        pipelineUtils.rsyncData(currentStage)

                        ostree_props = "${env.ORIGIN_WORKSPACE}/logs/ostree.props"
                        ostree_props_groovy = "${env.ORIGIN_WORKSPACE}/ostree.props.groovy"
                        pipelineUtils.convertProps(ostree_props, ostree_props_groovy)
                        load(ostree_props_groovy)

                        // Teardown resources
                        pipelineUtils.teardownResources(currentStage)

                        // Set our message topic, properties, and content
                        (topic, messageProperties, messageContent) = pipelineUtils.setMessageFields("image.complete")

                        // Send message org.centos.prod.ci.pipeline.image.complete on fedmsg
                        sendMessage(messageProperties, messageContent)

                    } else {
                        echo "Not Generating a New Image"
                    }
                }

                currentStage = "ci-pipeline-ostree-image-boot-sanity"
                stage(currentStage) {
                    if (fileExists("${env.WORKSPACE}/NeedNewImage.txt") || ("${env.GENERATE_IMAGE}" == "true")) {
                        pipelineUtils.setStageEnvVars(currentStage)

                        // Set our message topic, properties, and content
                        (topic, messageProperties, messageContent) = pipelineUtils.setMessageFields("smoke.running")

                        // Send message org.centos.prod.ci.pipeline.smoke.running on fedmsg
                        sendMessage(messageProperties, messageContent)

                        // Provision resources
                        pipelineUtils.provisionResources(currentStage)

                        // Stage resources - ostree image boot sanity
                        pipelineUtils.setupStage(current_stage, 'fedora-atomic-key')

                        // Rsync Data
                        pipelineUtils.rsyncData(currentStage)

                        // Teardown resources
                        pipelineUtils.teardownResources(currentStage)

                        // Set our message topic, properties, and content
                        (topic, messageProperties, messageContent) = pipelineUtils.setMessageFields("smoke.complete")

                        // Send message org.centos.prod.ci.pipeline.smoke.complete on fedmsg
                        sendMessage(messageProperties, messageContent)

                    } else {
                        echo "Not Running Image Boot Sanity on Image"
                    }
                }

                currentStage = "ci-pipeline-ostree-boot-sanity"
                stage(currentStage) {
                    pipelineUtils.setStageEnvVars(currentStage)

                    // Provision resources
                    pipelineUtils.provisionResources(currentStage)

                    // Stage resources - ostree boot sanity
                    pipelineUtils.setupStage(current_stage, 'fedora-atomic-key')

                    // Rsync Data
                    pipelineUtils.rsyncData(currentStage)


                    // Teardown resources
                    pipelineUtils.teardownResources(currentStage)

//                    step([$class: 'XUnitBuilder',
//                          thresholds: [[$class: 'FailedThreshold', unstableThreshold: '1']],
//                          tools: [[$class: 'JUnitType', pattern: "${env.ORIGIN_WORKSPACE}/logs/*.xml"]]]
//                    )

                    // Set our message topic, properties, and content
                    (topic, messageProperties, messageContent) = pipelineUtils.setMessageFields("integration.queued")

                    // Send message org.centos.prod.ci.pipeline.integration.queued on fedmsg
                    sendMessage(messageProperties, messageContent)
                }

                currentStage="ci-pipeline-atomic-host-tests"
                stage(currentStage) {
                    pipelineUtils.setStageEnvVars(currentStage)

                    // Set our message topic, properties, and content
                    (topic, messageProperties, messageContent) = pipelineUtils.setMessageFields("integration.running")

                    // Send message org.centos.prod.ci.pipeline.integration.running on fedmsg
                    sendMessage(messageProperties, messageContent)

                    // Provision resources
                    pipelineUtils.provisionResources(currentStage)

                    // Stage resources - atomic host tests
                    pipelineUtils.setupStage(current_stage, 'fedora-atomic-key')

                    // Teardown resources
                    pipelineUtils.teardownResources(currentStage)

//                     step([$class: 'XUnitBuilder',
//                          thresholds: [[$class: 'FailedThreshold', unstableThreshold: '1']],
//                          tools: [[$class: 'JUnitType', pattern: "${env.ORIGIN_WORKSPACE}/logs/ansible_xunit.xml"]]]
//                    )

                    // Set our message topic, properties, and content
                    (topic, messageProperties, messageContent) = pipelineUtils.setMessageFields("integration.complete")

                    // Send message org.centos.prod.ci.pipeline.integration.complete on fedmsg
                    sendMessage(messageProperties, messageContent)
                }

            } catch (e) {
                // Set build result
                currentBuild.result = 'FAILURE'

                // Report the exception
                echo "Error: Exception from " + currentStage + ":"
                echo e.getMessage()

                // Teardown resources
                pipelineUtils.teardownResources(currentStage)

                // Throw the error
                throw e

            } finally {
                // Set the build display name and description
                currentBuild.displayName = "Build#: ${env.BUILD_NUMBER} - Branch: ${env.branch} - Package: ${env.fed_repo}"
                currentBuild.description = "${currentBuild.currentResult}"

                //emailext subject: "${env.JOB_NAME} - Build # ${env.BUILD_NUMBER} - STATUS = ${currentBuild.currentResult}", to: "ari@redhat.com", body: "This pipeline was a ${currentBuild.currentResult}"

                // Archive our artifacts
                step([$class: 'ArtifactArchiver', allowEmptyArchive: true, artifacts: '**/logs/**,*.txt,*.groovy,**/job.*,**/*.groovy,**/inventory.*', excludes: '**/job.props,**/job.props.groovy,**/*.example', fingerprint: true])

                // Set our message topic, properties, and content
                (topic, messageProperties, messageContent) = pipelineUtils.setMessageFields("complete")

                // Send message org.centos.prod.ci.pipeline.complete on fedmsg
                sendMessage(messageProperties, messageContent)

            }
        }
    }
}
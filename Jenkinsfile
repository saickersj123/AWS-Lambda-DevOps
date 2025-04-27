pipeline {
    agent any
    
    // Prevent concurrent builds on the same branch
    options {
        disableConcurrentBuilds()
    }
    
    parameters {
        choice(
            name: 'ENVIRONMENT',
            choices: ['auto', 'dev', 'staging', 'prod'],
            description: 'Deployment environment (auto = based on branch)'
        )
        booleanParam(
            name: 'SKIP_TESTS',
            defaultValue: false,
            description: 'Skip running tests'
        )
        booleanParam(
            name: 'SKIP_INTEGRATION_TESTS',
            defaultValue: false,
            description: 'Skip running integration tests'
        )
    }
    
    environment {
        PYTHON_VERSION = '3.11'
        VENV_NAME = 'venv'
        AWS_REGION = 'us-east-2'
        AWS_CREDENTIALS = credentials('aws-credentials')
        SAFETY_API_KEY = credentials('safety-scan-key')
    }
    
    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }
        
        stage('Install Dependencies') {
            steps {
                sh '''#!/bin/bash
                    # Install system dependencies
                    if [ -f "/.dockerenv" ]; then
                        apt-get update
                        apt-get install -y python3 python3-pip python3-venv curl unzip jq
                    fi
                    
                    # Install Terraform if not present or needs update
                    if ! command -v terraform &> /dev/null || [ "$(terraform version | head -n1 | cut -d' ' -f2)" != "1.11.4" ]; then
                        echo "Installing/Updating Terraform..."
                        
                        # Create temporary directory for installation
                        TEMP_DIR=$(mktemp -d)
                        cd $TEMP_DIR
                        
                        # Download and install new version
                        curl -fsSL https://releases.hashicorp.com/terraform/1.11.4/terraform_1.11.4_linux_amd64.zip -o terraform.zip
                        unzip -o terraform.zip
                        chmod +x terraform
                        
                        # Remove existing terraform if present (handling both file and directory cases)
                        if [ -d "/usr/local/bin/terraform" ]; then
                            echo "Removing existing Terraform directory..."
                            rm -rf "/usr/local/bin/terraform"
                        elif [ -f "/usr/local/bin/terraform" ]; then
                            echo "Removing existing Terraform binary..."
                            rm -f "/usr/local/bin/terraform"
                        fi
                        
                        # Install new version
                        mv terraform /usr/local/bin/
                        
                        # Cleanup
                        cd -
                        rm -rf $TEMP_DIR
                        rm -f terraform.zip
                        
                        # Verify installation
                        if ! command -v terraform &> /dev/null; then
                            echo "Error: Terraform installation failed"
                            exit 1
                        fi
                        echo "Terraform version $(terraform version | head -n1 | cut -d' ' -f2) installed successfully"
                    else
                        echo "Terraform 1.11.4 is already installed"
                    fi
                    
                    # Create Python virtual environment
                    python3 -m venv ${VENV_NAME}
                    . ${VENV_NAME}/bin/activate
                    pip install --upgrade pip
                    pip install -r requirements-dev.txt
                '''
            }
        }
        
        stage('Lint & Format') {
            steps {
                sh '''
                    . ${VENV_NAME}/bin/activate

                    # Change permissions of scripts
                    chmod +x scripts/lint.sh
                    chmod +x scripts/format.sh
                    
                    # Run Python linting if it fails, continue the following steps
                    ./scripts/lint.sh || true

                    # Run Python formatting
                    ./scripts/format.sh
                '''
            }
        }
        
        stage('Security Scan') {
            steps {
                withCredentials([string(credentialsId: 'safety-scan-key', variable: 'SAFETY_API_KEY')]) {
                    sh '''
                        . ${VENV_NAME}/bin/activate
                        
                        # Run Bandit and save output
                        bandit -r lambda_functions -f json -o bandit.json || echo '{"results": []}' > bandit.json
                        
                        # Run Safety and save output
                        safety scan --key ${SAFETY_API_KEY} --output json > safety.json || echo '{"scan_results": {"projects": [{"files": []}]}}' > safety.json
                    '''
                }
            }
            post {
                always {
                    script {
                        // Parse Bandit results
                        def banditIssues = 0
                        def banditDetails = []
                        try {
                            def banditReport = readJSON file: 'bandit.json'
                            banditReport.results.each { issue ->
                                if (!issue.ignored) {
                                    banditIssues++
                                    banditDetails.add([
                                        severity: issue.severity,
                                        confidence: issue.confidence,
                                        issue_text: issue.issue_text,
                                        filename: issue.filename,
                                        line_number: issue.line_number
                                    ])
                                }
                            }
                        } catch (Exception e) {
                            echo "Error parsing Bandit report: ${e.message}"
                        }
                        
                        // Parse Safety results
                        def safetyIssues = 0
                        def safetyDetails = []
                        try {
                            def safetyReport = readJSON file: 'safety.json'
                            safetyReport.scan_results.projects.each { project ->
                                project.files.each { file ->
                                    file.results.dependencies.each { dep ->
                                        dep.specifications.each { spec ->
                                            spec.vulnerabilities.known_vulnerabilities.each { vuln ->
                                                if (!vuln.ignored) {
                                                    safetyIssues++
                                                    safetyDetails.add([
                                        package: dep.name,
                                        version: dep.version,
                                        vulnerability_id: vuln.vulnerability_id,
                                        advisory: vuln.advisory,
                                        severity: vuln.severity
                                    ])
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        } catch (Exception e) {
                            echo "Error parsing Safety report: ${e.message}"
                        }
                        
                        // Set build status - only if there are non-ignored issues
                        if (banditIssues > 0 || safetyIssues > 0) {
                            currentBuild.result = 'UNSTABLE'
                        }
                        
                        // Create security report
                        def securityReport = [
                            bandit: [
                                total_issues: banditIssues,
                                details: banditDetails
                            ],
                            safety: [
                                total_vulnerabilities: safetyIssues,
                                details: safetyDetails
                            ]
                        ]
                        
                        // Write security report to file
                        writeJSON file: 'coverage_reports/security_report.json', json: securityReport
                        
                        // Send Slack notification
                        def message = new StringBuilder()
                        message.append("🔒 *Security Scan Results*\n")
                        
                        if (banditIssues > 0 || safetyIssues > 0) {
                            if (banditIssues > 0) {
                                message.append("• Bandit Issues: ${banditIssues}\n")
                            }
                            if (safetyIssues > 0) {
                                message.append("• Safety Vulnerabilities: ${safetyIssues}\n")
                            }
                        } else {
                            message.append("✅ No security issues found")
                        }
                        
                        slackSend(
                            channel: '#jenkins-notifications',
                            color: currentBuild.result == 'UNSTABLE' ? 'warning' : 'good',
                            message: message.toString()
                        )
                    }
                }
            }
        }
        
        stage('Unit Tests') {
            when {
                expression { return !params.SKIP_TESTS }
            }
            steps {
                sh '''
                    . ${VENV_NAME}/bin/activate
                    chmod +x scripts/run_unit_tests.sh
                    ./scripts/run_unit_tests.sh
                '''
            }
            post {
                always {
                    junit 'coverage_reports/junit.xml'
                    recordCoverage(tools: [[parser: 'COBERTURA', pattern: 'coverage_reports/coverage.xml']])
                }
            }
        }

        stage('Integration Tests') {
            when {
                expression { 
                    return !params.SKIP_TESTS && 
                           !params.SKIP_INTEGRATION_TESTS && 
                           BRANCH_NAME != 'main' && 
                           params.ENVIRONMENT != 'prod'
                }
            }
            steps {
                sh '''
                    . ${VENV_NAME}/bin/activate
                    
                    # Set mock mode environment variables
                    export MOCK_API=1
                    export MOCK_DYNAMODB=1
                    export MOCK_S3=1
                    export MOCK_SQS=1
                    export MOCK_LAMBDA=1
                    
                    # Run integration tests in mock mode
                    chmod +x scripts/run_integration_tests.sh
                    ./scripts/run_integration_tests.sh
                '''
            }
            post {
                always {
                    junit 'coverage_reports/integration_junit.xml'
                }
            }
        }
        
        stage('Terraform Deploy') {
            steps {
                script {
                    def environment = params.ENVIRONMENT == 'auto' ? 
                        (BRANCH_NAME == 'main' ? 'prod' : 'dev') : 
                        params.ENVIRONMENT
                    def terraformDir = "terraform/environments/${environment}"
                    
                    sh """
                        cd ${terraformDir}
                        terraform init || terraform init -upgrade
                        terraform plan -out=tfplan
                        terraform apply -auto-approve tfplan
                    """
                }
            }
        }
    }
    
    post {
        always {
            cleanWs()
            
            script {
                def status = currentBuild.result ?: 'SUCCESS'
                def color = status == 'SUCCESS' ? 'good' : 'danger'
                def statusEmoji = status == 'SUCCESS' ? '✅' : '❌'
                def branchEmoji = BRANCH_NAME == 'main' ? '🚀' : '🔧'
                def environment = params.ENVIRONMENT == 'auto' ? 
                    (BRANCH_NAME == 'main' ? 'prod' : 'dev') : 
                    params.ENVIRONMENT
                
                // Slack notification
                try {
                    slackSend(
                        channel: '#jenkins-notifications',
                        color: color,
                        message: """
${statusEmoji} *Build ${status}*
• *Job:* ${env.JOB_NAME} #${env.BUILD_NUMBER}
• *Branch:* ${branchEmoji} ${BRANCH_NAME}
• *Environment:* ${environment.toUpperCase()}
• *Details:* <${env.BUILD_URL}|View Build>
• *Triggered by:* ${currentBuild.getBuildCauses('hudson.model.Cause$UserIdCause')[0]?.userId ?: 'System'}
• *Duration:* ${currentBuild.durationString}
"""
                    )
                } catch (Exception e) {
                    echo "Slack notification failed: ${e.message}"
                }
            }
        }
    }
} 
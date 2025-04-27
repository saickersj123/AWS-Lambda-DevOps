#!/bin/bash -e
# Create debug log
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "Starting Jenkins installation with Docker..."

# Update system packages
yum update -y

# Install required system packages - keep Python3 but don't make it default
yum install -y \
  git zip unzip jq \
  python3 python3-pip python3-devel python3-venv \
  gcc g++ make \
  openssl-devel bzip2-devel libffi-devel zlib-devel \
  wget

# Install Docker using amazon-linux-extras to avoid dependency issues
amazon-linux-extras install -y docker
systemctl enable docker
systemctl start docker || { echo "Failed to start Docker service"; exit 1; }
usermod -a -G docker ec2-user

# Verify Docker is running
docker info || { echo "Docker is not running properly"; systemctl restart docker; sleep 5; }

# Install Docker Compose with proper error handling
echo "Installing Docker Compose..."
mkdir -p /usr/local/bin
curl -L https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
/usr/local/bin/docker-compose --version || { echo "Docker Compose installation failed"; exit 1; }

# Install ECR credential helper for Docker after Docker is installed
yum install -y amazon-ecr-credential-helper

# IMPORTANT: DO NOT create a symlink from python3 to python as this breaks yum
# Use python3 explicitly in scripts instead

# Upgrade pip and install Python packages without affecting system Python
python3 -m pip install --upgrade pip
python3 -m pip install awscli boto3 flake8 black pytest pytest-cov coverage

# Install Terraform using Amazon Linux repo
yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
yum -y install terraform

# Create Jenkins home directory with proper permissions
mkdir -p /var/jenkins_home
chmod 777 /var/jenkins_home

# Configure AWS credentials on the host EC2
mkdir -p /root/.aws
chmod 700 /root/.aws

cat > /root/.aws/credentials << 'EOT'
[default]
aws_access_key_id=${aws_access_key_id}
aws_secret_access_key=${aws_secret_access_key}
EOT

cat > /root/.aws/config << 'EOT'
[default]
region=${region}
output=json
EOT

chmod 600 /root/.aws/credentials
chmod 600 /root/.aws/config

# Create Docker Compose file with explicit path
cat > /var/jenkins_home/docker-compose.yml << 'EOT'
services:
  jenkins:
    image: jenkins/jenkins:lts-jdk21
    container_name: jenkins
    user: root
    ports:
      - "8080:8080"
      - "50000:50000"
    volumes:
      - /var/jenkins_home:/var/jenkins_home
      - /var/run/docker.sock:/var/run/docker.sock
      - /root/.aws:/root/.aws:ro
    environment:
      - JENKINS_ADMIN_ID=${jenkins_admin_username}
      - JENKINS_ADMIN_PASSWORD=${jenkins_admin_password}
      - JAVA_OPTS=-Djenkins.install.runSetupWizard=false
      - JENKINS_OPTS=--argumentsRealm.roles.user=admin --argumentsRealm.roles.admin=admin
      - AWS_REGION=${region}
      - AWS_ACCESS_KEY_ID=${aws_access_key_id}
      - AWS_SECRET_ACCESS_KEY=${aws_secret_access_key}
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/login"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
    restart: always
EOT

# Create AWS credentials configuration script
cat > /var/jenkins_home/setup-aws.sh << 'EOT'
#!/bin/bash
set -e

echo "Setting up AWS CLI in Jenkins container..."

# Wait for Jenkins container to be available
until docker ps | grep -q jenkins; do
  echo "Waiting for Jenkins container to start..."
  sleep 5
done

# Install AWS CLI in Jenkins container using the official installer (instead of pip)
echo "Installing AWS CLI in Jenkins container..."
docker exec jenkins apt-get update
docker exec jenkins apt-get install -y curl unzip

# Download and install AWS CLI v2 inside the container
docker exec jenkins curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
docker exec jenkins unzip -q awscliv2.zip
docker exec jenkins ./aws/install
docker exec jenkins rm -rf aws awscliv2.zip

# Verify AWS CLI installation
echo "Verifying AWS CLI installation..."
docker exec jenkins aws --version

# Create .aws directory if it doesn't exist in the container
docker exec jenkins mkdir -p /root/.aws

# Create credentials file from environment variables if not mounted
if [ ! -f /root/.aws/credentials ]; then
  echo "Creating AWS credentials file in container..."
  docker exec jenkins bash -c 'cat > /root/.aws/credentials << EOT
[default]
aws_access_key_id=$AWS_ACCESS_KEY_ID
aws_secret_access_key=$AWS_SECRET_ACCESS_KEY
EOT'
  docker exec jenkins chmod 600 /root/.aws/credentials
fi

# Create config file if not mounted
if [ ! -f /root/.aws/config ]; then
  echo "Creating AWS config file in container..."
  docker exec jenkins bash -c 'cat > /root/.aws/config << EOT
[default]
region=$AWS_REGION
output=json
EOT'
  docker exec jenkins chmod 600 /root/.aws/config
fi

# Test AWS CLI configuration
echo "Testing AWS CLI configuration..."
docker exec jenkins aws sts get-caller-identity || echo "AWS CLI configuration failed"

echo "AWS CLI setup complete in Jenkins container"
EOT

chmod +x /var/jenkins_home/setup-aws.sh

# Create a script for automated plugin installation
cat > /var/jenkins_home/install-plugins.sh << 'EOT'
#!/bin/bash
set -e

JENKINS_URL="http://localhost:8080"
JENKINS_USER="${jenkins_admin_username}"
JENKINS_PASSWORD="${jenkins_admin_password}"

echo "Waiting for Jenkins to be available..."
MAX_WAIT=300  # 5 minutes
WAIT_INTERVAL=10
for ((i=0; i<MAX_WAIT; i+=WAIT_INTERVAL)); do
    if curl -s -f $JENKINS_URL/login > /dev/null; then
        echo "Jenkins is available!"
        break
    fi
    
    if [ $i -ge $MAX_WAIT ]; then
        echo "Timeout waiting for Jenkins to be available"
        exit 1
    fi
    
    echo "Still waiting for Jenkins to be available... ($i seconds)"
    sleep $WAIT_INTERVAL
done

# Download Jenkins CLI
echo "Downloading Jenkins CLI..."
curl -s -o /var/jenkins_home/jenkins-cli.jar $JENKINS_URL/jnlpJars/jenkins-cli.jar

# Verify Jenkins CLI download
if [ ! -f "/var/jenkins_home/jenkins-cli.jar" ]; then
    echo "ERROR: Failed to download Jenkins CLI"
    exit 1
fi

# Copy the plugin list to the container
docker cp /var/jenkins_home/reference/recommended-plugins.txt jenkins:/var/jenkins_home/reference/

# Collect all plugins to install
echo "Collecting plugins to install..."
PLUGINS_TO_INSTALL=""
while read -r plugin; do
    # Skip comments and empty lines
    [[ $plugin =~ ^#.*$ ]] && continue
    [[ -z $plugin ]] && continue
    
    echo "Adding plugin: $plugin"
    PLUGINS_TO_INSTALL="$PLUGINS_TO_INSTALL $plugin"
done < /var/jenkins_home/reference/recommended-plugins.txt

# Install all plugins at once
echo "Installing all plugins..."
if ! docker exec jenkins java -jar /var/jenkins_home/jenkins-cli.jar -s $JENKINS_URL -auth $JENKINS_USER:$JENKINS_PASSWORD install-plugin $PLUGINS_TO_INSTALL -restart; then
    echo "ERROR: Failed to install plugins"
    exit 1
fi

# Wait for Jenkins to restart
echo "Waiting for Jenkins to restart after installing all plugins..."
sleep 30
for ((i=0; i<MAX_WAIT; i+=WAIT_INTERVAL)); do
    if curl -s -f $JENKINS_URL/login > /dev/null; then
        echo "Jenkins is back online after installing all plugins"
        break
    fi
    
    if [ $i -ge $MAX_WAIT ]; then
        echo "Timeout waiting for Jenkins to restart"
        exit 1
    fi
    
    echo "Still waiting for Jenkins to restart... ($i seconds)"
    sleep $WAIT_INTERVAL
done

echo "All plugins installed successfully!"
EOT

chmod +x /var/jenkins_home/install-plugins.sh

# Create a file with the list of recommended plugins
mkdir -p /var/jenkins_home/reference
cat > /var/jenkins_home/reference/recommended-plugins.txt << 'EOT'
# Core pipeline plugins
workflow-aggregator
pipeline-stage-view
git

# Docker integration
docker-workflow
docker-plugin

# AWS integration
aws-credentials
pipeline-aws
aws-global-configuration

# Utility plugins
credentials
credentials-binding
timestamper

# UI plugins
blueocean

# Testing and reporting
junit
warnings-ng
coverage

# Notification
email-ext
slack

# Utilities
pipeline-utility-steps
configuration-as-code
ws-cleanup
EOT

# Create a diagnostic script
cat > /var/jenkins_home/troubleshoot.sh << 'EOT'
#!/bin/bash

echo "=== System Info ==="
date
uname -a

echo "=== Docker Status ==="
systemctl status docker

echo "=== Docker Version ==="
docker --version
docker-compose --version

echo "=== Docker Compose Files ==="
ls -la /var/jenkins_home/
cat /var/jenkins_home/docker-compose.yml

echo "=== Docker Containers ==="
docker ps
docker ps -a

echo "=== Starting Docker Compose ==="
cd /var/jenkins_home
docker-compose up -d

echo "=== Docker Logs ==="
docker logs jenkins || echo "No jenkins container found"

echo "=== Network Check ==="
netstat -tulpn | grep 8080

echo "=== Disk Space ==="
df -h

echo "=== Jenkins Home Directory ==="
ls -la /var/jenkins_home/

echo "=== End of Diagnostics ==="
EOT

chmod +x /var/jenkins_home/troubleshoot.sh

# Get public IP for reference
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4)

# Run diagnostic script to capture initial state before starting Jenkins
/var/jenkins_home/troubleshoot.sh > /tmp/initial_diagnostics.log 2>&1

# Create init groovy script for security setup
mkdir -p /var/jenkins_home/init.groovy.d

# Create security initialization script
cat > /var/jenkins_home/init.groovy.d/security.groovy << 'EOT'
import jenkins.model.*
import hudson.security.*
import jenkins.install.InstallState

def instance = Jenkins.getInstance()

println "--> Securing Jenkins"

// Create the security realm
def realm = new HudsonPrivateSecurityRealm(false)
realm.createAccount("${jenkins_admin_username}", "${jenkins_admin_password}")
instance.setSecurityRealm(realm)

// Create authorization strategy
def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
strategy.setAllowAnonymousRead(false)
instance.setAuthorizationStrategy(strategy)

// Mark Jenkins as having been set up
if(!instance.getSetupWizard().isComplete()) {
  instance.getSetupWizard().completeSetup()
}

// Check for Jenkins updates
println "--> Checking for Jenkins updates..."
try {
  def updateCenter = instance.getUpdateCenter()
  updateCenter.checkForUpdates()
  def coreUpdates = updateCenter.getCoreUpdates()
  if (coreUpdates.size() > 0) {
    println "--> Jenkins core updates available. Latest version: $${coreUpdates[0].version}"
    // Automatically update Jenkins core
    coreUpdates[0].deploy(true)
    println "--> Jenkins core update has been deployed and will take effect after restart"
  } else {
    println "--> Jenkins core is up to date"
  }
} catch (Exception e) {
  println "--> Error checking for updates: $${e.message}"
}

instance.setInstallState(InstallState.RUNNING)
instance.save()

println "--> Security setup complete"
EOT

# Create a script for periodic plugin updates
cat > /var/jenkins_home/update-plugins.sh << 'EOT'
#!/bin/bash

JENKINS_URL="http://localhost:8080"
JENKINS_USER="admin" 
JENKINS_PASSWORD="ADMIN_PASSWORD_PLACEHOLDER"

# Wait for Jenkins to be up
echo "Waiting for Jenkins to be available..."
while ! curl -s -f $JENKINS_URL > /dev/null; do
  sleep 10
done

# Download Jenkins CLI
curl -s -o /var/jenkins_home/jenkins-cli.jar $JENKINS_URL/jnlpJars/jenkins-cli.jar

# Check for plugin updates (if any plugins are already installed)
echo "Checking for plugin updates..."
java -jar /var/jenkins_home/jenkins-cli.jar -s $JENKINS_URL -auth $JENKINS_USER:$JENKINS_PASSWORD list-plugins | grep -e ')$' | awk '{ print $1 }' > /var/jenkins_home/plugins-to-update.txt

if [ -s /var/jenkins_home/plugins-to-update.txt ]; then
  echo "Found plugins to update: $(cat /var/jenkins_home/plugins-to-update.txt | tr '\n' ' ')"
  echo "Updating plugins..."
  java -jar /var/jenkins_home/jenkins-cli.jar -s $JENKINS_URL -auth $JENKINS_USER:$JENKINS_PASSWORD install-plugin $(cat /var/jenkins_home/plugins-to-update.txt | tr '\n' ' ') -restart
  echo "Plugins updated successfully. Jenkins restarted."
else
  echo "No plugins to update or no plugins installed"
fi

# Display recommended plugins
echo "Recommended plugins can be found in /var/jenkins_home/reference/recommended-plugins.txt"
echo "View these with: docker exec jenkins cat /var/jenkins_home/reference/recommended-plugins.txt"
EOT

# Replace placeholder password
sed -i "s/ADMIN_PASSWORD_PLACEHOLDER/${jenkins_admin_password}/g" /var/jenkins_home/update-plugins.sh

chmod +x /var/jenkins_home/update-plugins.sh

# Create setup script
cat > /var/jenkins_home/setup-jenkins.sh << 'EOT'
#!/bin/bash

# Function to check if Jenkins is ready
check_jenkins_ready() {
    # Check if the container is running
    if ! docker ps | grep -q jenkins; then
        return 1
    fi
    
    # Check if Jenkins is responding
    if curl -s -f http://localhost:8080/login > /dev/null; then
        return 0
    fi
    
    return 1
}

echo "Starting Jenkins setup..."

# Wait for Jenkins to be ready
echo "Waiting for Jenkins to start..."
MAX_WAIT=300  # 5 minutes
WAIT_INTERVAL=10
for ((i=0; i<MAX_WAIT; i+=WAIT_INTERVAL)); do
    if check_jenkins_ready; then
        echo "Jenkins is ready!"
        break
    fi
    
    if [ $i -ge $MAX_WAIT ]; then
        echo "Timeout waiting for Jenkins to start"
        exit 1
    fi
    
    echo "Still waiting for Jenkins... ($i seconds)"
    sleep $WAIT_INTERVAL
done

# Install plugins
echo "Installing plugins..."
/var/jenkins_home/install-plugins.sh

# Restart Jenkins to apply changes
echo "Restarting Jenkins..."
docker-compose -f /var/jenkins_home/docker-compose.yml restart jenkins

# Wait for Jenkins to be ready again
echo "Waiting for Jenkins to restart..."
for ((i=0; i<MAX_WAIT; i+=WAIT_INTERVAL)); do
    if check_jenkins_ready; then
        echo "Jenkins is ready after restart!"
        break
    fi
    
    if [ $i -ge $MAX_WAIT ]; then
        echo "Timeout waiting for Jenkins to restart"
        exit 1
    fi
    
    echo "Still waiting for Jenkins to restart... ($i seconds)"
    sleep $WAIT_INTERVAL
done

echo "Jenkins setup completed successfully!"
EOT

# Start Docker Compose with explicit path
echo "Starting Jenkins with Docker Compose..."
cd /var/jenkins_home
/usr/local/bin/docker-compose up -d

# Verify Jenkins container is running
if ! docker ps | grep -q jenkins; then
  echo "ERROR: Jenkins container failed to start!"
  docker ps -a
  docker logs jenkins || echo "No jenkins container found or cannot access logs"
  # Run troubleshooting again after failure
  /var/jenkins_home/troubleshoot.sh > /tmp/failed_startup_diagnostics.log 2>&1
else
  echo "Jenkins container started successfully"
  
  # Run AWS CLI setup
  /var/jenkins_home/setup-aws.sh > /tmp/aws_cli_setup.log 2>&1
fi

# Ensure Jenkins home directory exists and has correct permissions
if [ ! -d "/var/jenkins_home" ]; then
    echo "Creating Jenkins home directory..."
    mkdir -p /var/jenkins_home
fi

# Set correct permissions
chmod 777 /var/jenkins_home

# Run the Jenkins setup script in the background
echo "Setting up Jenkins..."
if [ ! -f "/var/jenkins_home/setup-jenkins.sh" ]; then
    echo "ERROR: setup-jenkins.sh not found!"
    exit 1
fi

# Ensure script is executable
chmod +x /var/jenkins_home/setup-jenkins.sh
if [ ! -x "/var/jenkins_home/setup-jenkins.sh" ]; then
    echo "ERROR: Failed to make setup-jenkins.sh executable!"
    exit 1
fi

# Run the setup script with error handling
if ! nohup /var/jenkins_home/setup-jenkins.sh > /tmp/jenkins_setup.log 2>&1 & then
    echo "ERROR: Failed to start setup-jenkins.sh!"
    cat /tmp/jenkins_setup.log
    exit 1
fi

echo "Jenkins installation initiated!"
echo "Admin username: ${jenkins_admin_username}"
echo "Admin password: ${jenkins_admin_password}"
echo "Jenkins URL: http://$PUBLIC_IP:8080"
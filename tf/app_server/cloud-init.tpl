#!/usr/bin/env bash
set -e  # Exit on error

# Function to log messages
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a /var/log/cloud-init-output.log
}

# Function to check command status
check_status() {
    if [ $? -eq 0 ]; then
        log "✓ $1 completed successfully"
    else
        log "✗ $1 failed"
        return 1
    fi
}

log "Starting cloud-init script"

# Add Docker's official GPG key
log "Installing prerequisites..."
sudo apt-get update
check_status "apt-get update" || exit 1

sudo apt-get install -y ca-certificates curl
check_status "Installing ca-certificates and curl" || exit 1

sudo install -m 0755 -d /etc/apt/keyrings
check_status "Creating keyrings directory" || exit 1

# Retry mechanism for downloading GPG key
max_attempts=3
attempt=1
while [ $attempt -le $max_attempts ]; do
    log "Attempting to download Docker GPG key (attempt $attempt of $max_attempts)"
    if sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc; then
        check_status "Downloading Docker GPG key"
        break
    else
        if [ $attempt -eq $max_attempts ]; then
            log "Failed to download Docker GPG key after $max_attempts attempts"
            exit 1
        fi
        log "Retrying in 5 seconds..."
        sleep 5
        ((attempt++))
    fi
done

sudo chmod a+r /etc/apt/keyrings/docker.asc
check_status "Setting GPG key permissions" || exit 1

# Add the repository to Apt sources
log "Adding Docker repository..."
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
check_status "Adding Docker repository" || exit 1

log "Updating apt after adding Docker repository..."
sudo apt-get update
check_status "apt-get update" || exit 1

log "Installing Docker..."
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
check_status "Installing Docker packages" || exit 1

# Start Docker service
log "Starting Docker service..."
sudo systemctl start docker
check_status "Starting Docker service" || exit 1

# Enable Docker service
log "Enabling Docker service..."
sudo systemctl enable docker
check_status "Enabling Docker service" || exit 1

# Verify Docker is running
log "Verifying Docker installation..."
if ! sudo docker run hello-world > /dev/null 2>&1; then
    log "Docker test failed. Installation may be incomplete."
    exit 1
fi
check_status "Docker verification" || exit 1

# Pull and run the container
log "Starting graph-terraform-run-task container..."
if sudo docker ps -a | grep -q graph-terraform-run-task; then
    log "Removing existing container..."
    sudo docker rm -f graph-terraform-run-task
fi

log "Pulling latest image..."
sudo docker pull stoffee/graph-terraform-run-task
check_status "Pulling Docker image" || exit 1

log "Starting container..."
sudo docker run -d \
    --name graph-terraform-run-task \
    --restart unless-stopped \
    -p 80:80 \
    stoffee/graph-terraform-run-task

if [ $? -eq 0 ]; then
    # Verify the container is running
    sleep 5
    if sudo docker ps | grep -q graph-terraform-run-task; then
        log "✓ Container started successfully"
    else
        log "✗ Container failed to start"
        log "Container logs:"
        sudo docker logs graph-terraform-run-task
        exit 1
    fi
else
    log "✗ Failed to start container"
    exit 1
fi

log "Cloud-init script completed successfully"
exit 0

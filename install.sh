#!/bin/bash
set -e # Exit on error
# Function for displaying prompts and storing user input to a file
prompt_and_store() {
read -p "$1" input
echo "$input" > "$2"
echo "$2=\$$2" >> install.log
}
# Function to log errors
log_error() {
echo "ERROR: $1" >> install.log
}
# Function to replace "SecretPassword" with the new password
replace_password() {
local new_password="$1"
sed -i "s|SecretPassword|$new_password|g" ./production-cluster.yml
}
# Function to replace user hashes in internal_users.yml
replace_user_hashes() {
local custom_hash
if [ -f "hash_code.txt" ]; then
custom_hash=$(cat "hash_code.txt")
sed -i "s|hash: \".*\"|hash: \"$custom_hash\"|g" production_cluster/elastic_opendistro/internal_users.yml
else
log_error "Custom hash file (hash_code.txt) not found."
exit 1
fi
}
# Create a log file to store user inputs and errors
touch install.log
# Update system and install prerequisites
echo "Updating the system and installing prerequisites..."
sudo apt update
sudo apt upgrade
# Install Docker
echo "Installing Docker..."
if ! sudo curl -fsSL https://get.docker.com/ | sh; then
log_error "Failed to install Docker."
exit 1
fi
sudo systemctl start docker
sudo systemctl enable docker
# Install Docker Compose
echo "Installing Docker Compose..."
if ! sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose; then
log_error "Failed to install Docker Compose."
exit 1
fi
sudo chmod +x /usr/local/bin/docker-compose
# Remove the existing symbolic link for Docker Compose if it exists
echo "Removing existing Docker Compose symbolic link..."
sudo rm -f /usr/bin/docker-compose
# Create a new symbolic link for Docker Compose
if ! sudo ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose; then
log_error "Failed to create a new Docker Compose symbolic link."
exit 1
fi
# Verify the Docker Compose version
docker-compose --version
# Configure Docker host preferences
echo "Configuring Docker host preferences..."
if ! sudo sysctl -w vm.max_map_count=262144; then
log_error "Failed to configure Docker host preferences."
exit 1
fi
# Clone the Wazuh Docker repo with the latest version
echo "Cloning the Wazuh Docker repository..."
if ! git clone https://github.com/wazuh/wazuh-docker.git -b v4.2.6 --depth=1; then
log_error "Failed to clone the Wazuh Docker repository."
exit 1
fi
# Generate SSL Certs for Elasticsearch
echo "Generating SSL Certs for Elasticsearch..."
cd wazuh-docker
if ! docker-compose -f generate-opendistro-certs.yml run --rm generator; then
log_error "Failed to generate SSL Certs for Elasticsearch."
exit 1
fi
# Generate SSL Certs for Kibana
echo "Generating SSL Certs for Kibana..."
if ! bash ./production_cluster/kibana_ssl/generate-self-signed-cert.sh; then
log_error "Failed to generate SSL Certs for Kibana."
exit 1
fi
# Generate SSL Certs for Nginx
echo "Generating SSL Certs for Nginx..."
if ! bash ./production_cluster/nginx/ssl/generate-self-signed-cert.sh; then
log_error "Failed to generate SSL Certs for Nginx."
exit 1
fi
# Prompt the user for a password and write it to a password.txt file
prompt_and_store "Enter a new password: " "password.txt"
# Prompt the user to run a separate command to generate the hash
echo "Run the following command to generate the password hash:"
echo "docker run --rm -ti amazon/opendistro-for-elasticsearch:1.13.2 bash /usr/share/elasticsearch/plugins/opendistro_security/tools/hash.sh"
echo "Copy and paste the generated hash into the next prompt."
# Prompt the user to enter the hash and write it to hash_code.txt
prompt_and_store "Enter the generated password hash: " "hash_code.txt"
# Replace "SecretPassword" with the new password in production-cluster.yml
replace_password "$(cat password.txt)"
# Replace user hashes in internal_users.yml
replace_user_hashes
# Deploy the SIEM stack
echo "Deploying the SIEM stack..."
if ! sudo docker-compose -f production-cluster.yml up -d; then
log_error "Failed to deploy the SIEM stack."
exit 1
fi
# Complete
echo "SIEM stack deployment completed."
# Optional: Cleanup
# rm install.log

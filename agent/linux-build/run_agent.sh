#!/bin/bash

# Exit on any error
set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'
BOLD=$(tput bold)
NORMAL=$(tput sgr0)

# Working directory
dir="/var/opt/authnull-db-agent"
mkdir -p $dir
cd $dir

if [ ! -f "authnull-db-agent" ] || [ ! -f "db.env" ]; then

  rm -rf ./*
  # Download the agent file
  rm -f authnull-db-agent
  echo -e "${GREEN}=> Downloading the agent file...${NC}${NORMAL}"
  rm -f authnull-db-agent
  wget https://github.com/authnull0/database-agent/raw/refs/heads/linux-mysql-db-agent/src/authnull-db-agent

  # Make the agent file executable
  echo -e "${GREEN}\n=> Making script executable...${NC}${NORMAL}"
  chmod +x authnull-db-agent
  echo -e "${GREEN}=> Done\n${NC}${NORMAL}"

  # db.env input prompt
  rm -f db.env
  echo -e "${GREEN}Please enter the content for the db.env file. End with an empty line or Ctrl+D:${NC}${NORMAL}"

  # Initialize an empty string to store the content
  db_env_content=""

  # Read input line by line
  while IFS= read -r line || [ -n "$line" ]; do
    # Append the line and a newline character to db_env_content
    db_env_content+="$line"$'\n'
  done

  # Remove the trailing newline character
  db_env_content=${db_env_content%$'\n'}

  # Create the db.env file with the provided content
  # sudo echo -n "$db_env_content" > db.env
  echo "$db_env_content" | tee -a db.env

  # Prompt for host, username, password and mode of operation
  echo -en "${BOLD}${YELLOW}=> Enter host${BLUE}: ${NORMAL}${NC}" ; read host; echo "DB_HOST=$host" | tee -a db.env
  echo -en "${BOLD}${YELLOW}=> Enter username${BLUE}: ${NORMAL}${NC}" ; read username; echo "DB_USER=$username" | tee -a db.env
  echo -en "${BOLD}${YELLOW}=> Enter password${BLUE}: ${NORMAL}${NC}" ; read password; echo "DB_PASSWORD=$password" | tee -a db.env

  source db.env

  # Download the service file
  echo -e "${GREEN}=> Downloading the service file...${NC}${NORMAL}"
  sudo rm -f run_agent.service
  wget https://github.com/authnull0/windows-endpoint/raw/refs/heads/DATAB-9/agent/linux-build/run_agent.service
  sed -i "6 i ExecStart=$dir/authnull-db-agent" run_agent.service
  sed -i "6 i WorkingDirectory=$dir" run_agent.service
  sed -i "6 i User=root" run_agent.service
  sudo mv run_agent.service /etc/systemd/system/
  sudo systemctl enable run_agent.service

fi

# Enable systemd service for the agent
sudo systemctl daemon-reload
sudo systemctl stop run_agent.service
sudo systemctl start run_agent.service

echo -e "${GREEN}=> Successfully started systemd service for the agent${NC}${NORMAL}"
cd -

# BEGIN PROXYSQL INSTALLATION
# Function to print status
print_status() {
    echo -e "${GREEN}[+] $1${NC}"
}

# Function to print error and exit
print_error() {
    echo -e "${RED}[-] ERROR: $1${NC}"
    exit 1
}

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root or with sudo."
fi

# Update package list
print_status "Updating package list..."
apt-get update -y || print_error "Failed to update package list."

# Install dependencies
print_status "Installing dependencies..."
apt-get install -y automake bzip2 cmake make g++ gcc git openssl libssl-dev libgnutls28-dev libtool patch uuid-dev \
    zlib1g-dev nlohmann-json3-dev libicu-dev build-essential libmysqlclient-dev libevent-dev libjemalloc-dev || \
    print_error "Failed to install dependencies."

# Clone ProxySQL repository
print_status "Cloning ProxySQL repository..."
if [ -d "proxysql-v3-alpha" ]; then
    print_status "Directory proxysql-v3-alpha already exists, pulling latest changes..."
    cd proxysql-v3-alpha
    git pull || print_error "Failed to pull latest changes from repository."
else
    git clone https://github.com/authnull0/proxysql-v3-alpha.git || print_error "Failed to clone repository."
    cd proxysql-v3-alpha
fi

# Checkout authsql branch
print_status "Checking out authsql branch..."
git checkout authsql || print_error "Failed to checkout authsql branch."

# Build ProxySQL
print_status "Cleaning previous build..."
make clean || print_error "Failed to clean previous build."

print_status "Building ProxySQL with $(nproc) jobs..."
make -j$(nproc) || print_error "Failed to build ProxySQL."

print_status "Installing ProxySQL..."
make install || print_error "Failed to install ProxySQL."

# Ensure ProxySQL user and group exist
print_status "Creating proxysql user and group if not exists..."
id -u proxysql &>/dev/null || useradd -r -s /bin/false proxysql
getent group proxysql &>/dev/null || groupadd -r proxysql
usermod -a -G proxysql proxysql || print_error "Failed to configure proxysql user/group."

# Remove existing PID file if it exists
if [ -f "/var/lib/proxysql/proxysql.pid" ]; then
    print_status "Removing existing PID file..."
    rm -f /var/lib/proxysql/proxysql.pid || print_error "Failed to remove PID file."
fi

# Create systemd service file
print_status "Setting up systemd service file..."
cat > /usr/lib/systemd/system/proxysql.service << EOL
[Unit]
Description=High Performance Advanced Proxy for MySQL
After=network.target

[Service]
Type=forking
ExecStart=/usr/bin/proxysql --idle-threads -c /etc/proxysql.cnf
PIDFile=/var/lib/proxysql/proxysql.pid
User=proxysql
Group=proxysql
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOL
[ $? -eq 0 ] || print_error "Failed to create systemd service file."

# Set up configuration file and permissions
print_status "Configuring /etc/proxysql.cnf..."
if [ ! -f "/etc/proxysql.cnf" ]; then
    touch /etc/proxysql.cnf || print_error "Failed to create /etc/proxysql.cnf."
fi

# Add authnull section to proxysql.cnf
cat >> /etc/proxysql.cnf << EOL

authnull =
{
    org_id = 105
    tenant_id = 1
    api_url = "https://prod.api.authnull.com/authnull0/api/v1/authn/v3/do-authenticationV4"
}
EOL
[ $? -eq 0 ] || print_error "Failed to update /etc/proxysql.cnf."

# Set permissions
print_status "Setting permissions for /etc/proxysql.cnf..."
chown proxysql:proxysql /etc/proxysql.cnf || print_error "Failed to chown /etc/proxysql.cnf."
chmod 644 /etc/proxysql.cnf || print_error "Failed to chmod /etc/proxysql.cnf."

# Create and set permissions for /var/lib/proxysql/
print_status "Setting up /var/lib/proxysql/..."
mkdir -p /var/lib/proxysql/ || print_error "Failed to create /var/lib/proxysql/."
chown proxysql:proxysql /var/lib/proxysql/ || print_error "Failed to chown /var/lib/proxysql/."

# Reload systemd daemon
print_status "Reloading systemd daemon..."
systemctl daemon-reload || print_error "Failed to reload systemd daemon."

# Stop any running ProxySQL instances
print_status "Stopping any running ProxySQL instances..."
killall proxysql 2>/dev/null || true

# Start ProxySQL service
print_status "Starting ProxySQL service..."
systemctl restart proxysql || print_error "Failed to restart proxysql service."

# Enable ProxySQL to start on boot
print_status "Enabling ProxySQL service on boot..."
systemctl enable proxysql || print_error "Failed to enable proxysql service."

print_status "ProxySQL setup completed successfully!"
echo "You can check the status with: systemctl status proxysql"

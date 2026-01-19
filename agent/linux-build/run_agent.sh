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
dir="/opt/authnull-db-agent"
service_binary="db-agent"
service_name="db-agent.service"
service_src="$dir/$service_name"
service_dst="/etc/systemd/system/$service_name"
env_file="$dir/db.env"

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root or with sudo."
    exit 1
fi
#Check Agent running Status 
agent_status() {
    local svc="$1"
    echo "Checking if $svc is already running"
    if pgrep -f "$svc" >/dev/null; then
        echo "Process $svc is running."
        return 0  # success means running
    else 
        echo "Process $svc is not running"
        return 1 # failure means not running 
    fi
}

  # Stop the existing agent if running
  echo -e "${YELLOW}=> Checking for existing agent service...${NC}${NORMAL}"
  if agent_status "$service_binary"; then
    echo -e "${YELLOW}=> Stopping existing agent service...${NC}${NORMAL}"
    sudo systemctl stop db-agent.service || echo "Service not running, continuing..."
    sudo systemctl disable db-agent.service || echo "Service not enabled, continuing..."
    sudo systemctl daemon-reload
  fi
  if [ ! -d "$dir" ]; then
    echo "Directory does not exist. Creating: $dir"
    mkdir -p "$dir"
    cd "$dir" || exit 1
  else
    echo "Directory already exists: $dir"
    cd "$dir" || exit 1
    echo -e "${YELLOW}=> Cleaning up existing files...${NC}${NORMAL}"    
    rm -rf ./*    
  fi
  
  echo -e "${GREEN}=> Downloading the agent file...${NC}${NORMAL}"
  wget -O db-agent https://github.com/authnull0/database-agent/raw/refs/heads/checkout_postgres/authnull-db-agent

  # Make the agent file executable
  echo -e "${GREEN}\n=> Making script executable...${NC}${NORMAL}"
  chmod +x db-agent
  echo -e "${GREEN}=> Done\n${NC}${NORMAL}"
  # Prompt user to input content for db.env
  echo -e "${GREEN}Please enter the content for the db.env file. End with an empty line or Ctrl+D:${NC}${NORMAL}"
  echo -e "${YELLOW}Required fields: ORG_ID, TENANT_ID, DB_TYPE, DB_PORT, TIME_INTERVAL, API, KEY, MACHINE_KEY${NC}${NORMAL}"
  echo -e "${YELLOW}Example:${NC}"
  echo -e "ORG_ID=1"
  echo -e "TENANT_ID=1"
  echo -e "DB_TYPE=postgres"
  echo -e "DB_PORT=5432"
  echo -e "TIME_INTERVAL=1"
  echo -e "API=https://prod.api.authnull.com"
  echo -e "KEY=your-key"
  echo -e "MACHINE_KEY=AGENT01"
  echo ""

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

  # Get this agent VM's IP address for multi-host mode
  echo -e "${GREEN}=> Detecting Agent VM IP address...${NC}${NORMAL}"
  agent_vm_ip=$(hostname -I | awk '{print $1}')
  echo -e "${YELLOW}Detected IP: $agent_vm_ip${NC}"
  echo -en "${BOLD}${YELLOW}=> Confirm Agent VM IP (press Enter to use $agent_vm_ip or type new IP)${BLUE}: ${NORMAL}${NC}"
  read -r custom_ip
  if [ -n "$custom_ip" ]; then
    agent_vm_ip="$(echo "$custom_ip" | xargs)"
  fi
  echo "AGENT_VM_IP=$agent_vm_ip" | tee -a db.env

  # Multi-host configuration
  echo ""
  echo -e "${GREEN}========================================${NC}"
  echo -e "${GREEN}  MULTI-HOST DATABASE CONFIGURATION${NC}"
  echo -e "${GREEN}========================================${NC}"
  echo -e "${YELLOW}This agent can manage multiple database hosts.${NC}"
  echo -e "${YELLOW}You will be prompted to add database hosts one by one.${NC}"
  echo ""

  # Initialize hosts JSON file
  hosts_file="$dir/db_hosts.json"
  echo '{"hosts":[]}' > "$hosts_file"

  host_count=0
  add_more="y"

  while [[ "$add_more" =~ ^[Yy]$ ]]; do
    host_count=$((host_count + 1))
    echo ""
    echo -e "${GREEN}--- Database Host #$host_count ---${NC}"

    # Prompt for host VM IP
    echo -en "${BOLD}${YELLOW}=> Enter Database Host VM IP${BLUE}: ${NORMAL}${NC}"
    read -r host_vm_ip
    host_vm_ip="$(echo "$host_vm_ip" | xargs)"

    # Prompt for port (default 5432)
    echo -en "${BOLD}${YELLOW}=> Enter Database Port (default: 5432)${BLUE}: ${NORMAL}${NC}"
    read -r db_port
    db_port="$(echo "$db_port" | xargs)"
    if [ -z "$db_port" ]; then
      db_port="5432"
    fi

    # Prompt for username
    echo -en "${BOLD}${YELLOW}=> Enter Database Admin Username${BLUE}: ${NORMAL}${NC}"
    read -r username
    username="$(echo "$username" | xargs)"

    # Prompt for password (hidden input)
    echo -en "${BOLD}${YELLOW}=> Enter Database Admin Password${BLUE}: ${NORMAL}${NC}"
    read -s password
    echo

    # Add host to JSON file using jq or manual JSON construction
    if command -v jq &> /dev/null; then
      # Use jq if available
      jq --arg ip "$host_vm_ip" --arg port "$db_port" --arg user "$username" --arg pass "$password" \
        '.hosts += [{"host_vm_ip": $ip, "port": $port, "username": $user, "password": $pass}]' \
        "$hosts_file" > "${hosts_file}.tmp" && mv "${hosts_file}.tmp" "$hosts_file"
    else
      # Manual JSON construction if jq is not available
      if [ $host_count -eq 1 ]; then
        echo "{\"hosts\":[{\"host_vm_ip\":\"$host_vm_ip\",\"port\":\"$db_port\",\"username\":\"$username\",\"password\":\"$password\"}]}" > "$hosts_file"
      else
        # Append to existing hosts array
        sed -i "s/\]}$/,{\"host_vm_ip\":\"$host_vm_ip\",\"port\":\"$db_port\",\"username\":\"$username\",\"password\":\"$password\"}]}/" "$hosts_file"
      fi
    fi

    echo -e "${GREEN}✓ Host #$host_count added: $host_vm_ip:$db_port${NC}"

    # Ask if user wants to add more hosts
    echo ""
    echo -en "${BOLD}${YELLOW}=> Add another database host? (y/n)${BLUE}: ${NORMAL}${NC}"
    read -r add_more
  done

  echo ""
  echo -e "${GREEN}Total hosts configured: $host_count${NC}"

  # Set permissions on hosts file (contains passwords)
  chmod 600 "$hosts_file"

  # For backward compatibility, also set the first host as DB_HOST, DB_USER, DB_PASSWORD
  # This allows the agent to work in single-host mode if needed
  if [ $host_count -ge 1 ]; then
    if command -v jq &> /dev/null; then
      first_host=$(jq -r '.hosts[0].host_vm_ip' "$hosts_file")
      first_user=$(jq -r '.hosts[0].username' "$hosts_file")
      first_pass=$(jq -r '.hosts[0].password' "$hosts_file")
    else
      # Parse manually (basic extraction)
      first_host=$(grep -o '"host_vm_ip":"[^"]*"' "$hosts_file" | head -1 | cut -d'"' -f4)
      first_user=$(grep -o '"username":"[^"]*"' "$hosts_file" | head -1 | cut -d'"' -f4)
      first_pass=$(grep -o '"password":"[^"]*"' "$hosts_file" | head -1 | cut -d'"' -f4)
    fi

    echo "DB_HOST=$first_host" | tee -a db.env
    echo "DB_USER=$first_user" | tee -a db.env

    # Remove existing entry if present
    sed -i '/^DB_PASSWORD=/d' db.env 2>/dev/null
    # Write password silently
    printf 'DB_PASSWORD=%s\n' "$first_pass" >> db.env

    echo -e "${GREEN}✓ Primary host set in db.env: $first_host${NC}"
  fi

  echo ""
  echo -e "${GREEN}========================================${NC}"
  echo -e "${GREEN}  Configuration Summary${NC}"
  echo -e "${GREEN}========================================${NC}"
  echo -e "Agent VM IP: $agent_vm_ip"
  echo -e "Total Database Hosts: $host_count"
  echo -e "Hosts file: $hosts_file"
  echo -e "Environment file: $env_file"
  echo ""


  # Download the service file
  echo -e "${GREEN}=> Downloading the service file...${NC}${NORMAL}"
  wget https://github.com/authnull0/windows-endpoint/raw/refs/heads/postgres-db-agent/agent/linux-build/db-agent.service
  
# Check if /etc/systemd/system is writable
if [ -w /etc/systemd/system ]; then
    echo "/etc/systemd/system is writable"
    sudo mv db-agent.service /etc/systemd/system/
    echo "Service file moved to /etc/systemd/system/db-agent.service"
    sudo chmod 644 /etc/systemd/system/db-agent.service
else
    echo "/etc/systemd/system is NOT writable"
    # Create symlink
    if [ ! -L "$service_dst" ]; then
        sudo ln -s "$service_src" "$service_dst"
        echo "Symlink created: $service_dst → $service_src"
        sudo chmod 644 "$service_dst"
    else
        echo "Symlink already exists"
    fi
fi
  
# Enable systemd service for the agent
echo -e "${GREEN}=> Enabling and starting the agent service...${NC}${NORMAL}"
sudo systemctl daemon-reload
sudo systemctl start db-agent
sudo systemctl enable db-agent

# Verify if the agent service is running
if agent_status "$service_binary"; then
    echo -e "${GREEN}=> Agent service is running successfully.${NC}${NORMAL}"
else
    echo -e "${RED}=> ERROR: Agent service failed to start.${NC}${NORMAL}"
    exit 1
fi
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

# Update package list
print_status "Updating package list..."
apt-get update -y || print_error "Failed to update package list."

print_status "Installing dependencies..."

apt-get update -y && \
apt-get install -y \
    build-essential \
    automake \
    cmake \
    make \
    git \
    pkg-config \
    bzip2 \
    patch \
    libtool \
    uuid-dev \
    zlib1g-dev \
    libevent-dev \
    libjemalloc-dev \
    libssl-dev \
    libgnutls28-dev \
    libicu-dev \
    nlohmann-json3-dev \
    default-libmysqlclient-dev \
    mysql-client-core-8.0 \
    postgresql \
    postgresql-contrib \
    || print_error "Failed to install dependencies."
# check if proxysql service is already running
if agent_status proxysql; then
    print_status "ProxySQL service is already running"
    echo "Stopping existing ProxySQL service..."
    sudo systemctl stop proxysql || print_error "Failed to stop existing ProxySQL service."
    sudo systemctl disable proxysql || print_error "Failed to disable existing ProxySQL service."
else
    print_status "ProxySQL service is not running. Proceeding with configuration."
fi
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
git checkout authsql-postgres || print_error "Failed to checkout authsql branch."

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
if [ -w /usr/lib/systemd/system ]; then
print_status "/usr/lib/systemd/system is writable"
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
else
    echo "/usr/lib/systemd/system is NOT writable"
    echo "Cannot create systemd service file."
    print_error "ProxySQL service file creation failed."
fi

# Set up configuration file and permissions
print_status "Configuring /etc/proxysql.cnf..."
if [ ! -f "/etc/proxysql.cnf" ]; then
    touch /etc/proxysql.cnf || print_error "Failed to create /etc/proxysql.cnf."
fi

if [ ! -f "$env_file" ]; then
    print_error "Environment file not found: $env_file"
fi

# Export variables from env file
set -a
source "$env_file"
set +a
if [ -z "$ORG_ID" ] || [ -z "$TENANT_ID" ]; then
    print_error "ORG_ID or TENANT_ID not set in $env_file"
fi


# Add authnull section to proxysql.cnf
cat >> /etc/proxysql.cnf << EOL

authnull =
{
    org_id = $ORG_ID
    tenant_id = $TENANT_ID
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

if agent_status proxysql; then
    print_status "ProxySQL service is running successfully."
else
    print_error "ERROR: ProxySQL service failed to start."
    exit 1
fi
# Restart db agent once again to ensure connectivity to proxysql
print_status "Restarting db-agent service to ensure connectivity to ProxySQL..."
systemctl restart db-agent || print_error "Failed to restart db-agent service."
if agent_status "$service_binary"; then
    print_status "db-agent service is running successfully."
else
    print_error "ERROR: db-agent service failed to start after ProxySQL installation."
    exit 1
fi
print_status "All services are up and running."
print_status "Database Agent Installation and Setup completed successfully."
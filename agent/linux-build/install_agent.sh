#!/bin/bash

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'
BOLD=$(tput bold)
NORMAL=$(tput sgr0)

if [ ! "$PWD" = "/etc/authnull-db-agent" ]; then
  echo -e "${RED}Please run the script from /etc/authnull-db-agent${NC}"
  exit 1
fi

# Download the agent file
rm -f authnull-db-agent
echo -e "${GREEN}=> Downloading the agent file...${NC}${NORMAL}"
sudo rm -f authnull-db-agent
sudo wget https://github.com/authnull0/database-agent/raw/refs/heads/linux-mysql-db-agent/src/authnull-db-agent

# Make the agent file executable
echo -e "${GREEN}\n=> Making script executable...${NC}${NORMAL}"
sudo chmod +x authnull-db-agent
echo -e "${GREEN}=> Done\n${NC}${NORMAL}"

# db.env input prompt
sudo rm -f db.env
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
echo "$db_env_content" | sudo tee -a db.env

# Prompt for host, username, password and mode of operation
echo -en "${BOLD}${YELLOW}=> Enter host${BLUE}: ${NORMAL}${NC}" ; read host; sudo echo "HOST=$host" | sudo tee -a db.env
echo -en "${BOLD}${YELLOW}=> Enter username${BLUE}: ${NORMAL}${NC}" ; read username; echo "USERNAME=$username" | sudo tee -a db.env
echo -en "${BOLD}${YELLOW}=> Enter password${BLUE}: ${NORMAL}${NC}" ; read password; echo "PASSWORD=$password" | sudo tee -a db.env
echo -en "${BOLD}${YELLOW}=> Enter mode (install, start, stop, restart, uninstall, debug) ${BLUE}: ${NORMAL}${NC}" ; read mode; echo "MODE=$mode" | sudo tee -a db.env

source db.env

# Download the service file
echo -e "${GREEN}=> Downloading the service file...${NC}${NORMAL}"
sudo rm -f run_agent.service
sudo wget https://github.com/authnull0/windows-endpoint/raw/refs/heads/DATAB-9/agent/linux-build/run_agent.service
sudo mv run_agent.service /etc/systemd/system/

# Download the run script
sudo rm -f run_agent.sh
sudo wget https://github.com/authnull0/windows-endpoint/raw/refs/heads/DATAB-9/agent/linux-build/run_agent.sh
sudo chmod +x run_agent.sh

# Enable systemd service for the agent
sudo systemctl enable run_agent.service
sudo systemctl daemon-reload
sudo systemctl stop run_agent.service
sudo systemctl start run_agent.service

echo -e "${GREEN}=> Successfully started systemd service for the agent${NC}${NORMAL}"

# Run the agent
# ./authnull-db-agent -host "$HOST" -username "$USERNAME" -password "$PASSWORD" -mode "$MODE"

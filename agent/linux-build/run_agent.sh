#!/bin/bash

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'
BOLD=$(tput bold)
NORMAL=$(tput sgr0)

# Download the agent file
if [ ! -f "authnull-db-agent" ] || [ "$1" = "--install" ]; then
  rm -f authnull-db-agent
  echo -e "${GREEN}=> Downloading the agent file...${NC}${NORMAL}"
  wget https://github.com/authnull0/database-agent/raw/refs/heads/linux-mysql-db-agent/src/authnull-db-agent

  # Make the agent file executable
  echo -e "${GREEN}\n=> Making script executable...${NC}${NORMAL}"
  sudo chmod +x authnull-db-agent
  echo -e "${GREEN}=> Done\n${NC}${NORMAL}"
fi

if [ ! -f "db.env" ] || [ "$1" = "--install" ]; then
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
  echo -n "$db_env_content" > db.env

  # Prompt for host, username, password and mode of operation
  echo -en "${BOLD}${YELLOW}=> Enter host${BLUE}: ${NORMAL}${NC}" ; read host; echo -e "\nHOST=$host" >> db.env
  echo -en "${BOLD}${YELLOW}=> Enter username${BLUE}: ${NORMAL}${NC}" ; read username; echo -e "USERNAME=$username" >> db.env
  echo -en "${BOLD}${YELLOW}=> Enter password${BLUE}: ${NORMAL}${NC}" ; read password; echo -e "PASSWORD=$password" >> db.env
  echo -en "${BOLD}${YELLOW}=> Enter mode (install, start, stop, restart, uninstall, debug) ${BLUE}: ${NORMAL}${NC}" ; read mode; echo -e "MODE=$mode" >> db.env
fi

source db.env

# Run the agent
./authnull-db-agent -host "$HOST" -username "$USERNAME" -password "$PASSWORD" -mode "$MODE"

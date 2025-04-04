#!/bin/bash

# Define colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Update package list
echo -e "${GREEN}Updating package lists...${NC}"
sudo apt update -y

# Install FreeRADIUS and dependencies
echo -e "${GREEN}Installing FreeRADIUS...${NC}"
sudo apt install -y freeradius freeradius-utils

# Enable FreeRADIUS service
echo -e "${GREEN}Enabling FreeRADIUS service...${NC}"
sudo systemctl enable freeradius

# Start FreeRADIUS service
echo -e "${GREEN}Starting FreeRADIUS service...${NC}"
sudo systemctl start freeradius

# Check FreeRADIUS service status
echo -e "${GREEN}Checking FreeRADIUS status...${NC}"
sudo systemctl status freeradius --no-pager

# Print success message
echo -e "${GREEN}FreeRADIUS installation completed successfully!${NC}"

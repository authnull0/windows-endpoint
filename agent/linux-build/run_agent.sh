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

source db.env
./authnull-db-agent -host "$HOST" -username "$USERNAME" -password "$PASSWORD" -mode "$MODE"

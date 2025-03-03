#!/bin/bash

# Exit on any error
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Function to print status messages
print_status() {
    echo -e "${GREEN}==> $1${NC}"
}

# 1. Update the system
print_status "Updating the system..."
sudo apt-get update -y

# 2.1 Install FreeRADIUS
print_status "Installing FreeRADIUS and required utilities..."
sudo apt-get install -y freeradius freeradius-utils

# Verify FreeRADIUS installation
dpkg -l | grep freeradius || { echo -e "${RED}FreeRADIUS installation failed!${NC}"; exit 1; }

# 2.4 Configure Authentication Methods (automated)
print_status "Configuring FreeRADIUS authentication methods..."


# Add authnull_2fa to authorize and authenticate sections using sed
# Append `authnull_2fa` at the end of the authorize section
sudo sed -i '/^authorize {/,/^}/ s/^}/    authnull_2fa 
    if (ok) { 

        update control { 

            Auth-Type := Accept 

        } 

        update reply { 

            Reply-Message := "2FA Successful" 

        } 

    } 

    else { 

        reject 

    } \n}/' /etc/freeradius/3.0/sites-enabled/default

# Append `authnull_2fa` at the end of the authenticate section
sudo sed -i '/^authenticate {/,/^}/ s/^}/    authnull_2fa\n}/' /etc/freeradius/3.0/sites-enabled/default


# 2.5 Configure Exec Section (automated)
print_status "Configuring FreeRADIUS exec module..."

cat << 'EOF' | sudo tee /etc/freeradius/3.0/mods-available/exec > /dev/null
exec {
    wait = yes
    input_pairs = request
    output_pairs = reply
    shell_escape = yes
    timeout = 10
    pass_through = yes
}
EOF

# Enable the exec module
sudo ln -sf /etc/freeradius/3.0/mods-available/exec /etc/freeradius/3.0/mods-enabled/

# 3.1 Install 2FA Script (authnull_2fa) (automated)
print_status "Installing 2FA script (authnull_2fa)..."
# Download the binary from the repository
wget https://github.com/authnull0/windows-endpoint/tree/main/agent/radius-build -O authnull_2fa 
# Install the binary
sudo mv authnull_2fa /usr/local/bin/
sudo chmod 755 /usr/local/bin/authnull_2fa
sudo chown root:root /usr/local/bin/authnull_2fa

# 3.2 Configure FreeRADIUS 2FA Module (automated)
print_status "Configuring FreeRADIUS 2FA module..."

# Create or update authnull_2fa module configuration
cat << 'EOF' | sudo tee /etc/freeradius/3.0/mods-available/authnull_2fa > /dev/null
exec authnull_2fa {
    wait = yes
    program = "/usr/local/bin/authnull_2fa \
        \"%{User-Name}@authnull.com\" \"%{User-Password}\" \"%{CHAP-Password}\" \
        \"%{Calling-Station-Id}\" \"%{NAS-IP-Address}\" \"%{NAS-Port}\" \
        \"%{NAS-Identifier}\" \"%{NAS-Port-Type}\" \"%{Framed-IP-Address}\" \
        \"%{Called-Station-Id}\" \"%{Service-Type}\" \"%{Framed-Protocol}\" \
        \"%{Filter-Id}\" \"%{Class}\" \"%{Session-Timeout}\" \
        \"%{Idle-Timeout}\" \"%{Acct-Session-Id}\" \"%{Acct-Input-Octets}\" \
        \"%{Acct-Output-Octets}\" \"%{Vendor-Specific}\" \"%{State}\" \
        \"%{Reply-Message}\""
    shell_escape = yes
    output = Reply-Message
}
EOF

# Enable the authnull_2fa module
sudo ln -sf /etc/freeradius/3.0/mods-available/authnull_2fa /etc/freeradius/3.0/mods-enabled/


# 6. Install and configure Fluent Bit (automated)
print_status "Installing and configuring Fluent Bit..."
curl https://raw.githubusercontent.com/fluent/fluent-bit/master/install.sh | sh

# Configure Fluent Bit
cat << 'EOF' | sudo tee /etc/fluent-bit/fluent-bit.conf > /dev/null
[SERVICE]
    Flush             1
    Log_Level         debug
    Parsers_File      /etc/fluent-bit/parsers.conf

[INPUT]
    Name              tail
    Path              /var/log/radius_2fa.log
    Tag               radius_log
    Mem_Buf_Limit     5MB
    Read_from_Head    On
    Parser            json_parser

[FILTER]
    Name    grep
    Match   radius_log
    Regex   eventType radius_auth

[OUTPUT]
    Name    stdout
    Match   radius_log
    Format  json

[OUTPUT]
    Name        http
    Match       radius_log
    Host        monitoring.authnull.com
    Port        443
    URI         /
    tls         on
    tls.verify  on
    Retry_Limit false
    Header      Content-Type application/json
    Format      json
EOF

print_status "FreeRADIUS with 2FA and Fluent Bit setup completed successfully!"

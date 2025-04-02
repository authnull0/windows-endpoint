#!/bin/bash

# This script deploys the pam module in a linux machine
echo "Downloading the pam module..."
curl -L -o pam_custom.so https://github.com/authnull0/windows-endpoint/raw/refs/heads/main/pam-authnull/pam_authnull.so
if [ $? -ne 0 ]; then
    echo "Failed to download the .so file."
    exit 1
fi
echo "Downloaded the .so file successfully."

#Copying the pam module to /lib/x86_64-linux-gnu/security/
echo "Copying pam_authnull.so to /lib/x86_64-linux-gnu/security/"
sudo cp pam_authnull.so /lib/x86_64-linux-gnu/security/.
if [ $? -eq 0 ]; then
    echo "pam_authnull.so successfully copied."
else
    echo "Failed to copy pam_authnull.so. Check permissions or file existence." >&2
    exit 1
fi

#CConfigure the sshd_config file
echo "Configuring /etc/ssh/sshd_config..."

if grep -q "^KbdInteractiveAuthentication no" /etc/ssh/sshd_config; then
    sudo sed -i 's/^KbdInteractiveAuthentication no/KbdInteractiveAuthentication yes/g' /etc/ssh/sshd_config
fi

if grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config; then
    sudo sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config
fi

if ! grep -q "AuthenticationMethods keyboard-interactive" /etc/ssh/sshd_config; then
    sudo sh -c 'echo "AuthenticationMethods keyboard-interactive" >> /etc/ssh/sshd_config'
fi

# #Configure the pam.d/sshd file
# echo "configuring /etc/pam.d/sshd..."

# # Check if the line is already present
# if ! grep -q "auth            sufficient              /lib/x86_64-linux-gnu/security/pam_authnull.so" /etc/pam.d/sshd; then
#     # Prepend the line to the top of the file
#     sudo sh -c 'echo "auth            sufficient              /lib/x86_64-linux-gnu/security/pam_authnull.so" | cat - /etc/pam.d/sshd > /tmp/sshd && mv /tmp/sshd /etc/pam.d/sshd'
# fi



#!/bin/bash

# Define the path to the env file
ENV_FILE="/usr/local/sbin/app.env"

# Define the target PAM file
PAM_FILE="/etc/pam.d/sshd"

# Read ORG_ID and TENANT_ID from the env file
if [[ -f "$ENV_FILE" ]]; then
    ORG_ID=$(grep "^ORG_ID=" "$ENV_FILE" | cut -d '=' -f2)
    TENANT_ID=$(grep "^TENANT_ID=" "$ENV_FILE" | cut -d '=' -f2)
else
    echo "Error: $ENV_FILE not found!"
    exit 1
fi

# Validate if values were retrieved
if [[ -z "$ORG_ID" || -z "$TENANT_ID" ]]; then
    echo "Error: ORG_ID or TENANT_ID not found in $ENV_FILE"
    exit 1
fi

# Define the auth line to be added
AUTH_LINE="auth sufficient /lib/x86_64-linux-gnu/security/pam_authnull.so tenant_id=$TENANT_ID org_id=$ORG_ID"

# Check if the line already exists in the file
if grep -Fxq "$AUTH_LINE" "$PAM_FILE"; then
    echo "Entry already exists in $PAM_FILE"
else
    # Add the line to the PAM configuration file
    echo "$AUTH_LINE" >> "$PAM_FILE"
    echo "Updated $PAM_FILE with: $AUTH_LINE"
fi

# Comment out @include common-auth line
echo "Commenting out '@include common-auth' in /etc/pam.d/sshd..."
if grep -q "@include common-auth" /etc/pam.d/sshd; then
    sudo sed -i 's/^@include common-auth/#&/' /etc/pam.d/sshd
    echo "Successfully commented out '@include common-auth'."
fi

#Restart the sshd service
echo "Restarting sshd service..."
sudo systemctl restart sshd
if [ $? -eq 0 ]; then
    echo "sshd service restarted successfully."
else
    echo "Failed to restart sshd service." >&2
    exit 1
fi

#Restart the ssh service
echo "Restarting ssh service..."
sudo systemctl restart ssh
if [ $? -eq 0 ]; then
    echo "ssh service restarted successfully."
else
    echo "Failed to restart ssh service." >&2
    exit 1
fi

# Log the SSH service restart status
echo "SSH service restart attempted. Check the logs with: tail -f /var/log/auth.log (Ubuntu) or tail -f /var/log/secure (CentOS)"
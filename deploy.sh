#!/bin/bash

# Exit on any error
set -e

echo "Starting deployment process..."

### Step 1: Download and Setup the Agent ###

# Download the agentv2.tar.gz file using curl and the provided token
echo "Downloading agentv2.tar.gz..."
curl -L -H "Authorization: token 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" -o agentv2.tar.gz "https://github.gwd.broadcom.net/ESD/SSP-Passwordless/blob/passwordless_integration/ssp-linux-agents/endpoint-daemon-pam/agentv2.tar.gz?raw=true"

# Uncompress the tar.gz file
echo "Uncompressing agentv2.tar.gz..."
tar -xzvf agentv2.tar.gz

# Prompt the user for input to create the app.env file
echo "Please enter the content for the app.env file. End with an empty line or Ctrl+D:"
app_env_content=""
while IFS= read -r line || [ -n "$line" ]; do
    app_env_content+="$line"$'\n'
done
app_env_content=${app_env_content%$'\n'}
echo -n "$app_env_content" > app.env

# Make the agent file executable and run it
chmod +x agentv2
./agentv2

### Step 2: Install the SSP Agent and Setup Service ###

# Download the SSP agent binary
echo "Downloading SSP agent binary..."
curl -L -o ssp_agent https://github.com/authnull0/windows-endpoint/raw/refs/heads/ssp-agent/ssp-agent/ssp_agent

# Download the SSP agent service file
echo "Downloading SSP agent service file..."
curl -L -o ssp_agent.service https://github.com/authnull0/windows-endpoint/raw/refs/heads/ssp-agent/ssp-agent/ssp_agent.service

# Copy the service file to systemd and set permissions
echo "Setting up SSP agent service..."
sudo cp ssp_agent.service /etc/systemd/system/
sudo chmod 644 /etc/systemd/system/ssp_agent.service

# Copy the agent binary to /usr/local/sbin and set permissions
sudo cp ssp_agent /usr/local/sbin/
sudo chmod 755 /usr/local/sbin/ssp_agent
sudo chown root:root /usr/local/sbin/ssp_agent

# Reload systemd and start the service
sudo systemctl daemon-reload
sudo systemctl start ssp_agent
sudo systemctl enable ssp_agent

### Step 3: Deploy the Custom PAM Module ###

# Update and install dependencies
echo "Updating system and installing dependencies..."
sudo apt-get update
sudo apt-get install -y gcc libpam0g-dev libldap2-dev curl

# # Download the LDAP configuration file
# LDAP_CONFIG_FILE="pam_custom_ldap_pwd.c"
# LDAP_CONFIG_URL="https://github.com/authnull0/windows-endpoint/raw/refs/heads/linux-agent-brcm/custom_pam_module/pam_custom_ldap_pwd.c"
# if [ ! -f "$LDAP_CONFIG_FILE" ]; then
#     echo "Downloading $LDAP_CONFIG_FILE..."
#     curl -o "$LDAP_CONFIG_FILE" "$LDAP_CONFIG_URL"
# else
#     echo "$LDAP_CONFIG_FILE already exists. Skipping download."
# fi

# # Verify LDAP configuration
# echo "Please verify $LDAP_CONFIG_FILE for correct LDAP values (LDAP_URI, BASE_DN, LDAP_BIND_DN, LDAP_BIND_PW)."
# read -p "Press Enter to continue after verification..."

#Download the .so file 
echo "Downloading pam_custom.so..."
curl -L -o pam_custom.so "https://github.com/authnull0/windows-endpoint/raw/refs/heads/linux-agent-brcm/custom_pam_module/pam_custom.so"

# # Compile the custom PAM module
# echo "Compiling the custom PAM module..."
# gcc -fPIC -shared -o pam_custom.so pam_custom_ldap_pwd.c -lpam -lldap

#copying the .so file to /lib/x86_64-linux-gnu/security/
echo "Copying pam_custom.so to /lib/x86_64-linux-gnu/security/..."
sudo cp pam_custom.so /lib/x86_64-linux-gnu/security/

# Copy the `did.sh` file if it exists
DID_SCRIPT="did.sh"
if [ -f "$DID_SCRIPT" ]; then
    echo "Copying $DID_SCRIPT to root directory..."
    sudo cp did.sh /
else
    echo "Warning: $DID_SCRIPT not found. Skipping..."
fi

# Update sshd_config
SSHD_CONFIG="/etc/ssh/sshd_config"
echo "Updating $SSHD_CONFIG..."
sudo sed -i 's/^#?PasswordAuthentication.*/PasswordAuthentication yes/' $SSHD_CONFIG
sudo sed -i 's/^#?KbdInteractiveAuthentication.*/KbdInteractiveAuthentication yes/' $SSHD_CONFIG
if ! grep -q "AuthenticationMethods keyboard-interactive" $SSHD_CONFIG; then
    echo "AuthenticationMethods keyboard-interactive" | sudo tee -a $SSHD_CONFIG
fi

# Update PAM sshd file
PAM_SSHD_FILE="/etc/pam.d/sshd"
echo "Updating $PAM_SSHD_FILE..."
if ! grep -q "pam_custom.so" $PAM_SSHD_FILE; then
    echo "auth    sufficient    /lib/x86_64-linux-gnu/security/pam_custom.so" | sudo tee -a $PAM_SSHD_FILE
fi

# Restart SSH service
echo "Restarting SSH service..."
sudo systemctl restart sshd

echo "Deployment complete. All components have been installed and configured successfully."

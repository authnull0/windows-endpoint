#!/bin/bash

# Check if curl is installed
if command -v curl >/dev/null 2>&1; then
    echo "curl is already installed."
else
    read -p "curl is not installed. Do you want to install it? (y/n): " user_input
    if [[ "$user_input" != "y" && "$user_input" != "Y" ]]; then
        echo "Installation aborted by user."
        exit 1
    fi

    # Detect package manager and install curl
    if command -v apt >/dev/null 2>&1; then
        echo "Detected apt-based system. Installing curl..."
        sudo apt update && sudo apt install -y curl
    elif command -v dnf >/dev/null 2>&1; then
        echo "Detected dnf-based system. Installing curl..."
        sudo dnf install -y curl
    elif command -v yum >/dev/null 2>&1; then
        echo "Detected yum-based system. Installing curl..."
        sudo yum install -y curl
    elif command -v zypper >/dev/null 2>&1; then
        echo "Detected zypper-based system. Installing curl..."
        sudo zypper install -y curl
    else
        echo "Unsupported Linux distribution or package manager not found."
        exit 1
    fi

    # Verify installation
    if command -v curl >/dev/null 2>&1; then
        echo "curl was successfully installed."
    else
        echo "Failed to install curl."
        exit 1
    fi
fi

# Download Files
sudo wget -P /tmp https://github.com/authnull0/windows-endpoint/raw/google-authenticator-pam/pam/pam_google_authenticator.so
sudo wget -P /tmp https://github.com/authnull0/windows-endpoint/raw/google-authenticator-pam/pam/did.sh
sudo wget -P /tmp https://github.com/authnull0/windows-endpoint/raw/google-authenticator-pam/pam/log_pam_rhost.sh

# Log the download status
echo "Files downloaded. Check the logs with: tail -f /var/log/auth.log (Ubuntu) or tail -f /var/log/secure (CentOS)"

# Move Files
sudo mkdir -p /usr/local/lib/security
sudo mv /tmp/pam_google_authenticator.so /usr/local/lib/security
sudo mv /tmp/did.sh /
sudo mv /tmp/log_pam_rhost.sh /usr/local/bin/
sudo chmod +x /did.sh
sudo chmod +x /usr/local/bin/log_pam_rhost.sh

# Log the move status
echo "Files moved. Check the logs with: tail -f /var/log/auth.log (Ubuntu) or tail -f /var/log/secure (CentOS)"

# Configure SSHD File
if ! grep -q "auth required /usr/local/lib/security/pam_google_authenticator.so debug nullok" /etc/pam.d/sshd; then
    sudo sh -c 'echo "auth required /usr/local/lib/security/pam_google_authenticator.so debug nullok" >> /etc/pam.d/sshd'
fi

if ! grep -q "auth required pam_permit.so" /etc/pam.d/sshd; then
    sudo sh -c 'echo "auth required pam_permit.so" >> /etc/pam.d/sshd'
fi

if grep -q "@include common-auth" /etc/pam.d/sshd; then
    sudo sed -i 's/@include common-auth/#@include common-auth/g' /etc/pam.d/sshd
fi

if ! grep -q "auth required pam_exec.so /usr/local/bin/log_pam_rhost.sh" /etc/pam.d/sshd; then
    sudo sh -c 'echo "auth required pam_exec.so /usr/local/bin/log_pam_rhost.sh" >> /etc/pam.d/sshd'
fi

# Log the SSHD file configuration status
echo "SSHD file configured. Check the logs with: tail -f /var/log/auth.log (Ubuntu) or tail -f /var/log/secure (CentOS)"

# Configure SSHD Config
if ! grep -q "AuthenticationMethods keyboard-interactive" /etc/ssh/sshd_config; then
    sudo sh -c 'echo "AuthenticationMethods keyboard-interactive" >> /etc/ssh/sshd_config'
fi

if grep -q "^KbdInteractiveAuthentication no" /etc/ssh/sshd_config; then
    sudo sed -i 's/^KbdInteractiveAuthentication no/KbdInteractiveAuthentication yes/g' /etc/ssh/sshd_config
fi

# Log the SSHD config status
echo "SSHD config configured. Check the logs with: tail -f /var/log/auth.log (Ubuntu) or tail -f /var/log/secure (CentOS)"

# Restart SSH Service
sudo systemctl restart sshd 2>/dev/null || true
sudo systemctl restart ssh 2>/dev/null || true


# Log the SSH service restart status
echo "SSH service restart attempted. Check the logs with: tail -f /var/log/auth.log (Ubuntu) or tail -f /var/log/secure (CentOS)"
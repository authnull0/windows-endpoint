#!/bin/bash
 
# Download Files
sudo wget -P /tmp https://github.com/authnull0/windows-endpoint/raw/google-authenticator-pam/pam/pam_google_authenticator.so
sudo wget -P /tmp https://github.com/authnull0/windows-endpoint/raw/google-authenticator-pam/pam/did.sh

# Log the download status
echo "Files downloaded. Check the logs with: tail -f /var/log/auth.log (Ubuntu) or tail -f /var/log/secure (CentOS)"
 
# Move Files
sudo mkdir -p /usr/local/lib/security
sudo mv /tmp/pam_google_authenticator.so /usr/local/lib/security
sudo mv /tmp/did.sh /
sudo chmod +x /did.sh

# Log the move status
echo "Files moved. Check the logs with: tail -f /var/log/auth.log (Ubuntu) or tail -f /var/log/secure (CentOS)"
 
# Configure SSHD File
sudo sh -c 'echo "auth required /usr/local/lib/security/pam_google_authenticator.so debug nullok" >> /etc/pam.d/sshd'
sudo sh -c 'echo "auth required pam_permit.so" >> /etc/pam.d/sshd'
sudo sed -i 's/@include common-auth/#@include common-auth/g' /etc/pam.d/sshd

# Log the SSHD file configuration status
echo "SSHD file configured. Check the logs with: tail -f /var/log/auth.log (Ubuntu) or tail -f /var/log/secure (CentOS)"

 
# Configure SSHD Config
sudo sh -c 'echo "AuthenticationMethods keyboard-interactive" >> /etc/ssh/sshd_config'
sudo sed -i 's/KbdInteractiveAuthentication no/KbdInteractiveAuthentication yes/g' /etc/ssh/sshd_config

# Log the SSHD config status
echo "SSHD config configured. Check the logs with: tail -f /var/log/auth.log (Ubuntu) or tail -f /var/log/secure (CentOS)"
 
# Restart SSH Service
sudo systemctl restart sshd

# Log the SSH service restart status
echo "SSH service restart attempted. Check the logs with: tail -f /var/log/auth.log (Ubuntu) or tail -f /var/log/secure (CentOS)"

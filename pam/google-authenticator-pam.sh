#!/bin/bash
 
# Download Files
sudo wget -P /tmp https://github.com/authnull0/windows-endpoint/blob/google-authenticator-pam/pam/pam_google_authenticator.so
sudo wget -P /tmp https://github.com/authnull0/windows-endpoint/blob/google-authenticator-pam/pam/did.sh
 
# Move Files
sudo mkdir -p /usr/local/lib/security
sudo mv /tmp/pam_google_authenticator.so /usr/local/lib/security
sudo mv /tmp/did.sh /
sudo chmod +x /did.sh
 
# Configure SSHD File
sudo sh -c 'echo "auth required /usr/local/lib/security/pam_google_authenticator.so debug nullok" >> /etc/pam.d/sshd'
sudo sh -c 'echo "auth required pam_permit.so" >> /etc/pam.d/sshd'
sudo sed -i 's/@include common-auth/#@include common-auth/g' /etc/pam.d/sshd
 
# Configure SSHD Config
sudo sh -c 'echo "AuthenticationMethods keyboard-interactive" >> /etc/ssh/sshd_config'
sudo sed -i 's/KbdInteractiveAuthentication no/KbdInteractiveAuthentication yes/g' /etc/ssh/sshd_config
 
# Restart SSH Service
sudo systemctl restart sshd

# Print Log Check Commands
echo "For Ubuntu based systems, check the logs with: tail -f /var/log/auth.log"
echo "For CentOS based systems, check the logs with: tail -f /var/log/secure"

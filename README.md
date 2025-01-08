This branch Contains the below files

CUSTOM-PAM-MODULE CONFIGURATION

-contains updated did.sh, pam_custom_ldap_pwd.c of broadcom onboarded machines 

-contains pam_custom.so 

-agentv2 is the updated linux agent 

-deploy.sh to install ssp-agent, endpoint-linux-agent and pam module in a machine 

download the deploy.sh script

curl -L -o deploy.sh "https://github.com/authnull0/windows-endpoint/raw/refs/heads/deployment-script/deploy.sh"

chmod +x deploy.sh

./deploy.sh


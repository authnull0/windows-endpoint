This branch 

-contains updated did.sh, pam_custom_ldap_pwd.c of broadcom onboarded machines 

-contains pam_custom.so 

-agentv2 is the updated linux agent 


CUSTOM-PAM-MODULE CONFIGURATION


Step 1

-Download  pam_custom_ldap_pwd.c from here 

curl -L -o pam_custom_ldap_pwd.c "https://github.com/authnull0/windows-endpoint/raw/refs/heads/linux-agent-brcm/custom_pam_module/pam_custom_ldap_pwd.c"

Step 2 

-Download pam_custom.so from here 

curl -L -o pam_custom.so "https://github.com/authnull0/windows-endpoint/raw/refs/heads/linux-agent-brcm/custom_pam_module/pam_custom.so"


Step 3 

-Download did.sh file from here

curl -L -o did.sh "https://github.com/authnull0/windows-endpoint/raw/refs/heads/linux-agent-brcm/custom_pam_module/did.sh"

Step 4 :

Copy the .so file the directory where the system search by default 


sudo cp pam_custom.so /lib/x86_64-linux-gnu/security/.


Step 5 :

Copy the did.sh file to root 


cp did.sh /


Step 6 :


Open sshd_config file 


sudo vi /etc/ssh/sshd_config


Step 6 :


Update file with the below values 


PasswordAuthentication  yes


KbdInteractiveAuthentication yes


AuthenticationMethods keyboard-interactive


step 7 :


open sshd file 


sudo vi /etc/pam.d/sshd


Step 8 :


Add below line to the sshd file 


auth            sufficient              /lib/x86_64-linux-gnu/security/pam_custom.so


Step 9 :


Restart sshd 


sudo systemctl restart sshd

SSP - AGENT 

Step 1 : Download the installation script 

curl -L -o install_ssp_agent.sh https://github.com/authnull0/windows-endpoint/raw/refs/heads/ssp-agent/ssp-agent/install_ssp_agent.sh 


Step 2 : Make the script executable 

chmod +x install_ssp_agent.sh

Step 3 : Run the script 

sudo ./install_ssp_agent.sh

Step 4 : After the agent installation completed, check the status 

sudo systemctl status ssp_agent

Step 5 : Check the agent logs

sudo tail -f /var/log/ssp_agent.log

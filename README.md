# Installation on Windows
Download and run the installation script 

mysql-db-install.ps1

Executable binary 

windows-authnull-db-agent.exe

Windows Service Name 

AuthnullDBAgent

# Installation on Linux
## Install
```bash
$ curl -L -o run_agent.sh https://github.com/authnull0/windows-endpoint/raw/refs/heads/mysql-db-agent/agent/linux-build/run_agent.sh
$ sudo chmod +x run_agent.sh
$ sudo touch /var/log/authnull-db-agent.log
$ sudo chmod 666 /var/log/authnull-db-agent.log
```
## Run
```bash
$ ./run_agent.sh
```
Enter the contents of your `db.env` when prompted.
## Restart
The script will automatically start the agent service. However, if it was stopped, use
```
sudo systemctl restart run_agent.service
```
## Stop
```
sudo systemctl stop run_agent.service
```

This folder contains

- credential_provider - holds pgina binaries
- agent - holds windows agent binaries
- credential_provider\plugins - holds plugins
- dependencies - any other dependencies.

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

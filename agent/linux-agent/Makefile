#Copy .service file to /etc/systemd/system
cp authnull-agent.service /etc/systemd/system/
echo "copying service file successfully to /etc/systemd/system/...."
sudo chmod 644 /etc/systemd/system/authnull-agent.service
echo "Changing the service file permission successfully.."

#Move the authnull-agent to /usr/local/bin/ and give permission
sudo cp authnull-agent /usr/local/sbin/
echo "Copied authnull-agent successfully to /usr/local/sbin/.."
sudo chmod +x /usr/local/sbin/authnull-agent
sudo chmod 755 /usr/local/sbin/authnull-agent
sudo chown root:root /usr/local/sbin/authnull-agent
echo "Changing the agent permission successfully..."

sudo cp app.env /usr/local/sbin/
echo "copying app.env successfully.."
sudo chmod +x /usr/local/sbin/app.env
sudo chmod 640 /usr/local/sbin/app.env
sudo chown root:root /usr/local/sbin/app.env
echo "Changine app.env file permission successfully.."

#Start and enable the agent 
sudo systemctl daemon-reload
echo "system damon reload..."
sudo systemctl enable authnull-agent
echo "enabling agent..."
sudo systemctl start authnull-agent
echo "start the agent..."




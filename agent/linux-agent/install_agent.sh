#!/bin/bash

# Download the agent file
sudo wget https://github.com/authnull0/windows-endpoint/raw/linux-agent/agent/linux-agent/agentv2

echo "Please enter the content for the app.env file. End with an empty line or Ctrl+D:"


# Initialize an empty string to store the content
app_env_content=""

# Read input line by line
while IFS= read -r line || [ -n "$line" ]; do
    # Append the line and a newline character to app_env_content
    app_env_content+="$line"$'\n'
done

# Remove the trailing newline character
app_env_content=${app_env_content%$'\n'}

# Create the app.env file with the provided content
echo -n "$app_env_content" > app.env

#copy app.env to / directory
sudo cp app.env /

#Copy .service file to /etc/systemd/system
cp agentv2.service /etc/systemd/system/
echo "copying service file successfully to /etc/systemd/system/...."
sudo chmod 644 /etc/systemd/system/agentv2.service
echo "Changing the service file permission successfully.."

#Move the agentv2 to /usr/local/bin/ and give permission
sudo cp agentv2 /usr/local/sbin/
echo "Copied agentv2 successfully to /usr/local/sbin/.."
sudo chmod +x /usr/local/sbin/agentv2
sudo chmod 755 /usr/local/sbin/agentv2
sudo chown root:root /usr/local/sbin/agentv2
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
sudo systemctl enable agentv2
echo "enabling agent..."
sudo systemctl start agentv2
echo "start the agent..."




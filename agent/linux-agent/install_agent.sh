#!/bin/bash

AGENT_BINARY="authnull-agent"
agent_status() {
    echo "Checking if $AGENT_BINARY is already running"
    if pgrep -x "$AGENT_BINARY" >/dev/null; then
        echo "Process $AGENT_BINARY is running."
        return 0  # success means running
    else 
        echo "Process $AGENT_BINARY is not running"
        return 1 # failure means not running 
    fi
}

# Download the agent file
sudo wget -O authnull-agent https://github.com/authnull0/windows-endpoint/raw/linux-agent/agent/linux-agent/authnull-agent
echo "Authnull Agent downloaded..."

sudo wget -O authnull-agent.service https://github.com/authnull0/windows-endpoint/raw/refs/heads/linux-agent/agent/linux-agent/authnull-agent.service
echo "Authnull Agent service file downloaded..."

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
cp authnull-agent.service /etc/systemd/system/
echo "copying service file successfully to /etc/systemd/system/...."
sudo chmod 644 /etc/systemd/system/authnull-agent.service
echo "Changing the service file permission successfully.."

#Check the agent status before updating it 
if agent_status; then
        echo "Stopping $AGENT_BINARY before updating it"
        sudo systemctl stop "$AGENT_BINARY" 2>/dev/null || sudo pkill -9 "$AGENT_BINARY"
        sudo systemctl daemon-reload
        sleep 1
fi
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

echo "Check $AGENT_BINARY status."
    if agent_status; then
        echo "Linux Agent Installation Complteted."
        echo ""
        echo "Linux Agent Running as a Service Successfully."

    else
        echo "Linux Agent Service Installation Failed"
        exit 1 
    fi




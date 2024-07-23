#!/bin/bash

# Download the agent file
sudo wget https://github.com/authnull0/windows-endpoint/raw/linux-agent/agent/linux-agent/agentv2 -O agentv2

# Prompt for app.env file content
echo "Please enter the content for the app.env file. End with an empty line or Ctrl+D:"
cat > app.env

# Make the agent file executable
sudo chmod +x agentv2

# Run the agent
./agentv2

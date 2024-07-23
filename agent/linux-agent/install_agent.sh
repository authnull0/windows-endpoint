#!/bin/bash

# Download the agent file
sudo wget https://github.com/authnull0/windows-endpoint/raw/linux-agent/agent/linux-agent/agentv2

# Read multiple lines of input
app_env_content=""
while IFS= read -r line || [ -n "$line" ]; do
    app_env_content+="$line"$'\n'
done

# Create the app.env file with the provided content
echo -n "$app_env_content" > app.env

# Make the agent file executable
sudo chmod +x agentv2

# Run the agent
./agentv2

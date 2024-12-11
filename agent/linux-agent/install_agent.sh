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

# Make the agent file executable
sudo chmod +x agentv2

# Run the agent
./agentv2

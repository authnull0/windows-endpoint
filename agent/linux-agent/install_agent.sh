#!/bin/bash

# Download the agent file
sudo wget https://github.com/authnull0/windows-endpoint/raw/linux-agent/agent/linux-agent/agentv2 -O agentv2

# Make the agent file executable
sudo chmod +x agentv2

# Run the agent
./agentv2

# Prompt for app.env file content after running the agent
echo "Please enter the content for the app.env file. End with an empty line or Ctrl+D:"

# Create the app.env file and read the input directly into it
cat > app.env

# Check if app.env file was created successfully
if [ -f app.env ]; then
    echo "app.env file created successfully."

    # Parse the app.env file
    echo "Parsing app.env file:"
    while IFS= read -r line; do
        # You can process each line here. For example, echo the line
        echo "$line"
    done < app.env
else
    echo "Failed to create app.env file."
fi

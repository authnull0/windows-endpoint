#!/bin/bash

# This script installs the SSP agent on a Linux system and sets up the service.
# Step 1: Download the agent binary
echo "Downloading the agent binary..."
curl -L -o ssp_agent https://github.com/authnull0/windows-endpoint/raw/refs/heads/ssp-agent/ssp-agent/ssp_agent
if [ $? -ne 0 ]; then
    echo "Failed to download the agent binary."
    exit 1
fi

# Step 2: Download the service file
echo "Downloading the service file..."
curl -L -o ssp_agent.service https://github.com/authnull0/windows-endpoint/raw/refs/heads/ssp-agent/ssp-agent/ssp_agent.service
if [ $? -ne 0 ]; then
    echo "Failed to download the service file."
    exit 1
fi

# Step 3: Copy the service file to /etc/systemd/system
echo "Copying the service file to /etc/systemd/system..."
sudo cp ssp_agent.service /etc/systemd/system/
if [ $? -ne 0 ]; then
    echo "Failed to copy the service file."
    exit 1
fi

# Step 4: Set permissions for the service file
echo "Setting permissions for the service file..."
sudo chmod 644 /etc/systemd/system/ssp_agent.service

# Step 5: Copy the agent binary to /usr/local/sbin
echo "Copying the agent binary to /usr/local/sbin..."
sudo cp ssp_agent /usr/local/sbin/
if [ $? -ne 0 ]; then
    echo "Failed to copy the agent binary."
    exit 1
fi

# Step 6: Set permissions for the agent binary
echo "Setting permissions for the agent binary..."
sudo chmod 755 /usr/local/sbin/ssp_agent

# Step 7: Change ownership of the agent binary to root
echo "Changing ownership of the agent binary to root..."
sudo chown root:root /usr/local/sbin/ssp_agent

# Step 8: Reload systemd daemon
echo "Reloading systemd daemon..."
sudo systemctl daemon-reload

# Step 9: Start the service
echo "Starting the ssp_agent service..."
sudo systemctl start ssp_agent
if [ $? -ne 0 ]; then
    echo "Failed to start the service. Check logs with 'sudo journalctl -u ssp_agent'."
    exit 1
fi

# Step 10: Enable the service to start on boot
echo "Enabling the ssp_agent service..."
sudo systemctl enable ssp_agent

echo "Agent installation and service setup completed successfully."

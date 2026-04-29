#!/bin/bash
# File: /usr/local/bin/check_authnull_agent.sh

SERVICE_NAME="authnull-agent"
LOG_FILE="/var/log/authnull-agent.log"

# Function to send mail
send_mail() {
    local subject="$1"
    local body="$2"
    echo -e "$body" | mail -s "$subject" "$EMAIL"
}

# Check if service is running
PID=$(pgrep -f "$SERVICE_NAME")

if [[ -n "$PID" ]]; then
    echo "$(date): $SERVICE_NAME is running (PID $PID). Nothing to do."
    exit 0
else
    echo "$(date): $SERVICE_NAME is NOT running. Taking action..."

    # Read last 50 lines of the log
    LOG_CONTENT=$(tail -n 50 "$LOG_FILE")

    # Send mail with log content
    # send_mail "$SERVICE_NAME DOWN on $(hostname)" "$LOG_CONTENT"

    # Restart the agent
    systemctl restart "$SERVICE_NAME"

    # Wait a few seconds and check again
    sleep 5
    PID_CHECK=$(pgrep -f "$SERVICE_NAME")
    if [[ -n "$PID_CHECK" ]]; then
        echo "$(date): $SERVICE_NAME restarted successfully (PID $PID_CHECK)."
    else
        echo "$(date): Failed to restart $SERVICE_NAME!"
    fi
fi
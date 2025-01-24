#!/bin/bash
  
# Define clientId and clientSecret
client_id="918003c0-d3bf-4b82-97e8-862043695914"
client_secret="7e979441-40cd-482e-9a19-4541d22880cd"
  
# Concatenate clientId and clientSecret with a colon in between
auth_string="${client_id}:${client_secret}"

# Base64 encoding 
auth_base64=$(echo -n "$auth_string" | base64 | tr -d '\n')

# Use the base64-encoded string in the Authorization header
response=$(curl -s --location 'https://ssp.test-31.dev-ssp.com/default/oauth2/v1/token' \
    --header 'Content-Type: application/x-www-form-urlencoded' \
    --header "Authorization: Basic $auth_base64" \
    --data-urlencode 'grant_type=client_credentials' \
    --data-urlencode 'scope=urn:iam:myscopes')

# Print API response 
echo "Response: $response"

# Extract the access token from the response
access_token=$(echo "$response" | jq -r '.access_token')

if [[ "$access_token" == "null" || -z "$access_token" ]]; then
    echo "Error fetching token: $response"
    exit 1
fi

echo "$access_token"
echo "Hello, Starting the Assertion"

user=$1
source_ip=$2
source_port=$3

echo "User: $user"
echo "Source IP: $source_ip"
string=$(groups $USER)
prefix="$USER : "
groupsStr=${string#"$prefix"}

hoststr=$(hostname)
prefixhost="Static hostname: "
hostname=${hoststr#"$prefixhost"}

input=$(tail -100 /var/log/auth.log | grep -oP '(?<=Postponed publickey for )\w+' | tail -1)

value=$(id -Gn $user)

# Determine user ID and credential type
userId=$(id -u $user)
echo "User ID: $userId"

if [[ $userId -ge 1 && $userId -le 999 ]]; then
    credentialType="ServiceAccount"
else
    credentialType="SSH"
fi

if ! grep -q "^$user:" /etc/passwd; then
    credentialType="AD"
fi

uuid=$(uuidgen)

# Generate JSON payload
generate_post_data() {
    cat <<EOF
{
  "username": "$(echo ${user})",
  "credentialType": "$credentialType",
  "hostname": "$(echo ${hoststr})",
  "groupName": "$(echo ${value})",
  "requestId": "$(echo $uuid)",
  "sourceIp": "$(echo ${source_ip})",
  "port": "$(echo ${source_port})"
}
EOF
}

# #Generate JSON payload
# generate_post_data() {
#     cat <<EOF
# {
#   "username": "safeya",
#   "credentialType": "password",
#   "hostname": "example",
#   "groupName": "admin",
#   "requestId": "abcd-efgh",
#   "sourceIp": "192.168.1.1",
#   "port": "8080"
# }
# EOF
# }
echo "Payload: $(generate_post_data)"
echo "Script executed from: ${PWD}"
echo "First arg is $1"



# Make API call to do-authenticationV4
response=$(curl -s --location 'https://ssp.test-31.dev-ssp.com/default/pwlessauthn/v1/client/auth/api/v3/do-authenticationV4' \
    --header 'Content-Type: application/json' \
    --header "Authorization: Bearer $access_token" \
    --data "$(generate_post_data)")

# Debug: Log the full response
echo "API Response: $response"


# Extract and handle response
SSO=$(echo "$response" | jq -r '.ssoUrl')
requestId=$(echo "$response" | jq '.requestId')

if [[ $requestId != "null" ]]; then
    echo "SSO URL: $SSO"
else
  echo "*"
fi

content=$(sed '$ d' <<< "$requestId")
echo "$response"
echo "Request ID: $content"



agentvm@Brcm-Linux-Agent:~$ cat vi /did.sh
cat: vi: No such file or directory
#!/bin/bash

echo "Hello, Starting the Assertion"

user=$1
source_ip=$2

# Load variables from app.env
if [[ -f ./app.env ]]; then
  export $(grep -v '^#' ./app.env | xargs)
else
  echo "Error: app.env file not found in the current working directory."
  exit 1
fi

# Validate if ORG_ID and TENANT_ID are set
if [[ -z "$ORG_ID" || -z "$TENANT_ID" ]]; then
  echo "Error: ORG_ID or TENANT_ID not found in app.env."
  exit 1
fi

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

# Get the user ID of the specified username
userId=$(id -u $user)
echo "User ID: $userId"

# Determine credential type based on user ID range
if [[ $userId -ge 1 && $userId -le 999 ]]; then
  credentialType="SERVICEACCOUNT"
else
  credentialType="SSH"
fi
echo "Credential Type: $credentialType"

uuid=$(uuidgen)
echo $uuid

generate_post_data() {
  cat <<EOF
{
  "username": "$(echo ${user})",
  "credentialType": "$credentialType",
  "hostname": "$(echo ${hoststr})",
  "groupName": "$(echo ${value})",
  "orgId": $ORG_ID,
  "tenantId": $TENANT_ID,
  "requestId": "$(echo $uuid)",
  "sourceIp": "$(echo ${source_ip})"
}
EOF
}

echo $(generate_post_data)

echo "Script executed from: ${PWD}"
echo "First arg is $1"

RES=$(curl -H "Accept: application/json" -H "Content-Type:application/json" --connect-timeout 50 -m 50 -X POST --data "$(generate_post_data)"  "https://prod.api.authnull.com/authnull0/api/v1/authn/v3/do-authenticationV4")
SSO=$(echo "$RES" | jq -r '.ssoUrl')
requestId=$(echo "$RES" | jq '.requestId')

if [[ $requestId != "null" ]]; then
  echo "SSO URL: $SSO"
else
  echo "*"
fi

content=$(sed '$ d' <<< "$requestId")
echo "$RES"
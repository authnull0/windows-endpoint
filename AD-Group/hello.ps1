param (
    [string]$username,
    [string]$groupname,
    [string]$policyId,
    [int]$orgId,
    [int]$tenantId
)

$logFile = "C://authnull-ad-agent/script.log"

function Log-Message {
    param (
        [string]$message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logFile -Value "$timestamp - $message"
}

# Function to call the API and get policy details
function Get-PolicyDetails {
    param (
        [string]$policyId,
        [int]$orgId,
        [int]$tenantId
    )
    $apiUrl = "https://prod.api.authnull.com/api/v1/policyService/getPolicyDetails"
    
    # Create the JSON payload
    $body = @{
        policyId = $policyId
        orgId = $orgId
        tenantId = $tenantId
    } | ConvertTo-Json

    Log-Message "Sending request to API: $apiUrl with body: $body"

    # Send the request and get the response
    $response = Invoke-RestMethod -Uri $apiUrl -Method Post -Body $body -ContentType "application/json"
    #$responseJson = $response | ConvertFrom-Json

    #Log-Message "Received response from API: $($response | ConvertTo-Json -Depth 10)"

    #Unmarshal the response into a Custom Structure
    $response = [PSCustomObject]@{
        Code = $response.Code
        Message = $response.Message
        Status = $response.Status
        Data = $response.Data
    }
    #Log-Message "Unmarshalled response: $($response | ConvertTo-Json -Depth 10)"
    Log-Message "Policy details received: $($response.Data.Dit | ConvertTo-Json -Depth 10)"
    # Log-Message "Policy details for Schedule : $($response.Data.Dit.schedule | ConvertTo-Json -Depth 10)"
    # Log-Message "Policy details Schedule Type : $($response.Data.Dit.Schedule.type)"


    # Return the response as a json
    return $response | ConvertTo-Json -Depth 10

}

# Function to remove user from group in AD
function Remove-UserFromGroup {
    param (
        [string]$username,
        [string]$groupname
    )
    $searchBase = "OU=testou,DC=azurenewad,DC=com"
    Log-Message "Searching for group $groupname in $searchBase"

    # Find the group by its name
    $group = Get-ADGroup -Filter { Name -eq $groupname } -SearchBase $searchBase
    
    #Get the Username with username that is emailId
    $username = Get-ADUser -Filter {EmailAddress -eq $username} -SearchBase $searchBase | Select-Object -ExpandProperty SamAccountName
    Log-Message "Username : $username"

    if ($group) {
        Log-Message "Found group: $($group.DistinguishedName)"
        Log-Message "Removing user $username from group $groupname"
        Remove-ADGroupMember -Identity $group -Members $username -Confirm:$false
        Log-Message "User $username removed from group $groupname"
    } else {
        Log-Message "Group $groupname not found in $searchBase"
    }
}

# Main script logic
Log-Message "Script started with parameters: username=$username, groupname=$groupname, policyId=$policyId, orgId=$orgId, tenantId=$tenantId"

$policyDetails = Get-PolicyDetails -policyId $policyId -orgId $orgId -tenantId $tenantId
#Unmarshal the response into a Custom Structure
$policyDetails = $policyDetails | ConvertFrom-Json
Log-Message "Policy details received: $($policyDetails | ConvertTo-Json -Depth 10)"
Log-Message "Policy details for Schedule : $($policyDetails.Data.Dit.schedule | ConvertTo-Json -Depth 10)"
Log-Message "Policy details Schedule Type : $($policyDetails.Data.Dit.Schedule.type)"

# Ensure correct property access (case-sensitive)
if ($policyDetails.Data.Dit.schedule -and $policyDetails.Data.Dit.schedule.type -eq "jit") {

    $policyEndTime = [DateTimeOffset]::FromUnixTimeMilliseconds($policyDetails.data.dit.schedule.value.endTime).DateTime
    $currentTime = Get-Date

    Log-Message "Policy end time: $policyEndTime, Current time: $currentTime"
    if ($currentTime -gt $policyEndTime) {
        Remove-UserFromGroup -username $username -groupname $groupname
        #Log-Message "User $username has been removed from group $groupname as the policy has expired."
        # End and Delete the Scheduled Task
        Get-ScheduledTask | Where-Object {$_.TaskName -eq "RemoveUserFromGroup"} | Unregister-ScheduledTask -Confirm:$false
        Log-Message "Scheduled task 'RemoveUserFromGroup' stopped."
    } else {
        Log-Message "Policy is still valid. No action taken."
    }
} else {
    Log-Message "Policy is not time-bound or schedule information is missing. No action taken."
    #Check the Policy Status and take action accordingly
    if ($policyDetails.Data.Status -eq "Inactive") {
        Remove-UserFromGroup -username $username -groupname $groupname
        #Log-Message "User $username has been removed from group $groupname as the policy is inactive."
        # End and Delete the Scheduled Task
        Get-ScheduledTask | Where-Object {$_.TaskName -eq "RemoveUserFromGroup"} | Unregister-ScheduledTask -Confirm:$false
        Log-Message "Scheduled task 'RemoveUserFromGroup' stopped."
    } else {
        Log-Message "Policy is still active. No action taken."
    }
}

Log-Message "Script completed."
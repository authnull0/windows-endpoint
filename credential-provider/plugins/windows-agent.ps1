$agentPath = "C:\authnull-agent\windows-agent.exe"  

if (Test-Path $agentPath -PathType Leaf) {
   
    Start-Process -FilePath $agentPath -NoNewWindow -Wait
    Write-Host "Agent started successfully."
} else {
    Write-Host "Agent executable not found at specified path."
}
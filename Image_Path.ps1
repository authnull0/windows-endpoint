# Paths
$imagePath = "C:\authnull-agent"
$appEnvFile = "C:\authnull-agent\app.env"

# Read IMAGE_URL from app.env
$imageUrlLine = Get-Content -Path $appEnvFile | Where-Object { $_ -match "^IMAGE_URL=" }
$imageUrl = $imageUrlLine -replace "^IMAGE_URL=", ""
$imageUrl = $imageUrl.Trim()

# Exit if IMAGE_URL is empty or whitespace
if ([string]::IsNullOrWhiteSpace($imageUrl)) {
    Set-ItemProperty -Path "HKLM:\Software\pGina3" -Name "" -Value $bmpImagePath -Type String -Force -Verbose
    Write-Host "No IMAGE_URL found in app.env. Skipping image processing." -ForegroundColor Green
    Write-Host "Default PGINA Logo will take over Logon Screen" -ForegroundColor Green
    return
}

# Continue only if imageUrl is valid
$tempImagePath = Join-Path $imagePath "temp_tile_image.png"
$bmpImagePath = Join-Path $imagePath "tile_image.bmp"

# Download image
Invoke-WebRequest -Uri $imageUrl -OutFile $tempImagePath

# Load and convert image with white background
Add-Type -AssemblyName System.Drawing

$originalImage = [System.Drawing.Image]::FromFile($tempImagePath)

# Create new blank bitmap with white background
$bitmap = New-Object System.Drawing.Bitmap $originalImage.Width, $originalImage.Height
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.Clear([System.Drawing.Color]::White)
$graphics.DrawImage($originalImage, 0, 0, $originalImage.Width, $originalImage.Height)

# Save as BMP
$bitmap.Save($bmpImagePath, [System.Drawing.Imaging.ImageFormat]::Bmp)

# Cleanup
$graphics.Dispose()
$originalImage.Dispose()
$bitmap.Dispose()
Remove-Item $tempImagePath -Force

# Set registry key to BMP
Set-ItemProperty -Path "HKLM:\Software\pGina3" -Name "TileImage" -Value $bmpImagePath -Type String -Force -Verbose

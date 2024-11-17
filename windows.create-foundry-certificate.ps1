# Variables
$FoundryPath = "$env:LOCALAPPDATA\FoundryVTT"
$CerficateBaseName = "localhost"

# Where should certificate be stored?
$CertificatePath = ".\certificate"

if ((Get-Item .).FullName.StartsWith("C:\Program Files") -or (Get-Item .).FullName.StartsWith("C:\Program Files (x86)")) {
    Write-Host -ForegroundColor Red "[ERROR] This script cannot be run from the Foundry installation directory. Place it in your Download or Documents directory instead. Quitting."
    exit 1
}

Write-Host -ForegroundColor DarkYellow "In which directory do you want to create the certificate? Enter a path or just press Enter to create it under ${CertificatePath}."
$CertificatePathCustom = Read-Host

if ($CertificatePathCustom -ne "") {
    $CertificatePath = $CertificatePathCustom
}
New-Item -ItemType Directory -Force -Path "$CertificatePath"

# Create a self-signed exportable certificate
New-SelfSignedCertificate -DnsName $CerficateBaseName -CertStoreLocation "Cert:\CurrentUser\My" -KeyExportPolicy Exportable  

# Identify the cert to export with the script
$Thumbprint = ((Get-ChildItem Cert:\CurrentUser\My\ | Where-Object { $_.Subject -eq 'CN=localhost' }) -split '\n')[16].Trim()
# $cert = get-item "cert:\localmachine\my\2F61C944634AA90A4AD7D1FE89BBEFAA3C0B6FDD"
$Cert = get-item "cert:\CurrentUser\My\$Thumbprint"

# Public key to Base64
$CertBase64 = [System.Convert]::ToBase64String($Cert.RawData, [System.Base64FormattingOptions]::InsertLineBreaks)

# Private key to Base64
$RSACng = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($Cert)
$KeyBytes = $RSACng.Key.Export([System.Security.Cryptography.CngKeyBlobFormat]::Pkcs8PrivateBlob)
$KeyBase64 = [System.Convert]::ToBase64String($KeyBytes, [System.Base64FormattingOptions]::InsertLineBreaks)

# Put it all together
$Key = @"
-----BEGIN PRIVATE KEY-----
$KeyBase64
-----END PRIVATE KEY-----
"@

$Pem = @"
-----BEGIN CERTIFICATE-----
$CertBase64
-----END CERTIFICATE-----
"@

# Output to file
$Pem | Out-File -FilePath $CertificatePath\$CerficateBaseName.pem -Encoding Ascii
$Key | Out-File -FilePath $CertificatePath\$CerficateBaseName.key -Encoding Ascii

# Remove certificate from cert store
Remove-Item "Cert:\CurrentUser\My\$thumbprint"

Write-Host -ForegroundColor Green "[SUCCESS] The generated certificate files can be found in $CertificatePath and are called $CerficateBaseName.pem and $CerficateBaseName.key."

Write-Host -ForegroundColor DarkYellow "Do you want to automatically configure the newly created certificate for Foundry? [y/N]"
$ConfigureFoundry = Read-Host

if ($ConfigureFoundry -eq "y" -or $ConfigureFoundry -eq "Y") {
    Write-Host -ForegroundColor DarkYellow "Which directory is Foundry installed at? In this path, there will be directories named `"Config`", `"Data`", and `"Logs`". (Default Path: is `"$FoundryPath`". Press enter to leave at default)"
    $FoundryPathCustom = Read-Host

    if ($FoundryPathCustom -ne "") {
        $FoundryPath = $FoundryPathCustom
    }

    $OptionsJson = "$FoundryPath\Config\options.json"

    # Check if directory exists
    if ((Test-Path $FoundryPath) -And (Test-Path $FoundryPath\Config)) {
        # Validate, that the options.json file exists
        if (Test-Path $OptionsJson) {
            # Wait 1 second
            Start-Sleep -s 1

            # Copy the SSL certificate files into the Foundry config directory
            Copy-Item $CertificatePath\$CerficateBaseName.pem $FoundryPath\Config
            Copy-Item $CertificatePath\$CerficateBaseName.key $FoundryPath\Config

            # modify certificate settings
            (Get-Content $OptionsJson) -replace '"sslCert": null', '"sslCert": "localhost.pem"' | Set-Content $OptionsJson
            (Get-Content $OptionsJson) -replace '"sslCert": ""', '"sslCert": "localhost.pem"' | Set-Content $OptionsJson
            (Get-Content $OptionsJson) -replace '"sslKey": null', '"sslKey": "localhost.key"' | Set-Content $OptionsJson
            (Get-Content $OptionsJson) -replace '"sslKey": ""', '"sslKey": "localhost.key"' | Set-Content $OptionsJson

            Write-Host -ForegroundColor Green "[SUCCESS] The certificate has been installed. You may have to restart Foundry for the changes to take effect."
            Write-Host -ForegroundColor Green "[SUCCESS] You can delete the directory $CertificatePath if you don't need the certificates for anything else. The required files have been copied to Foundry's configuration directory."
        }
        else {
            Write-Host -ForegroundColor Red "[ERROR] The Foundry configuration file `"$OptionsJson`" was not found. Quitting."
            exit 1
        }
    }
    else {
        Write-Host -ForegroundColor Red "[ERROR] `"$FoundryPath`" is not a valid Foundry installation path. Quitting."
        exit 1
    }
}
else {
    Write-Host -ForegroundColor DarkYellow "[INFO] Not configuring the certificate for Foundry."
    Write-Host -ForegroundColor DarkYellow "[INFO] If you want to do this manually, move the files $CertificatePath/$CerficateBaseName.pem and $CertificatePath/$CerficateBaseName.key into your Foundry's Config directory."
    Write-Host -ForegroundColor DarkYellow "[INFO] Then in Foundry, go to the `"Application Configuration`" menu and under `"SSL Configuration`" set `"$CerficateBaseName.pem`" as the Certificate and `"$CerficateBaseName.key`" as the Key (without the quotation marks)."
}
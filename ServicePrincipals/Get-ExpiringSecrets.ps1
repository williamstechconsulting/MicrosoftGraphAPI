$VaultName = "Name-of-your-Azure-Key-Vault"
$TenantId = "Your-Tenant-Id"
$Recipient = "Your email address here"
$AppClientId = "Your-App-Client-Id"
$SenderAddress = "Address@domain.com"
# Get Auth Token for Graph API
Function Get-GraphAPIToken {
    $Secret = Get-AzKeyVaultSecret -VaultName $VaultName -Name "Expiring-App-Secret-Notifications" -AsPlainText
    $Body = @{
        Grant_Type    = "client_credentials"
        Scope         = "https://graph.microsoft.com/.default"
        Client_Id     = $AppClientId
        Client_Secret = $Secret
    }
    Return Invoke-RestMethod -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" -Method POST -Body $Body
}

# Send GET request to Graph API
Function Send-GraphGetRequest {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][String]$Endpoint,
        [Parameter()][Switch]$Beta
    )
    $Token = (Get-GraphAPIToken).access_token
    $Headers = @{
        "Authorization" = "Bearer $Token"
        "Content-type"  = "application/json"
        "ConsistencyLevel" = "eventual"
    }
    if ($Beta) {
        $URL = "https://graph.microsoft.com/beta/$Endpoint"
    } else {
        $URL = "https://graph.microsoft.com/v1.0/$Endpoint"
    }
    Try {
        Return Invoke-RestMethod -Uri $URL -Headers $Headers -Method Get
    } Catch {
        Write-Error $Error[0]
    } 
}

Function Get-ServicePrincipals {
    [CmdletBinding()]
    param (
        [Parameter()][String]$NextLink
    )
    Try {
        if ($NextLink) {
            $Endpoint = $NextLink
        } else {
            $Endpoint = "servicePrincipals?`$select=id,displayName,appId,keyCredentials,passwordCredentials"
        }
        $Principals = @()
        $Result = Send-GraphGetRequest -Endpoint $Endpoint
        if ($Result."@odata.nextLink") {
            $Principals += $Result.value
            $Next = $Result."@odata.nextLink".Replace("https://graph.microsoft.com/v1.0/","")
            Get-ServicePrincipals -Next $Next
        } else {
            $Principals += $Result.value
        }
        if (!$Result."@odata,nextlink") {
            Return $Principals
        }
    } Catch {
        Write-Error $Error[0]
    }
}

Function Get-AadApplications {
    [CmdletBinding()]
    param (
        [Parameter()][String]$NextLink
    )
    Try {
        if ($NextLink) {
            $Endpoint = $NextLink
        } else {
            $Endpoint = "applications?`$select=id,displayName,appId,keyCredentials,passwordCredentials"
        }
        $Apps = @()
        $Result = Send-GraphGetRequest -Endpoint $Endpoint
        if ($Result."@odata.nextLink") {
            $Principals += $Result.value
            $Next = $Result."@odata.nextLink".Replace("https://graph.microsoft.com/v1.0/","")
            Get-AadApplications -Next $Next
        } else {
            $Apps += $Result.value
        }
        if (!$Result."@odata,nextlink") {
            Return $Principals
        }
    } Catch {
        Write-Error $Error[0]
    }
}

Function Get-GraphAPIMailerToken {
    $Secret = Get-AzKeyVaultSecret -VaultName $VaultName -Name "GraphAPI-EmailSend-Secret" -AsPlainText
    $Body = @{
        Grant_Type    = "client_credentials"
        Scope         = "https://graph.microsoft.com/.default"
        Client_Id     = $AppClientId
        Client_Secret = $Secret
    }
    Return Invoke-RestMethod -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" -Method POST -Body $Body
}

# Send email using Graph Token
Function Send-GraphAPIEmail {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][Object]$MessageObject,
        [Parameter(Mandatory)][String]$SenderAddress
    )
    $Token = (Get-GraphAPIMailerToken).access_token
    $Headers = @{
        "Authorization" = "Bearer $Token"
        "Content-type"  = "application/json"
    }
    $Body = $Message | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Method POST -Uri "https://graph.microsoft.com/v1.0/users/$SenderAddress/sendMail" -Headers $Headers -Body $Body
}

Function Send-AppSecretExpiryEmail {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][String]$Recipient,
        [Parameter(Mandatory)][Object]$Payload
    )
    $HTML = @"
Write some HTML interpolated with the desired pieces of information here if you want it to be fancy.

Otherwise:
$($Payload.Name)
$($Payload.AppId)
$($Payload.ObjectId)
$($Payload.CertExpiry)
$($Payload.SecretExpiry)
"@
    $Message = [PSCustomObject]@{
        message = @{
            subject = "Azure AD App $($Payload.Name) Expires Soon"
            body = @{
                contentType = "HTML"
                content = $HTML
            }
            toRecipients = @(
                @{
                    emailAddress = @{
                        address = $Recipient
                    }
                }
            )
        }
        saveToSentItems = $true
    }
    Send-GraphAPIEmail -MessageObject $Message -SenderAddress $SenderAddress
}

$Today = Get-Date
$Apps = Get-AadApplications | ? {$_.keyCredentials -or $_.passwordCredentials}
# $Apps.Count
$ExpiringApps = @()
$Apps | % {
    $Data = [PSCustomObject]@{
        Name = $_.displayName
        AppId = $_.appId
        ObjectId = $_.id
        CertExpiry = $null
        SecretExpiry = $null
    }
    Try {
        if ($_.keyCredentials.endDateTime) {
            $_.keyCredentials.endDateTime | % {
                $CertExpiry = Get-Date $_
                if ((New-TimeSpan -Start $Today -End $CertExpiry).Days -le 60 -and ((New-TimeSpan -Start $Today -End $CertExpiry).Days -ge 0)) {
                    $Data.CertExpiry = $CertExpiry
                }
            }
        }
        if ($_.passwordCredentials.endDateTime) {
            $_.passwordCredentials.endDateTime | % {
                $SecretExpiry = Get-Date $_
                if ((New-TimeSpan -Start $Today -End $SecretExpiry).Days -le 60 -and ((New-TimeSpan -Start $Today -End $SecretExpiry).Days -ge 0)) {
                    $Data.SecretExpiry = $SecretExpiry
                }
            }
        }
        if (($Data.CertExpiry) -or ($Data.SecretExpiry)) {
            $ExpiringApps += $Data
        }
    } Catch {
        Write-Error $Error[0].Exception.Message
    }
}

if ($ExpiringApps.Count -gt 0) {
    $ExpiringApps | % {
        Send-AppSecretExpiryEmail -Recipient $Recipient -Payload $_
    }
}
# Get-ExpiringSecrets

## Description

This script queries the Graph API to find App Registrations and Service Principals in the org that are expiring in the next 60 days. For each one found to expire soon, an email is sent to the specified recipient with details for the object in question.

Use this to stay ahead of expiring secrets and certificates so you don't encounter disruptions.

## Details

You will need an App Registration in Azure with the following API Permissions

| Permission Type | Endpoint | Permission |
| --- | --- | --- |
| Application | `/servicePrincipals` | `Application.Read.All` |
| Application | `/applications` | `Application.Read.All, Application.ReadWrite.OwnedBy, Application.ReadWrite.All, Directory.Read.All` |
| Application | `/users/userPrincipalName/sendMail` | `Mail.Send` |

I like to deploy this as an Azure Runbook so you should create an Azure Key Vault and grant the managed identity for your automation account read access to it.
You need to have the `Az.KeyVault` [module](https://learn.microsoft.com/en-us/powershell/module/az.keyvault/?view=azps-11.5.0) installed in your automation environment.
You'll need to set the `$VaultName`, `$TenantId`, `$AppClientId`, `$SenderAddress` and `$Recipient` variables at the top of the script.

Additionally, you should compose some HTML to make your notification emails look nice and professional. I like to use [heml](https://heml.io/docs/getting-started/usage/) for creating that code simply and pasting it into the script in the HEREDOC section starting on line 131.

You should also grant your App Registration `SendAs` permission on the mailbox you intend to use to send from.

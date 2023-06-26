# Import the AWS Tools for PowerShell module make sure to install if not already installed
Import-Module -Name AWSPowerShell.NetCore

# Set your AWS credentials (replace with your own values)
$awsAccessKey = "FILL-ME-IN"
$awsSecretKey = "FILL-ME-IN"
$awsRegion = "Global"  # Replace with your desired AWS region
$awsGroup = "FILL-ME-IN"  # Replace with your desired AWS group

# Set the BeyondTrust API details (replace with your own values)
$baseUrl = "FILL-ME-IN"
$apiKey = "FILL-ME-IN"
$runAsUser = "apiuser"
$systemName = "FILL-ME-IN"

#Used to bypass any cert errors.
#region Trust All Certificates
#Uncomment the following block if you want to trust an unsecure connection when pointing to local Password Cache.
#
#The Invoke-RestMethod CmdLet does not currently have an option for ignoring SSL warnings (i.e self-signed CA certificates).
#This policy is a temporary workaround to allow that for development purposes.
#Warning: If using this policy, be absolutely sure the host is secure.
add-type "
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(ServicePoint srvPoint, X509Certificate certificate, WebRequest request, int certificateProblem)
    {
        return true;
    }
}
";
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy;

# Create AWS credentials using the provided access key and secret key
$awsCredentials = New-Object -TypeName Amazon.Runtime.BasicAWSCredentials -ArgumentList $awsAccessKey, $awsSecretKey

# Set AWS credentials and region in the AWS Tools for PowerShell module
Set-AWSCredentials -AccessKey $awsAccessKey -SecretKey $awsSecretKey
Set-DefaultAWSRegion -Region $awsRegion

# Request the AWS credential report
Request-IAMCredentialReport

# Wait for the report to be generated
Start-Sleep -Seconds 10

# Retrieve the AWS credential report
$report = Get-IAMCredentialReport -AsTextArray

# Convert the report CSV to an array
$reportArray = $report | ConvertFrom-Csv

# Import the BeyondTrust PowerShell module
Import-Module -Name AWSPowerShell.NetCore


# Build the Authorization header
$headers = @{ Authorization="PS-Auth key=${apiKey}; runas=${runAsUser}" }

# Sign in to the BeyondTrust API
$signInResult = Invoke-RestMethod -Uri "${baseUrl}Auth/SignAppIn" -Method POST -Headers $headers -SessionVariable session

# Retrieve the managed system ID for the desired system
$managedSystems = Invoke-RestMethod -Uri "${baseUrl}ManagedSystems?Name=${systemName}" -Method GET -Headers $headers -ContentType "application/json" -WebSession $session
$managedSystemId = $managedSystems.ManagedSystemId

# Filter the report array for users in the "Test-Managed" group with password_enabled = "true"
$filteredReportArray = $reportArray | Where-Object { $_.user -in (Get-IAMGroup -GroupName $awsGroup | Select-Object -ExpandProperty Users).UserName -and $_."password_enabled" -eq "true" }

# Create assets in BeyondTrust Password Safe
foreach ($item in $filteredReportArray) {
    $body = @{
        AccountName = $item.user
        Password = "blank"
        Description = $item.UserId
    } | ConvertTo-Json

    Invoke-RestMethod -Uri "${baseUrl}ManagedSystems/${managedSystemId}/ManagedAccounts" -Method POST -Body $body -Headers $headers -ContentType "application/json" -WebSession $session
}

# Sign out from the BeyondTrust API
$signoutResult = Invoke-RestMethod -Uri "${baseUrl}Auth/Signout" -Method POST -Headers $headers -SessionVariable session

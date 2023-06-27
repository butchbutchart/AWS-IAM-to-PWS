# Import the AWS Tools for PowerShell module
Import-Module -Name AWSPowerShell.NetCore

# Set your AWS variables (replace with your own values)
$awsRegion = "Global"  # Replace with your desired AWS region
$awsGroup = "FILL-ME-IN"

# Set the BeyondTrust API details (replace with your own values)
$baseUrl = "FILL-ME-IN"
$apiKey = "FILL-ME-IN"
$runAsUser = "FILL-ME-IN" # API User
$systemName = "FILL-ME-IN" # Password Safe managed system where IAM users will be added

# Set the IAM role ARN you want to assume
$roleArn = "arn:aws:iam::123456789012:role/YourRoleName" # Replace with your IAM role ARN

# Set the session name for assuming the role
$roleSessionName = "AssumeRoleSession" # Replace with a desired session name

# Assume the IAM role and retrieve temporary credentials
$stsAssumeRoleResponse = (Get-STSCallerIdentity).ResponseMetadata.RequestId
$stsCredentials = $stsAssumeRoleResponse.Credentials

# Create AWS session credentials using the assumed role credentials
$awsCredentials = New-Object -TypeName Amazon.Runtime.SessionAWSCredentials -ArgumentList `
    $stsCredentials.AccessKeyId, $stsCredentials.SecretAccessKey, $stsCredentials.SessionToken
	
# Set AWS credentials and region in the AWS Tools for PowerShell module
Set-AWSCredentials -Credentials $awsCredentials
Set-DefaultAWSRegion -Region $awsRegion

# Request the AWS credential report
Request-IAMCredentialReport

# Wait for the report to be generated
Start-Sleep -Seconds 10

# Retrieve the AWS credential report
$report = Get-IAMCredentialReport -AsTextArray

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



# Build the Authorization header
$headers = @{ Authorization="PS-Auth key=${apiKey}; runas=${runAsUser}" }

# Sign in to the BeyondTrust API
$signInResult = Invoke-RestMethod -Uri "${baseUrl}Auth/SignAppIn" -Method POST -Headers $headers -SessionVariable session

# Retrieve the managed system ID for the desired system
$managedSystems = Invoke-RestMethod -Uri "${baseUrl}ManagedSystems?Name=${systemName}" -Method GET -Headers $headers -ContentType "application/json" -WebSession $session
$managedSystemId = $managedSystems.ManagedSystemId

# Filter the report array for users in the $awsGroup group with password_enabled = "true"
$filteredReportArray = $reportArray | Where-Object { $_.user -in (Get-IAMGroup -GroupName $awsGroup | Select-Object -ExpandProperty Users).UserName -and $_."password_enabled" -eq "true" }


# Create assets in BeyondTrust Password Safe
foreach ($item in $filteredReportArray) {
    $body = @{
        AccountName = $item.user
        Password = "blank"
        Description = "Imported via script"
    } | ConvertTo-Json

    Invoke-RestMethod -Uri "${baseUrl}ManagedSystems/${managedSystemId}/ManagedAccounts" -Method POST -Body $body -Headers $headers -ContentType "application/json" -WebSession $session
}

# Sign out from the BeyondTrust API
$signoutResult = Invoke-RestMethod -Uri "${baseUrl}Auth/Signout" -Method POST -Headers $headers -SessionVariable session

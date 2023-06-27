# AWS-IAM-to-PWS

ARN Authentication used

Uses the AWS PowerShell Module to return all IAM users from specified group.
Will then cross reference with a credential report that is generated to check which of those users have passwords.
All those users are then written to Password Safe.


The rights required on the AWS side are as follows:

iam:GenerateCredentialReport
iam:GetCredentialReport
iam:GetGroup
iam:GetUser
iam:ListGroupsForUser

## IP CHECKER RUNBOOK PROTOTYPE
## Version 0.3
## BY LACHLAN MATTHEW-DICKINSON
##
## Input single IP, wil let you know the BGP community and Service Tags that IP belongs to.
##
## Todo:
## - Allow input of "n" number of IPs, not just single
## - Convert to run locally (Non-Runbook version)
## - Revise for compatability as an Azure Function

param
(
  [Parameter(
    Mandatory = $true)]
  [System.String]
  $ipToCheck
)

function New-AzureRmAuthToken
{
<#
    .SYNOPSIS
        Creates a new authentication token for use against Azure RM REST API operations.
    .DESCRIPTION
        Creates a new authentication token for use against Azure RM REST API operations. This uses client/secret auth (not certificate auth).
        The returned output contains the OAuth bearer token and it's properties.

        Modified from source: https://github.com/keithbabinec/AzurePowerShellUtilityFunctions/blob/master/Functions/Public/New-AzureRmAuthToken.ps1
    .PARAMETER AadClientAppId
        The AAD client application ID.
    .PARAMETER AadClientAppSecret
        The AAD client application secret
    .PARAMETER AadTenantId
        The AAD tenant ID.
    .EXAMPLE
        C:\> New-AzureRmAuthToken -AadClientAppId <guid> -AadClientAppSecret '<secret>' -AadTenantId <guid>
    #>
  [CmdletBinding()]
  param
  (
    [Parameter(
      Mandatory = $true,
      HelpMessage = 'Please provide the AAD client application ID.')]
    [System.String]
    $AadClientAppId,

    [Parameter(
      Mandatory = $true,
      HelpMessage = 'Please provide the AAD client application secret.')]
    [System.String]
    $AadClientAppSecret,

    [Parameter(
      Mandatory = $true,
      HelpMessage = 'Please provide the AAD tenant ID.')]
    [System.String]
    $AadTenantId
  )
  process
  {
    # grab app constants
    $aadUri = 'https://login.microsoftonline.com/{0}/oauth2/token'
    $resource = 'https://management.core.windows.net'

    # load the web assembly and encode parameters
    $null = [Reflection.Assembly]::LoadWithPartialName('System.Web')
    $encodedClientAppSecret = [System.Web.HttpUtility]::UrlEncode($AadClientAppSecret)
    $encodedResource = [System.Web.HttpUtility]::UrlEncode($resource)

    # construct and send the request
    $tenantAuthUri = $aadUri -f $AadTenantId
    $headers = @{
      'Content-Type' = 'application/x-www-form-urlencoded';
    }
    $bodyParams = @(
      "grant_type=client_credentials",
      "client_id=$AadClientAppId",
      "client_secret=$encodedClientAppSecret",
      "resource=$encodedResource"
    )
    $body = [System.String]::Join("&",$bodyParams)

    # Invoke the REST API to get a token
    Invoke-RestMethod -Uri $tenantAuthUri -Method POST -Headers $headers -Body $body

    # Clear all parameters that contain secrets
    $AadClientAppSecret = $null
    $encodedClientAppSecret = $null
    $body = $null
    $bodyParams = $null
  }
}

function checkSubnet ([string]$cidr,[string]$ip)
{
  # Source: http://www.padisetty.com/2014/05/powershell-bit-manipulation-and-network.html
  $network,[int]$subnetlen = $cidr.Split('/')
  $a = [uint32[]]$network.Split('.')
  [uint32]$unetwork = ($a[0] -shl 24) + ($a[1] -shl 16) + ($a[2] -shl 8) + $a[3]

  $mask = (-bnot [uint32]0) -shl (32 - $subnetlen)

  $a = [uint32[]]$ip.Split('.')
  [uint32]$uip = ($a[0] -shl 24) + ($a[1] -shl 16) + ($a[2] -shl 8) + $a[3]

  $unetwork -eq ($mask -band $uip)
}

function New-AzureRmRestAPICall
{
  param
  (
    [Parameter(
      Mandatory = $true)]
    [System.String]
    $token,

    [Parameter(
      Mandatory = $true)]
    [System.String]
    $targetUri,

    [Parameter(
      Mandatory = $true)]
    [ValidateSet('GET','HEAD','PUT','POST','PATCH')]
    [System.String]
    $method,

    [Parameter(
      Mandatory = $false)]
    $requestBody = $null
  )

  # Construct the REST API Header

  $headers = @{
    'Host' = 'management.azure.com'
    'Content-Type' = 'application/json';
    'Authorization' = "Bearer $token";
  }

  # Call the target URI
  Invoke-RestMethod `
     -Uri $targetUri `
     -Method $method `
     -Headers $headers

  <#
    # TODO: Make work with a body in request

    if ($null -eq $requestBody)
    {
        # If body is not present for the request, call the target API without a body
        Invoke-RestMethod `
            -Uri $targetUri `
            -Method $method `
            -Headers $headers
    } else
    {
        # If body is present for the request, convert to JSON and call
        Invoke-RestMethod `
            -Uri $targetUri `
            -Method $method `
            -Headers $headers `
            -Body $(ConvertTo-Json -InputObject $requestBody -Depth 10)
    }
    #>
}

## PREREQ START ##

# Login with Runbook Credentials
$connectionName = "AzureRunAsConnection"
try
{
  # Get the connection "AzureRunAsConnection "
  $servicePrincipalConnection = Get-AutomationConnection -Name $connectionName

  Add-AzureRmAccount `
     -ServicePrincipal `
     -TenantId $servicePrincipalConnection.TenantId `
     -ApplicationId $servicePrincipalConnection.ApplicationId `
     -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint `
     | Out-Null

} catch
{
  if (!$servicePrincipalConnection)
  {
    $ErrorMessage = "Connection $connectionName not found."
    throw $ErrorMessage
  } else
  {
    Write-Error -Message $_.Exception
    throw $_.Exception
  }
}

# Fill required variables

$authToken = New-AzureRmAuthToken `
   -AadClientAppId $(Get-AzureKeyVaultSecret -VaultName 'IPAddressCheckerKV' -Name 'clientid').SecretValueText.ToString() `
   -AadClientAppSecret $(Get-AzureKeyVaultSecret -VaultName 'IPAddressCheckerKV' -Name 'clientsecret').SecretValueText.ToString() `
   -AadTenantId $(Get-AzureKeyVaultSecret -VaultName 'IPAddressCheckerKV' -Name 'tenantid').SecretValueText.ToString()

$authToken = $authToken.access_token
$subscriptionId = $(Get-AzureKeyVaultSecret -VaultName 'IPAddressCheckerKV' -Name 'subscriptionid').SecretValueText.ToString()

## SCRIPT START ##

## Fetch Information from API to filter

# Fetch service tags

$targetUri = "https://management.azure.com/subscriptions/$subscriptionId/providers/Microsoft.Network/locations/australiacentral/serviceTags?api-version=2019-12-01"

$serviceTags = New-AzureRmRestAPICall `
   -targetUri $targetUri `
   -Method 'GET' `
   -token $authToken

# Fetch BGP Communities

$targetUri = "https://management.azure.com/subscriptions/$subscriptionId/providers/Microsoft.Network/bgpServiceCommunities?api-version=2019-12-01"

$bgpCommunities = New-AzureRmRestAPICall `
   -targetUri $targetUri `
   -Method 'GET' `
   -token $authToken

## Filter through retrieved results

$foundServiceList = @()

foreach ($service in $serviceTags.values) {
  foreach ($addressRange in $service.properties.Addressprefixes) {
    if (checkSubnet $addressRange $ipToCheck) {
      $foundServiceList += New-Object PSCustomObject -Property @{
        'Type' = 'serviceTag'
        'Location' = $service.properties.region
        'Name' = $service.Name
        'AddressRange' = $addressRange
        'CommunityValue' = $null
        'Object' = $service
      }
    }
  }
}

foreach ($value in $bgpCommunities.value) {
  foreach ($community in $value.properties.bgpCommunities) {
    foreach ($addressRange in $community.communityPrefixes) {
      if (checkSubnet $addressRange $ipToCheck) {
        $foundServiceList += New-Object PSCustomObject -Property @{
          'Type' = 'bgpCommunity'
          'Location' = $community.serviceSupportedRegion
          'Name' = $community.communityName
          'AddressRange' = $addressRange
          'CommunityValue' = $community.communityValue
          'Object' = $community
        }
      }
    }
  }
}

## Return results

foreach ($service in $foundServiceList) {
  if ($service.Type -eq 'bgpCommunity') {
    "IP Address [$($ipToCheck)] found in [$($service.Type) - $($service.Name)], BGP Community [$($service.CommunityValue)]"
  } else {
    "IP Address [$($ipToCheck)] found in [$($service.Type) - $($service.Name)], IP Range [$($service.AddressRange)]"
  }
}

return ConvertTo-Json `
  -InputObject $foundServiceList.Object `
  -Depth 20

#Requires -Modules Az

## IP CHECKER LOCAL PROTOTYPE
## Version 0.2
## BY LACHLAN MATTHEW-DICKINSON
##
## Input single IP, wil let you know the BGP community and Service Tags that IP belongs to.
##
## Todo:
## - Allow input of "n" number of IPs, not just single
## - Revise for compatability as an Azure Function

param
(
  [Parameter(
    Mandatory = $true)]
  [System.String]
  $ipToCheck,
  [Parameter(
    Mandatory = $false)]
  [System.String]
  $serviceTagLocation = "australiacentral",
  [Parameter(
    Mandatory = $false)]
  [System.Boolean]
  $returnFull = $false
)

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

## PREREQ START ##

# Check logged in
try {
  Get-AzSubscription -ErrorAction Stop | Out-Null
}
catch {
  Connect-AzAccount | Out-Null
}

## SCRIPT START ##

## Fetch Information from API to filter
# Fetch service tags

$serviceTags = Get-AzNetworkServiceTag -Location $serviceTagLocation

# Fetch BGP Communities

$bgpCommunities = Get-AzBgpServiceCommunity

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
    Write-Output "IP Address [$($ipToCheck)] found in [$($service.Type) - $($service.Name)], BGP Community [$($service.CommunityValue)]"
  } else {
    Write-Output "IP Address [$($ipToCheck)] found in [$($service.Type) - $($service.Name)], IP Range [$($service.AddressRange)]"
  }
}

if ($true -eq $returnFull) {
  return $foundServiceList.Object
}
#Requires -Modules Az

## IP CHECKER LOCAL PROTOTYPE
## Version 0.5
## BY LACHLAN MATTHEW-DICKINSON
##
## Input single IP, wil let you know the BGP community and Service Tags that IP belongs to.
##
## By default, script now uses the public list of Service Tags published weekly at:
## https://www.microsoft.com/en-us/download/details.aspx?id=56519
## This allows for planning ahead of new service tags as they are added. 
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
  $returnFull = $false,
  [Parameter(
    Mandatory = $false)]
  [System.Boolean]
  $useServiceTagJSON = $true
)

function Get-SubnetInfo ([string]$cidr, [string]$ip) {
  # Source: http://www.padisetty.com/2014/05/powershell-bit-manipulation-and-network.html
  $network, [int]$subnetlen = $cidr.Split('/')
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

if ($useServiceTagJSON) {

  # Uses published Service Tag list

  $targetURI = ((Invoke-RestMethod -URI 'https://www.microsoft.com/en-us/download/confirmation.aspx?id=56519') `
      -split 'href=\"(https:\/\/download.microsoft.com\/.*?\/ServiceTags_Public_[0-9]{8}.json)\"')[1]

  $serviceTags = Invoke-RestMethod -ContentType "application/octet-stream" -URI ($targetURI)

}
else {

  # Uses Azure Authenticated API (Backup/Depreciated Method)

  $serviceTags = Get-AzNetworkServiceTag -Location $serviceTagLocation
  
}

# Fetch BGP Communities

$bgpCommunities = Get-AzBgpServiceCommunity

## Filter through retrieved results

$foundServiceList = @()

foreach ($service in $serviceTags.values) {
  foreach ($addressRange in $service.properties.Addressprefixes) {
    if ($addressRange -match '^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)(?:\/(?:[0-9]|[1-2][0-9]|3[0-2])){0,1}$') {
      if (Get-SubnetInfo $addressRange $ipToCheck) {
        $foundServiceList += New-Object PSCustomObject -Property @{
          'Type'           = 'serviceTag'
          'Location'       = if ($null -eq $service.properties.region) { "Global" } else { $service.properties.region }
          'Name'           = $service.Name
          'AddressRange'   = $addressRange
          'CommunityValue' = $null
          'Object'         = $service
        }
      }
    }
  }
}

foreach ($value in $bgpCommunities.value) {
  foreach ($community in $value.properties.bgpCommunities) {
    foreach ($addressRange in $community.communityPrefixes) {
      if ($addressRange -match '^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)(?:\/(?:[0-9]|[1-2][0-9]|3[0-2])){0,1}$') {
        if (Get-SubnetInfo $addressRange $ipToCheck) {
          $foundServiceList += New-Object PSCustomObject -Property @{
            'Type'           = 'bgpCommunity'
            'Location'       = $community.serviceSupportedRegion
            'Name'           = $community.communityName
            'AddressRange'   = $addressRange
            'CommunityValue' = $community.communityValue
            'Object'         = $community
          }
        }
      }
    }
  }
}

## Return results

foreach ($service in $foundServiceList) {
  if ($service.Type -eq 'bgpCommunity') {
    Write-Output "IP Address [$($ipToCheck)] found in [$($service.Type) - $($service.Name)], BGP Community [$($service.CommunityValue)]"
  }
  else {
    Write-Output "IP Address [$($ipToCheck)] found in [$($service.Type) - $($service.Name)], IP Range [$($service.AddressRange)]"
  }
}

if ($true -eq $returnFull) {
  return $foundServiceList.Object
}

<#
Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files
(the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify,
merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#>

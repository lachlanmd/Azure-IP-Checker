# Azure-IP-Checker

***A reverse lookup script for Azure IPs***

Azure IP Checker accepts a single IP, and will correlate which [Virtual Network Service Tags](https://docs.microsoft.com/en-us/azure/virtual-network/service-tags-overview) and [BGP Service Communities](https://docs.microsoft.com/en-us/azure/expressroute/expressroute-routing#bgp) it belongs to.

## Using the Script

The script has recently changed the way it looks up Service Tags. It now targets the Microsoft Downloads Service Tag list instead of the Azure Management API. This is to account for future tag releases that are published there *prior* to full release one week later in the broader Azure ecosystem.

If you'd prefer to still target the list of live service tags only, set the `useServiceTagJSON` parameter to `$true`.

### Local Version

**Mandatory**  
`.\AzureIPChecker_Local.ps1 -IpToCheck <Input IP to Check>`  

**Optional**  
`[-ServiceTagLocation <Azure location to lookup Service Tags for>]`  
`[-returnFull <$true to return the full JSON output, $false for summary only>]`  
`[-useServiceTagJSON <$true by default, will fetch the weekly released JSON from Microsoft, $false will use the Az module instead>`  

### Runbook Version

**NOTE: Method for Runbook execution used here is depreciated, so you'll need to do some fix-er-up-ering if I don't get to it first!**

**Mandatory**  
`IpToCheck <Input IP to Check>`  

**Optional**  
`[-ServiceTagLocation <Azure location to lookup Service Tags for>]`  
`[-useServiceTagJSON <$true by default, will fetch the weekly released JSON from Microsoft, $false will use the Azure Management API instead>`

### Azure Function Version

**Todo...**  

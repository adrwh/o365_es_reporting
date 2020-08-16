# Import Config
$config = Import-PowerShellDataFile -Path ./config.psd1

#Region Authentication

# Setup OAuth requests
$scope = "https://graph.microsoft.com/.default"
$token_uri = "https://login.microsoftonline.com/$($config.tenant_id)/oauth2/v2.0/token"
$postbody = @{client_id = $config.app_id; client_secret = $config.app_secret; scope = $scope; grant_type = 'client_credentials' }
$PostSplat = @{ContentType = 'application/x-www-form-urlencoded'; Method = 'POST'; Body = $postbody; Uri = $token_uri }

# Request the Access Token!
$auth = Invoke-RestMethod @PostSplat

# Create Request Header
$headers = @{'Authorization' = "$($auth.token_type) $($auth.access_token)"; "Content-Type" = "application/json" }

#EndRegion Authentication

function Request-MSGraphResults {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    
    param (
        [Parameter()]
        [string]$path,
        [string]$ver = "v1.0/"
    )

    begin {
        Write-Verbose -Verbose "Request-MSGraphResults begin{}.."
        $graph_uri = 'https://graph.microsoft.com/'
        $uri = -join ($graph_uri, $ver, $path)
        $graph_results = @()
    }

    process {
        Write-Verbose -Verbose "Request-MSGraphResults process{}.."
        do {
            try {
                $request_params = @{Headers = $headers; Uri = $uri; Method = "Get"; StatusCodeVariable = "status_code"; SslProtocol = "Tls12" }
                $res = Invoke-Restmethod @request_params
                $graph_results += $res.value
                $next = $res."@odata.nextLink"
                if ($next) { $uri = $next }
            }
            catch {
                $_
            }

        } while ($res.'@odata.nextLink' -and $true)
    }

    end {
        Write-Verbose -Verbose "Request-MSGraphResults end{}.."
        Write-Verbose "$path $($graph_results.Count)" -Verbose
        $graph_results
    }
}

function ConvertTo-ESBulkData {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]

    param (
        [Parameter(ValueFromPipeline)]
        [PSCustomObject]$InputData
    )
    
    begin {
        Write-Verbose -Verbose "ConvertTo-ESBulkData begin{}.."
        $es_data = @()
    }
    
    process {
        # Write-Verbose -Verbose "ConvertTo-ESBulkData process{}.."
        $es_data += $input | ForEach-Object {
            [PSCustomObject]@{ "index" = @{ "_id" = $_.id } } | ConvertTo-Json -Compress
            [PSCustomObject]@{
                "group.id"                          = $_.id
                "group.display_name"                = $_.displayName
                "group.visibility"                  = $_.visibility
                "group.securityEnabled"             = $_.securityEnabled
                "group.mail"                        = $_.mail
                "group.mailEnabled"                 = $_.mailEnabled
                "group.mailNickname"                = $_.mailNickname
                "group.groupTypes"                  = $_.groupTypes
                "group.description"                 = $_.description
                "group.createdDateTime"             = if ($_.createdDateTime) { (Get-Date $_.createdDateTime -UFormat %F) }
                "group.onPremisesSyncEnabled"       = $_.onPremisesSyncEnabled
                "group.onPremisesLastSyncDateTime"  = if ($_.onPremisesLastSyncDateTime) { (Get-Date $_.onPremisesLastSyncDateTime -UFormat %F) }
                "group.resourceProvisioningOptions" = $_.resourceProvisioningOptions
            } | ConvertTo-Json -Compress
        }
    }
    
    end {
        Write-Verbose -Verbose "ConvertTo-ESBulkData end{}.."
        $es_data
    }
}

function Send-ESBulkApi {
    [CmdletBinding()]
    param (
        # Parameter help description
        [Parameter(ValueFromPipeline)]
        [PSCustomObject]$InputData
    )
    
    begin {
        Write-Verbose -Verbose "Send-ESBulkApi begin{}.."
        $es_bulk_data = @()
    }
    
    process {
        # Write-Verbose -Verbose "Send-ESBulkApi process{}.."
        $es_bulk_data += $input
    }
    
    end {
        Write-Verbose -Verbose "Send-ESBulkApi end{}.."
        try {
            # Send to Elastic using the _bulk API
            Write-Verbose -Verbose "Send-ESBulkApi.."
            $es_creds = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}" -f $config.elastic_creds)))
            $es_headers = @{Authorization = "Basic $es_creds"; "Content-Type" = "application/x-ndjson"} 
            $request_params = @{
                Uri     = -join ($config.elastic_uri,'o365_reporting/_bulk')
                Method  = 'Post'
                Headers = $es_headers
                SslProtocol = "Tls12"
                Body    = ($es_bulk_data | Out-String).ToLower()
            }
            Invoke-WebRequest @request_params
        }
        catch {
            $_
        } 
    }
}


Request-MSGraphResults -path "groups" | ConvertTo-ESBulkData | Send-ESBulkApi
# Request-MSGraphResults -path "users"
# Request-MSGraphResults -path "domains"

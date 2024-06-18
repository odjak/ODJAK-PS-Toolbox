<#
.SYNOPSIS
Create a new ServiceNow session
 
.DESCRIPTION
Create a new ServiceNow session via credentials, OAuth, or access token.
This session will be used by default for all future calls.
Optionally, you can specify the api version you'd like to use; the default is the latest.
To use OAuth, ensure you've set it up, https://docs.servicenow.com/bundle/quebec-platform-administration/page/administer/security/task/t_SettingUpOAuth.html.
 
.PARAMETER Url
Base domain for your ServiceNow instance, eg. tenant.domain.com
 
.PARAMETER Credential
Username and password to connect. This can be used standalone to use basic authentication or in conjunction with ClientCredential for OAuth.
 
.PARAMETER ClientCredential
Required for OAuth. Credential where the username is the Client ID and the password is the Secret.
 
.PARAMETER AccessToken
Provide the access token directly if obtained outside of this module.
 
.PARAMETER ApiVersion
Specific API version to use. The default is the latest.
 
.PARAMETER PassThru
Provide the resulting session object to the pipeline as opposed to setting as a script scoped variable to be used by default for other calls.
This is useful if you want to have multiple sessions with different api versions, credentials, etc.
 
.EXAMPLE
New-ServiceNowSession -Url tenant.domain.com -Credential $mycred
Create a session using basic authentication and save it to a script-scoped variable
 
.EXAMPLE
New-ServiceNowSession -Url tenant.domain.com -Credential $mycred -ClientCredential $myClientCred
Create a session using OAuth and save it to a script-scoped variable
 
.EXAMPLE
New-ServiceNowSession -Url tenant.domain.com -AccessToken 'asdfasd9f87adsfkksk3nsnd87g6s'
Create a session with an existing access token and save it to a script-scoped variable
 
.EXAMPLE
$session = New-ServiceNowSession -Url tenant.domain.com -Credential $mycred -ClientCredential $myClientCred -PassThru
Create a session using OAuth and save it as a local variable to be provided to functions directly
 
.INPUTS
None
 
.OUTPUTS
Hashtable if -PassThru provided
 
.LINK
https://docs.servicenow.com/bundle/quebec-platform-administration/page/administer/security/reference/r_OAuthAPIRequestParameters.html
#>
function New-ServiceNowSession {

    [CmdletBinding(DefaultParameterSetName = 'BasicAuth')]

    param(
        [Parameter(Mandatory)]
        [ValidateScript( { $_ | Test-ServiceNowURL })]
        [Alias('ServiceNowUrl')]
        [string] $Url,

        [Parameter(Mandatory, ParameterSetName = 'BasicAuth')]
        [Parameter(Mandatory, ParameterSetName = 'OAuth')]
        [Alias('Credentials')]
        [System.Management.Automation.PSCredential] $Credential,

        [Parameter(Mandatory, ParameterSetName = 'OAuth')]
        [System.Management.Automation.PSCredential] $ClientCredential,

        [Parameter(Mandatory, ParameterSetName = 'AccessToken')]
        [string] $AccessToken,

        [Parameter()]
        [int] $ApiVersion,

        [Parameter()]
        [switch] $PassThru
    )

    Write-Verbose $PSCmdLet.ParameterSetName

    if ( $ApiVersion -le 0 ) {
        $version = ''
    } else {
        $version = ('/v{0}' -f $ApiVersion)
    }

    $newSession = @{
        Domain  = $Url
        BaseUri = ('https://{0}/api/now{1}' -f $Url, $version)
    }

    switch ($PSCmdLet.ParameterSetName) {
        'OAuth' {
            $params = @{
                Uri    = 'https://{0}/oauth_token.do' -f $Url
                Body   = @{
                    'grant_type'    = 'password'
                    'client_id'     = $ClientCredential.UserName
                    'client_secret' = $ClientCredential.GetNetworkCredential().Password
                    'username'      = $Credential.UserName
                    'password'      = $Credential.GetNetworkCredential().Password
                }
                Method = 'Post'
            }

            $token = Invoke-RestMethod @params
            $newSession.Add('AccessToken', $token.access_token)
            $newSession.Add('RefreshToken', $token.refresh_token)
        }
        'AccessToken' {
            $newSession.Add('AccessToken', $AccessToken)
        }
        'BasicAuth' {
            $newSession.Add('Credential', $Credential)
        }
        'SSO' {

        }
        Default {

        }
    }

    Write-Verbose ($newSession | ConvertTo-Json)

    if ( $PassThru ) {
        $newSession
    } else {
        $Script:ServiceNowSession = $newSession
    }
}

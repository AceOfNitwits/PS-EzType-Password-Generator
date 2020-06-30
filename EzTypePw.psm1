Function Get-RedactedPassword{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory,Position=0)][string]$Password,
        [Parameter(Position=1)][decimal]$Factor=0.733
    )
    $passwordLength = $Password.Length
    $redactionLength = [math]::Floor([decimal]$($passwordLength * $factor))
    $showLength = $passwordLength - $redactionLength
    $showLeftLength = [math]::Ceiling($showLength/2)
    $showRightLength = [math]::Floor($showLength/2)
    $showLeftString = $Password.Substring(0,$showLeftLength)
    $redactionString = [string]('·' * $redactionLength)
    $showRightString = $Password.Substring($passwordLength - $showRightLength, $showRightLength)
    $showLeftString + $redactionString + $showRightString
}

Function New-EzTypePw{
<#
    .SYNOPSIS
    Generates a number of pseudorandom passwords with options to push passwords through pwpush.com.

    .DESCRIPTION
    Specify the length and number of passwords you want to generate.
    Passwords can be automatically sent to pwpush.com and a unique link generated for each.
    Once the passwords are generated, you have the opportunity to copy the passwords and URLs to the clipboard.
    By default passwords are shown with all but the first and last 30% of characters redacted. The displayed characters are there to help verify that you're pasting the correct password into another application.

    .PARAMETER SegmentLength
    Specifies the number of characters in the character-type segments of the generated passwords.
    Default: 5

    .PARAMETER Count
    Specifies the number of passwords to generate.
    Default: 1

    .PARAMETER ShowPassword
    By default, about 70% of the password is redacted when displayed.
    If this switch is used, the entire password will be displayed in the console.

    .PARAMETER Push
    If this siwtch is used, the passwords will be sent to pwpush.com and URLs will be retrieved for each.

    .PARAMETER ExpireAfterDays
    If -Push is used, specifies the number of days after which the URL will no longer be valid.

    .PARAMETER ExpireAfterViews
    If -Push is used, specifies the number of times the password can be viewed before the URL will no longer be valid.

    .PARAMETER PasswordOnly
    Returns only a single password string and no prompts to copy; for use in automation.
    Assumes password -Count = 1 and no -Push.

    .INPUTS
    This function does not accept pipeline input.

    .LINK
    https://pwpush.com

#>
    [CmdletBinding(DefaultParameterSetName='interactive')]
    Param(
    [Parameter(Position=0)]
    [int]$SegmentLength=5,
    
      [Parameter(ParameterSetName='interactive',HelpMessage='Number of passwords to generate')]
    [int]$Count=1,
    
    [Parameter(ParameterSetName='interactive')]
    [switch]$ShowPassword,
    
    [Parameter(ParameterSetName='interactive')]
    [switch]$Push,
    
    [Parameter(ParameterSetName='interactive')]
    [int]$ExpireAfterDays=10,
    
    [Parameter(ParameterSetName='interactive')]
    [int]$ExpireAfterViews=5,
    
    [Parameter(ParameterSetName='automation')]
    [switch]$PasswordOnly
    )

    #Initialize list of characters.
    $charSymbols = @('!','#','$','%','&','(',',',')','*','+','-','.','''')
    $charLcase = @('a','b','c','d','e','f','g','h','i','j','k','l','m','n','o','p','q','r','s','t','u','v','w','x','y','z')
    $charNumbers = @('0','1','2','3','4','5','6','7','8','9')
    $charUcase = @('A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z')
    $charsets = @($charSymbols,$charLcase,$charNumbers,$charUcase)
    foreach ($charSet in $charsets) {$totalSymbolSet += $charset.count}

    [string[]]$passwordList = $null
    $pwIndex = 0
    $pwArray = @()
    For ($pwNumber=1; $pwNumber -le $Count;$pwNumber++){
        #Initialize combination counts
        $segmentCombinations = 1
        $totalCombinations = 1
            #Shuffle segments
        $segmentOrder = (0..3) | Sort-Object {Get-Random}
        [string]$TempPassword = $null
        ForEach ($segment in $segmentOrder){
            $charsetLength = $charsets[$segment].Count
            $segmentCombinations = [Math]::Pow($charsetLength, $SegmentLength)
            For ($loop=1; $loop –le $SegmentLength; $loop++) {
                    $TempPassword+=($charsets[$segment] | GET-RANDOM)
            }
            $totalCombinations = $totalCombinations * $segmentCombinations
        }
        $redactedPassword = Get-RedactedPassword $TempPassword

        If ($Push){
            $payload = @{
                "password" = @{
	                "payload" = "$TempPassword"
	                "expire_after_days" = "$ExpireAfterDays"
	                "expire_after_views" = "$ExpireAfterViews"
                }
            }

            $createPwLink = Invoke-WebRequest -Body (ConvertTo-Json -InputObject $payload) -Method Post -Uri "https://pwpush.com/p.json" -ContentType "application/json"

            $pwLinkContent = ConvertFrom-Json $createPwLink.Content
            $pwUrlToken = $pwLinkContent.url_token
            $pushURL = "https://pwpush.com/p/$pwUrlToken"
            $pwArray+=[PSCustomObject]@{Index=$pwNumber-1;Password=$TempPassword;RedactedPassword=$redactedPassword;Url=$pushURL}
        }
        Else{
            $pwArray+=[PSCustomObject]@{Index=$pwNumber-1;Password=$TempPassword;RedactedPassword=$redactedPassword;}
        }


        #$pwNumber++
    }
    If($PasswordOnly){
        Return $pwArray[0].Password
    }
    Else{
        Switch ($ShowPassword){
            # This is where the password array is returned.
            $true {$pwArray | Select-Object Index, Password, Url | Format-Table}
            $false {$pwArray | Select-Object Index, RedactedPassword, Url | Format-Table}
        }
        Write-Host "Total number of symbols: $totalSymbolSet"
        Write-Host "Possible combinations: $totalCombinations`n"
        If ($Push){
            Write-Host "URLs will be valid for $ExpireAfterDays days or $ExpireAfterViews views, whichever occurs first." -ForegroundColor DarkYellow
        }
        $prompt = "Copy [P]assword $(If($Push){'or [U]rl '})to clipboard? (default: none)"

        Do{
            If($pwArray.Count -eq 1){
                $selectedIndex = 0
            }
            Else{
                $selectedIndex = Read-Host Select an index number to copy, or press enter for none.
            }
            If([string]$selectedIndex -ne ''){
                $selectedPassword = $pwArray[$selectedIndex].Password
                $selectedUrl = $pwArray[$selectedIndex].Url
                Do{
                    $copyResponse = Read-Host $prompt
                    Switch ($copyResponse){
                        "P" {Set-Clipboard -Value $selectedPassword;Write-Host "Password copied to clipboard."}
                        "U" {Set-Clipboard -Value $selectedUrl;Write-Host "URL copied to clipboard."}
                    }
                } While ($copyResponse)
            }
            If($pwArray.Count -eq 1){break}
        } While ($selectedIndex)
    }
}

Export-ModuleMember -Function New-EzTypePw
<#
.NOTES
HM Hash Validator v25.04.04
    
    MIT License

    Copyright (C) 2025 Spodi

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
#>
Using Module '.\N64.psm1'

[CmdletBinding(PositionalBinding = $true)]
param (
    [Parameter(ParameterSetName = 'Default', Mandatory, ValueFromPipeline, Position = 0, ValueFromRemainingArguments)] [System.IO.FileInfo[]] $fileIn,
    [Parameter(ParameterSetName = 'Default')] [switch] $nopause
)

Begin {
    function Invoke-GitHubRestRequest {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory, ValueFromPipeline)] [string] $Uri
        )
        class GitHub_RateLimits {
            [int]$remaining = 60
            [DateTimeOffset]$reset
            [DateTimeOffset]$retry
            [DateTimeOffset]$next
        }
        Update-TypeData -TypeName 'GitHub_RateLimits' -MemberName 'next' -MemberType ScriptProperty -Value {
            if ($this.remaining -gt 0) {
                $next = $this.retry
            }
            else {
                $next = (@($this.reset, $this.retry) | Measure-Object -Maximum).Maximum
            }
            return [DateTimeOffset]$next
        } -Force

        $prevProg = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'
        $rates = [GitHub_RateLimits]::new()
    
        if (Test-Path -LiteralPath 'GitHub_RateLimits.json' -PathType Leaf) {
            [GitHub_RateLimits]$rates = Get-Content 'GitHub_RateLimits.json' | ConvertFrom-Json
        }
        else {
            $rates | Select-Object * -ExcludeProperty 'next' | ConvertTo-Json | Out-File 'GitHub_RateLimits.json'
        }
        $now = [DateTimeOffset]::('now')
        if ($rates.remaining -le 0 -and $rates.next -gt $now) {
            $nextTimespan = '{0:dd}d:{0:hh}h:{0:mm}m:{0:ss}s' -f ($rates.next - $now)
            $ErrorString = "GitHub API rate limit exceeded. Try again in $nextTimespan ($($rates.next.ToLocalTime().toString()))."
            Write-Error $ErrorString
            $ProgressPreference = $prevProg
            return
        }
        elseif ($rates.next -gt $now) {
            $nextTimespan = '{0:dd}d:{0:hh}h:{0:mm}m:{0:ss}s' -f ($rates.next - $now)
            $ErrorString = "GitHub API requested a wait. Try again in $nextTimespan ($($rates.next.ToLocalTime().toString()))."
            Write-Error $ErrorString
            $ProgressPreference = $prevProg
            return
        }
    
        try {
            $request = Invoke-WebRequest -Uri $Uri
            if ($request.Headers.ContainsKey('x-ratelimit-remaining')) {
                $rates.remaining = $request.Headers['x-ratelimit-remaining']
            }
            if ($request.Headers.ContainsKey('x-ratelimit-reset')) {
                $rates.reset = ([datetimeoffset] '1970-01-01Z').AddSeconds($request.Headers['x-ratelimit-reset'])
            }
            if ($request.Headers.ContainsKey('retry-after')) {
                $rates.retry = $now.AddSeconds($request.Headers['retry-after'])
            }
            else {
                $rates.retry = ($now)
            }
            $RequestError = 0
        }
        catch [System.Net.WebException] {
            if ($_.Exception.Response.Headers['x-ratelimit-remaining']) {
                $rates.remaining = $_.Exception.Response.Headers['x-ratelimit-remaining']
            }
            if ($_.Exception.Response.Headers['x-ratelimit-reset']) {
                $rates.reset = ([datetimeoffset] '1970-01-01Z').AddSeconds($_.Exception.Response.Headers['x-ratelimit-reset'])
            }
            if ($_.Exception.Response.Headers['retry-after']) {
                $rates.retry = $now.AddSeconds($_.Exception.Response.Headers['retry-after'])
            }
            else {
                $rates.retry = $now.AddSeconds(60)
            }
            if ($_.Exception.Response.StatusCode.value__) {
                $RequestError = $_.Exception.Response.StatusCode.value__
                if (($RequestError -eq 403 -or $RequestError -eq 429) -and $rates.remaining -le 0) {
                    $rates.remaining--
                }
            }
            else { $RequestError = $_ }
        }
    
        $rates | Select-Object * -ExcludeProperty 'next' | ConvertTo-Json | Out-File 'GitHub_RateLimits.json'
    
        if ($RequestError) {
            if ($rates.remaining -lt 0) {
                $nextTimespan = '{0:dd}d:{0:hh}h:{0:mm}m:{0:ss}s' -f ($rates.next - [DateTimeOffset]::('now'))
                $ErrorString = "GitHub API rate limit exceeded. Try again in $nextTimespan ($($rates.next.ToLocalTime().toString()))."
                Write-Error $ErrorString
                $ProgressPreference = $prevProg
                return
            }
            else {
                Write-Error $RequestError
                $ProgressPreference = $prevProg
                return
            }
        }
        $ProgressPreference = $prevProg
        return $request.Content | ConvertFrom-Json | Add-Member -NotePropertyName 'GhRemainingRate' -NotePropertyValue $rates.remaining -PassThru
    }

    function Get-Hashes {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory)] [String] $owner,
            [Parameter(Mandatory)] [String] $repo,
            [Parameter(Mandatory)] [String] $rawFile
        )
        $prevProg = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'

        try {
            $latestTag = (Invoke-GitHubRestRequest -Uri ('https://api.github.com/repos/' + $owner + '/' + $repo + '/releases/latest') -ErrorAction Stop).tag_name
            $request = Invoke-GitHubRestRequest -Uri ('https://api.github.com/repos/' + $owner + '/' + $repo + '/tags') -ErrorAction Stop
            $CommitSha = ($request | Where-Object name -EQ $latestTag).commit.sha
            try { $content = ((Invoke-WebRequest -Uri ('https://raw.githubusercontent.com/' + $owner + '/' + $repo + '/' + $CommitSha + $rawFile)).Content | ConvertFrom-Json) | & { Process { Add-Member -InputObject $_ 'Version' $latestTag -PassThru } } }
            catch { }
        }
        catch {
            Write-Error $_
            $ProgressPreference = $prevProg
            return
        }

        if (!$content) {
            Write-Warning 'Could not find compatible hashes for latest release. Falling back to latest default branch.'
            try {
                $defaultBranch = (Invoke-GitHubRestRequest -Uri ('https://api.github.com/repos/' + $owner + '/' + $repo) -ErrorAction Stop).default_branch
                try { $content = ((Invoke-WebRequest -Uri ('https://raw.githubusercontent.com/' + $owner + '/' + $repo + '/' + $defaultBranch + $rawFile)).Content | ConvertFrom-Json) | & { Process { Add-Member -InputObject $_ 'Version' $defaultBranch -PassThru } } }        
                catch { }
            }
            catch {
                Write-Error $_
                $ProgressPreference = $prevProg
                return
            }
        }
        $ProgressPreference = $prevProg
        return $content
    }

    function Get-HMHashes {
        if (Test-Path -LiteralPath 'HMHashes.json') {
            $Data = Get-Content -LiteralPath 'HMHashes.json' | ConvertFrom-Json
        }
        $now = [DateTimeOffset]::('now')
        if ($Data.Hashes -and ([DateTimeOffset]$Data.lastUpdate.AddHours(1) -gt $now)) {
            return $Data
        }
        Write-Host 'Updating hashes from GitHub.'
        $params = @{
            owner   = 'HarbourMasters'
            rawFile = '/docs/supportedHashes.json'
        }
        $Hashes = & {
            Get-Hashes @params -repo 'Shipwright' | Add-Member 'Game' 'SoH' -PassThru -ErrorAction SilentlyContinue
            Get-Hashes @params -repo '2ship2harkinian' | Add-Member 'Game' '2S2H' -PassThru -ErrorAction SilentlyContinue
            #Get-Hashes @params -repo 'Starship' | Add-Member 'Game' 'Starship' -PassThru -ErrorAction SilentlyContinue
        }
        if (!$Hashes) {
            Write-Warning 'Could not update compatible sha1 hashes from GitHub!'
        }
        else {

            $Data = [PSCustomObject]@{
                Hashes = $Hashes
                lastUpdate = $now
            } 
            $Data | ConvertTo-Json | Out-File 'HMHashes.json'
            return $Data
            
        }
    }

    $HMhashes = (Get-HMHashes).Hashes

}

Process {
    foreach ($File in $fileIn) {
        if (!$File) {
            return
        }
        if (Test-Path $File -PathType Leaf) {
            $header = $null
            $File = [System.IO.FileInfo] $File
            if ($File.Extension -EQ '.z64') {     
                try { $header = [N64.RomHeader]::Read($File) }
                catch {
                    Write-Error 'Error while reading N64 Rom file.'
                    Write-Verbose $_
                }
            }
            $FileHash = Get-FileHash $File -Algorithm SHA1
            $Compat = $HMhashes | Where-Object sha1 -EQ $FileHash.Hash
            if ($compat) {
                $HM_Game = $compat.Game + ' (' + $compat.version + ')'
            }
            Write-Output ([PSCustomObject]@{
                    Name       = $File.Name
                    Path       = $File.Directory
                    SHA1       = (Get-FileHash $File -Algorithm SHA1).Hash
                    N64_Header = $header
                    HM_Game    = $HM_Game
                    HM_Type    = $Compat.name
                })
        }
    }
}

End {
    if (!$nopause -and $fileIn) {
        Pause
    }
    if ($erroroccured) { EXIT 1 }
    EXIT
}
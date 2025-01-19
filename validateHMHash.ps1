<#
.NOTES
HM Hash Validator v25.01.19
    
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
    [Parameter(ParameterSetName = 'Default')][Parameter(ParameterSetName = 'Update', Mandatory)] [switch] $UpdateHashes,
    [Parameter(ParameterSetName = 'Default')] [switch] $nopause
)

Begin {
    function Get-Hashes {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory)] [String] $owner,
            [Parameter(Mandatory)] [String] $repo,
            [Parameter(Mandatory)] [String] $rawFile
        )
        $prevProg = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'
        $Remaining = ((Invoke-WebRequest -Uri 'https://api.github.com/rate_limit').Content | ConvertFrom-Json).resources.core.remaining
    
        if ($Remaining -ge 2) {
            $latestTag = ((Invoke-WebRequest -Uri ('https://api.github.com/repos/' + $owner + '/' + $repo + '/releases/latest')).Content | ConvertFrom-Json).tag_name
            $request = Invoke-WebRequest -Uri ('https://api.github.com/repos/' + $owner + '/' + $repo + '/tags')
            $Remaining = $request.Headers['X-RateLimit-Remaining']
            $CommitSha = (($request.Content | ConvertFrom-Json) | Where-Object name -EQ $latestTag).commit.sha
            try { $content = ((Invoke-WebRequest -Uri ('https://raw.githubusercontent.com/' + $owner + '/' + $repo + '/' + $CommitSha + $rawFile)).Content | ConvertFrom-Json) | & { Process { Add-Member -InputObject $_ 'Version' $latestTag -PassThru } } }
            catch { }
        }
        if (!$content) {
            if ($Remaining -ge 1) {
                $defaultBranch = ((Invoke-WebRequest -Uri ('https://api.github.com/repos/' + $owner + '/' + $repo)).Content | ConvertFrom-Json).default_branch
                try { $content = ((Invoke-WebRequest -Uri ('https://raw.githubusercontent.com/' + $owner + '/' + $repo + '/' + $defaultBranch + $rawFile)).Content | ConvertFrom-Json) | & { Process { Add-Member -InputObject $_ 'Version' $defaultBranch -PassThru } } }        
                catch { }
            }
            else {
                # Basically bruteforce
                $BranchNames = @('main', 'develop')
                $i = 0
                while (!$content -and $i -lt $BranchNames.Count) {
                    try { $content = ((Invoke-WebRequest -Uri ('https://raw.githubusercontent.com/' + $owner + '/' + $repo + '/' + $BranchNames[$i] + $rawFile)).Content | ConvertFrom-Json) | & { Process { Add-Member -InputObject $_ 'Version' $BranchNames[$i] -PassThru } } }
                    catch { }
                    $i++
                }
            }
        }
        return $content
        $ProgressPreference = $prevProg
    }

    function Get-HMHashes {
        $params = @{
            owner   = 'HarbourMasters'
            rawFile = '/docs/supportedHashes.json'
        }
        $Hashes = & {
            Get-Hashes @params -repo 'Shipwright' | Add-Member 'Game' 'SoH' -PassThru
            Get-Hashes @params -repo '2ship2harkinian' | Add-Member 'Game' '2S2H' -PassThru
            Get-Hashes @params -repo 'Starship' | Add-Member 'Game' 'Starship' -PassThru
        }
        if ($Hashes) {
            $Hashes | ConvertTo-Json | Out-File 'HMHashes.json'
            return $true
        }
        else {
            return $false
        }
    }
    if (Test-Path -LiteralPath 'HMHashes.json') {
        $HMhashes = Get-Content -LiteralPath 'HMHashes.json' | ConvertFrom-Json
    }

    If ($UpdateHashes -OR !$HMhashes) {
        $HMhashes = $null
        if (!(Get-HMHashes)) {
            Write-Warning 'Could not get any compatible sha1 hashes from GitHub! (No network connection?)'
        }

        if (Test-Path -LiteralPath 'HMHashes.json') {
            $HMhashes = Get-Content -LiteralPath 'HMHashes.json' | ConvertFrom-Json
        }
    }
}

Process {
    foreach ($File in $fileIn) {
        if (!$File) {
            return
        }
        if (Test-Path $File -PathType Leaf) {
            $header = $null
            $File = [System.IO.FileInfo] $File
            if ($_.Extension -EQ '.z64') {     
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
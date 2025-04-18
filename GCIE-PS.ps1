<#
.DESCRIPTION
Extracts or lists files from an uncompressed GameCube image (uncompressed gcm/iso). As this was originally written for "Harbor Masters 64" ports, it tries to extract a supported OoT, MQ or MM ROM by default. But it can also be used to extract any raw file from the gcm/iso by name or just list its file system.

Requires you to install .NET and Powershell on MacOS and Linux (untested, but should work).

> [!TIP]
> Instead of starting the script the usual way, you can also Drag & Drop your rom on the included batch file to kickstart the automatic extraction.

There is also a C# port of this ported by xoascf (aka Amaro): https://github.com/xoascf/GCIE

.NOTES
GameCube Image Extractor - PowerShell Script v25.04.04
    
    MIT License

    Copyright (C) 2024 Spodi

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

Using Module '.\GC.psm1'
Using Module '.\N64.psm1'

[CmdletBinding(PositionalBinding = $false, DefaultParameterSetName = 'Default')]
param (
    # GameCube image file to extract or list files from (uncompressed gcm/iso).
    [Parameter(ParameterSetName = 'Extract', Position = 0, Mandatory)]
    [Parameter(ParameterSetName = 'List', Position = 0, Mandatory)]
    [Parameter(ParameterSetName = 'Default', Position = 0, Mandatory)]
    [string]$fileIn,
    # Extracts all files where their full name (path + name) matches this Regular Expression.
    [Parameter(ParameterSetName = 'Extract', Position = 1, Mandatory)] [string]$Extract,
    # Lists all files in the image. "Object" sends the file infos as objects to the pipeline. "Text" and "Json" saves the infos as "FileList.txt" or "FileList.json".
    [Parameter(ParameterSetName = 'List', Position = 1, Mandatory)][ValidateSet('Object', 'Text', 'Json')] [string]$ListFiles,
    # Does not pause to keep the console open after extraction (useful for automation).
    [Parameter(ParameterSetName = 'Default')] [Parameter(ParameterSetName = 'Extract')] [switch] $nopause
)

Begin {
    $erroroccured = $null
}
Process {
    $RSHashes = [powershell]::Create()
    $RSHashes.Runspace.SessionStateProxy.SetVariable('Root', $PSScriptRoot)
    [void]$RSHashes.AddScript({
            if ((Test-Path 'validateHMHash.ps1' -PathType Leaf) -and -not (Test-Path 'HMHashes.json' -PathType Leaf)) {
                . 'validateHMHash.ps1' -UpdateHashes
            }
        })

    if (!(Test-Path -LiteralPath $fileIn -PathType Leaf)) {
        Write-Error "File `"$fileIn`" not found!"
        return
    }

    $RSHashesHandle = $RSHashes.BeginInvoke()

    $fileInfo = [System.IO.FileInfo] $fileIn
    $Stream = [System.IO.File]::OpenRead($fileIn)
    try { $Disc = [GC.Disc]$Stream }
    catch {
        Write-Error 'Error while reading GC Rom file.'
        Write-Verbose $_
        $erroroccured = $true
        return
    }
    Write-Host '------ Input: ------' -ForegroundColor Cyan
    ([PSCustomObject]@{
        Name      = $fileInfo.Name
        Path      = $fileInfo.Directory
        GC_Header = $Disc.ToString()
        #SHA1   = (Get-FileHash $fileIn -Algorithm SHA1).Hash
    } | Format-List | Out-String).Trim() | Out-Host

    $list = $Disc.GetAllEntries() | & { Process { if ($_ -is [FileEntry]) { $_ } } }
    Write-Host '--------------------' -ForegroundColor Cyan


    if ($ListFiles) {
        switch ($ListFiles) {
            'Object' {
                $list | Sort-Object FileOffset | Write-Output 
            }
            'json' {
                $list | Select-Object FileOffset, Size, Path, Name | Sort-Object FileOffset | ConvertTo-Json | Out-File FileList.json
            }
            'Text' {
            ($list | Select-Object FileOffset, Size, Path, Name | Sort-Object FileOffset | Format-Table | Out-String).Trim() | Out-File FileList.txt
            }
        }
    }

    elseif ($Extract) {
        $List = $List | Where-Object 'FullName' -Match $Extract
        if ($List) {
            $extractedFiles = $List | & { Process {
                    if ([System.IO.Path]::GetExtension($_.Name) -EQ '.n64') {
                        $_.WriteFile((Join-Path $PSScriptRoot ([System.IO.Path]::ChangeExtension($_.Name, '.z64'))), $true)
                    }
                    else {
                        $_.WriteFile((Join-Path $PSScriptRoot $_.Name), $true)
                    }
                } }
        }
        else {
            Write-Host "Couldn't find any file or path matching the regular expression `"$Extract`"."
        }
    }

    else {

        if ($list) {
            $extractedFiles = & {
                switch ($list) {

                    { $_.name -eq 'zlp_f.n64' } {
                        # Ocarina of Time EU
                        try { $_.WriteFile((Join-Path $PSScriptRoot 'TLoZ-OoT-GC-EU.z64'), $true) }
                        catch [FileAlreadyExistsException] {
                            Write-Error -ErrorRecord $_ -ErrorAction 'Continue'
                        }
                    }
                
                    { $_.name -eq 'urazlp_f.n64' } {
                        # Ocarina of Time - Master Quest EU
                        try { $_.WriteFile((Join-Path $PSScriptRoot 'TLoZ-OoT-MQ-GC-EU.z64'), $true) }
                        catch [FileAlreadyExistsException] {
                            Write-Error -ErrorRecord $_ -ErrorAction 'Continue'
                        }
                    }

                    { $_.name -eq 'zle_f.n64' } {
                        # Ocarina of Time US
                        try { $_.WriteFile((Join-Path $PSScriptRoot 'TLoZ-OoT-GC-US.z64'), $true) }
                        catch [FileAlreadyExistsException] {
                            Write-Error -ErrorRecord $_ -ErrorAction 'Continue'
                        }
                    }
                
                    { $_.name -eq 'urazle_f.n64' } {
                        # Ocarina of Time - Master Quest US
                        try { $_.WriteFile((Join-Path $PSScriptRoot 'TLoZ-OoT-MQ-GC-US.z64'), $true) }
                        catch [FileAlreadyExistsException] {
                            Write-Error -ErrorRecord $_ -ErrorAction 'Continue'
                        }
                    }

                    { $_.name -eq 'zlj_f.n64' } {
                        # Ocarina of Time JP
                        try { $_.WriteFile((Join-Path $PSScriptRoot 'TLoZ-OoT-GC-JP.z64'), $true) }
                        catch [FileAlreadyExistsException] {
                            Write-Error -ErrorRecord $_ -ErrorAction 'Continue'
                        }
                    }
                
                    { $_.name -eq 'urazlj_f.n64' } {
                        # Ocarina of Time - Master Quest JP
                        try { $_.WriteFile((Join-Path $PSScriptRoot 'TLoZ-OoT-MQ-GC-JP.z64'), $true) }
                        catch [FileAlreadyExistsException] {
                            Write-Error -ErrorRecord $_ -ErrorAction 'Continue'
                        }
                    }

                    { $_.name -eq '120903_zelda.n64' } {
                        # Ocarina of Time Collectors Edition JP
                        try { $_.WriteFile((Join-Path $PSScriptRoot 'TLoZ-OoT-GC-CE-JP.z64'), $true) }
                        catch [FileAlreadyExistsException] {
                            Write-Error -ErrorRecord $_ -ErrorAction 'Continue'
                        }
                    }
                
                

                    { $_.name -eq 'zelda2e.n64' } {
                        # Majoras Mask US
                        try { $_.WriteFile((Join-Path $PSScriptRoot 'TLoZ-MM-GC-US.z64'), $true) }
                        catch [FileAlreadyExistsException] {
                            Write-Error -ErrorRecord $_  -ErrorAction 'Continue'
                        }
                    }

                    { $_.name -eq 'zelda2e.n64' } {
                        # Majoras Mask US
                        try { $_.WriteFile((Join-Path $PSScriptRoot 'TLoZ-MM-GC-US.z64'), $true) }
                        catch [FileAlreadyExistsException] {
                            Write-Error -ErrorRecord $_  -ErrorAction 'Continue'
                        }
                    }

                } 
            }
        }
        else {
            Write-Host "Couldn't find any PAL OoT, PAL MQ or NTSC-U MM ROM."
        }
    }

    $RSHashes.EndInvoke($RSHashesHandle)
    $RSHashes.Runspace.Close()
    $RSHashes.Dispose()

    if ($extractedFiles) {
        if (Test-Path '.\validateHMHash.ps1' -PathType Leaf) {
            $extractedFiles | & '.\validateHMHash.ps1' -nopause | Write-Output
        }
        else {
            $extractedFiles | ForEach-Object {
                if (Test-Path $_ -PathType Leaf) {
                    $header = $null
                    $File = [System.IO.FileInfo] $_
                    if ($File.Extension -EQ '.z64') {     
                        try { $header = [N64.RomHeader]::Read($File) }
                        catch {
                            Write-Error 'Error while reading N64 Rom file.'
                            Write-Verbose $_
                        }
                    }
                 ([PSCustomObject]@{
                        Name       = $File.Name
                        Path       = $File.Directory
                        SHA1       = (Get-FileHash $File -Algorithm SHA1).Hash
                        N64_Header = $header
                        HM_Game    = $null
                        HM_Type    = $null
                    }) | Write-Output             
                }       
            }
        }
        if (!$nopause) {
            Pause
        }
    }
}
End {
    if ($erroroccured) { EXIT 1 }
    EXIT
}
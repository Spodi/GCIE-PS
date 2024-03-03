<#
.SYNOPSIS
Extracts or lists files from an uncompressed GameCube image (uncompressed iso). Trys to extract a PAL OoT or MQ ROM by default.

.NOTES
GameCube Image Extractor Script v24.02.29
    
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

Using Module .\GC.psm1

[CmdletBinding(PositionalBinding = $false, DefaultParameterSetName = 'Default')]
param (
    # GameCube image file to extract or list files from (uncompressed iso).
    [Parameter(ParameterSetName = 'Extract', Position = 0, Mandatory)][Parameter(ParameterSetName = 'List', Position = 0, Mandatory)][Parameter(ParameterSetName = 'Default', Position = 0, Mandatory)] [string]$fileIn,
    # Extracts all files where their full name (path + name) matches this Regular Expression.
    [Parameter(ParameterSetName = 'Extract', Position = 1, Mandatory)] [string]$Extract,
    # Lists all files in the image. "Object" sends the file infos as objects to the pipeline. "Text" and "Json" saves the infos as "FileList.txt" or "FileList.json".
    [Parameter(ParameterSetName = 'List', Position = 1, Mandatory)][ValidateSet('Object', 'Text', 'Json')] [string]$ListFiles
)


if (!(Test-Path -LiteralPath $fileIn)) {
    Throw "File `"$fileIn`" not found!"
}

$Stream = [System.IO.File]::OpenRead($fileIn)
$DiscHeader = [GC.DiscHeader]::Read($Stream)
Write-Host $DiscHeader.GameCode ' - ' $DiscHeader.GameName

$list = [GC.FSEntry]::Read($Stream, $DiscHeader) | & { Process { if ($_ -is [FileEntry]) { $_ } } } | Sort-Object FileOffset

if ($ListFiles) {
    switch ($ListFiles) {
        'Object' {
            Write-Output $list 
        }
        'json' {
            $list | Select-Object FileOffset, Size, Path, Name | ConvertTo-Json | Out-File FileList.json
        }
        'Text' {
            ($list | Select-Object FileOffset, Size, Path, Name | Format-Table | Out-String).Trim() | Out-File FileList.txt
        }
    }
}

elseif ($Extract) {
    $List = $List | Where-Object 'FullName' -Match $Extract
    if ($List) {
        $rom | & { Process {
                $_.WriteFile((Join-Path $PSScriptRoot $_.Name))
            } }
    }
    else {
        Write-Host "Couldn't find any file or path matching the regular expression `"$Extract`"."
    }
}

else {
    $list = $list | Where-Object 'Name' -Match '^((ura)?zlp_f|zelda2p)\.n64$'
    if ($list) {
        $list | & { Process {
                # Ocarina of Time
                if ($_.name -eq 'zlp_f.n64') {
                    $_.WriteFile((Join-Path $PSScriptRoot 'TLoZ-OoT-GC.z64'))
                }
                # Ocarina of Time - Master Quest
                elseif ($_.name -eq 'urazlp_f.n64') {
                    $_.WriteFile((Join-Path $PSScriptRoot 'TLoZ-OoT-MQ-GC.z64'))
                }
                
                # Majoras Mask
                elseif ($_.name -eq 'zelda2p.n64') {
                    $_.WriteFile((Join-Path $PSScriptRoot 'TLoZ-MM-GC.z64'))
                }
                 
            } }
    }
    else {
        Write-Host "Couldn't find any PAL OoT or MQ ROM."
    }
}

$Stream.Dispose()
Exit
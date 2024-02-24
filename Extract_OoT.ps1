<#
.SYNOPSIS
Extracts or lists files from an uncompressed GameCube image (uncompressed iso). Trys to extract a PAL OoT or MQ ROM by default.

.NOTES
GameCube Image Extractor Script v23.12.06
    
    MIT License

    Copyright (C) 2023 Spodi

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

[CmdletBinding(PositionalBinding = $false, DefaultParameterSetName = "Default")]
param (
    # GameCube image file to extract or list files from (uncompressed iso).
    [Parameter(ParameterSetName = "Extract", Position = 0, Mandatory)][Parameter(ParameterSetName = "List", Position = 0, Mandatory)][Parameter(ParameterSetName = "Default", Position = 0, Mandatory)] [string]$fileIn,
    # Extracts all files where their full name (path + name) matches this Regular Expression.
    [Parameter(ParameterSetName = "Extract", Position = 1, Mandatory)] [string]$Extract,
    # Lists all files in the image. "Object" sends the file infos as objects to the pipeline. "Text" and "Json" saves the infos as "FileList.txt" or "FileList.json".
    [Parameter(ParameterSetName = "List", Position = 1, Mandatory)][ValidateSet("Object", "Text", "Json")] [string]$ListFiles
)

# Just a little thing to not let me confuse those two.
enum FSTType {
    File = 0
    Directory = 1
}

function Split-File {
    <#
    .SYNOPSIS
    Makes a new file out of another by copying only a specific area.
    .NOTES
    #>
    [CmdletBinding()]
    param(
        # The source stream to get the data from.
        [Parameter(Mandatory, Position = 0)] [System.IO.Stream]$Stream,
        # Name and path of the new file. Won't overwrite existing files.
        [Parameter(Mandatory, Position = 1)] [string]$fileOut,
        # Starting position of the area to copy in bytes (from start of the file).
        [Parameter()] [int64]$start = 0,
        # Size of the area to copy in bytes (bytes from starting position).
        [Parameter(Mandatory)] [int64]$size
    )
    begin {
        $prevDir = [System.IO.Directory]::GetCurrentDirectory()
        [System.IO.Directory]::SetCurrentDirectory((Get-location))
    }
    Process {
        if (Test-Path -Path $fileOut -PathType Leaf) {
            Write-Error "$fileOut already exists."
            return
        }
        $destination = [System.IO.Path]::GetDirectoryName($fileOut)
        if ($destination) {
            if (!(Test-Path -LiteralPath $destination -PathType Container)) {
                New-Item $destination -ItemType Directory | Out-Null
            }
        }
        $read = $Stream
        $write = [System.IO.File]::OpenWrite($fileOut)
        $buffer = new-object Byte[] 131072
        $BytesToRead = $size
        [void]$read.seek($start, 0)
        while ($BytesToRead -gt 0) {
            if ($BytesToRead -lt $buffer.Count) {
                $n = $read.read($buffer, 0, $BytesToRead)
                [void]$write.write($buffer, 0, $BytesToRead)
            }
            else {
                $n = $read.read($buffer, 0, $buffer.Count)
                [void]$write.write($buffer, 0, $buffer.Count)
            }
            if ($n -eq 0) { break }
            $BytesToRead = $BytesToRead - $n
        }
        $write.close()
    
    }
    end {
        [System.IO.Directory]::SetCurrentDirectory($prevDir)
    }
}

function Convert-ByteArrayToUint32 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [Byte[]] $value
    )
    while ($value.count -lt 4) {
        $value = [byte[]]@(00) + $value
    }
    if ([System.BitConverter]::IsLittleEndian) {
        [Array]::Reverse($value)
    }
    [System.BitConverter]::ToUInt32($value, 0)
}

function Read-GCFST {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]  [System.IO.Stream] $Stream,
        [Parameter(Mandatory)]  [uint32] $FSTStart,
        [Parameter()]  [int32] $OffsetShift,
        [Parameter()]  [string] $ParentFile
    )
    begin {
        $FSTEntry = new-object Byte[] 0x0C
    }
    Process {
        [void]$Stream.seek($FSTStart, 0)
        [void]$Stream.read($FSTEntry, 0, 0xC)
        $root = [PSCustomObject]@{
            Type       = [FSTType]$FSTEntry[0]
            EntryCount = Convert-ByteArrayToUint32($FSTEntry[8..11])
        }
        $lastFolder = 0
        $FST = & { for ($i = 1; $i -lt ($root.EntryCount); $i++) {
                [void]$Stream.read($FSTEntry, 0, 0xC)
                if ([FSTType]$FSTEntry[0] -eq 'Directory') {
                    $lastFolder = $i
                    [PSCustomObject]@{
                        Pos          = $i
                        ParentFile   = $ParentFile
                        Type         = [FSTType]$FSTEntry[0]
                        Path         = $null
                        Name         = $null
                        NameOffset   = Convert-ByteArrayToUint32($FSTEntry[1..3])
                        ParentDirPos = Convert-ByteArrayToUint32($FSTEntry[4..7])
                        NextDirPos   = Convert-ByteArrayToUint32($FSTEntry[8..11])
                        FullName     = $null
                        OffsetShift = $OffsetShift
                    } #| Add-member -PassThru ScriptProperty 'FullName' { $this.ParentFile + $this.Path + $this.Name + '/' }
                    # "Add-Member" is slow, so we add "FullName" empty for now and add its value later in a 3rd pass.
                }
                else {
                    [PSCustomObject]@{
                        Pos          = $i
                        ParentFile   = $ParentFile
                        Type         = [FSTType]$FSTEntry[0]
                        Path         = $null
                        Name         = $null
                        NameOffset   = Convert-ByteArrayToUint32($FSTEntry[1..3])
                        FileOffset   = (Convert-ByteArrayToUint32($FSTEntry[4..7])) + $OffsetShift
                        Size         = Convert-ByteArrayToUint32($FSTEntry[8..11])
                        ParentDirPos = $lastFolder
                        FullName     = $null
                        OffsetShift = $OffsetShift
                    } #| Add-Member -PassThru ScriptProperty 'FullName' { $this.ParentFile + $this.Path + $this.Name }
                } 
            } }

        $StringTablePos = $Stream.Position
        # 1st Pass: Getting the names from the String-Table
        # Funny enough "& {Process { }}"  is MUCH faster then "Foreach-Object { }" and does the same. 
        $FST | & { Process {                      
                $name = & { [void]$Stream.seek(($StringTablePos + $_.nameoffset), 0)
                    While ($byte -ne 0) {
                        $byte = $Stream.ReadByte()
                        if ($byte -ne 0) {
                            $byte
                        }
                    }
                }
                $_.Name = [System.Text.Encoding]::ASCII.GetString($name) 
                $_
            }
        } | Group-Object ParentDirPos | & { Process {
                # 2nd Pass: Add Paths
                [System.Collections.ArrayList]$path = @('/')
                $parent = $_.Group[0]
                while ($parent.ParentDirPos -ne 0) {
                    $parent = $FST[($parent.ParentDirPos - 1)] # Avoid Where-Object here (slow!). Position in the FST matches the position in the array anyway (root would be [0], but is not in the array, so "-1").
                    $Path.insert(0, $parent.Name)
                    $Path.insert(0, '/')             
                }
                $_.Group.ForEach('Path', -join $Path)
                $_.Group  # ungroup things again
            } } | & { Process {
                # 3rd Pass: Add FullName here and avoid slow "Add-Member"
                if ($_.Type -eq 'Directory') {
                    $_.FullName = $_.ParentFile + $_.Path + $_.Name + '/'
                }
                else {
                    $_.FullName = $_.ParentFile + $_.Path + $_.Name
                }
                $_
            } }
    }    
} 

function Read-TGC {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]                      [System.IO.Stream] $Stream,
        [Parameter(ValueFromPipelineByPropertyName)]   [uint32] $FileOffset,
        [Parameter(ValueFromPipelineByPropertyName)]   [string] $FullName
    )
    begin {
        $TGCMagic = [Byte[]]@(0xae, 0x0f, 0x38, 0xa2)
    }
    Process {
        [void]$Stream.seek($FileOffset, 0)
        [void]$Stream.read($buffer, 0, 0x4)
        if (!(Compare-object $buffer $TGCMagic)) {
            [void]$Stream.seek($FileOffset + 0x0010, 0)
            [void]$Stream.read($buffer, 0, 0x4)
            $FSTStart = (Convert-ByteArrayToUint32($buffer)) + $FileOffset
            [void]$Stream.seek((0x4 * 4), 1)
            [void]$Stream.read($buffer, 0, 0x4)
            $fileArea = Convert-ByteArrayToUint32($buffer)
            [void]$Stream.seek((0x4 * 3), 1)
            [void]$Stream.read($buffer, 0, 0x4)
            $virtualFileArea = Convert-ByteArrayToUint32($buffer)
            $OffsetShift = [Int32](($fileArea - $virtualFileArea) + $FileOffset)
            Read-GCFST $Stream $FSTStart $OffsetShift $FullName
        }
    }
}

if (!(Test-Path -LiteralPath $fileIn)) {
    Throw "File `"$fileIn`" not found!"
}

$Stream = [System.IO.File]::OpenRead($fileIn)

$buffer = new-object Byte[] 0x04

[void]$Stream.seek(0x0424, 0)
[void]$Stream.read($buffer, 0, 0x4)
$FSTStart = Convert-ByteArrayToUint32($buffer)


$list = Read-GCFST $Stream $FSTStart | Where-Object 'Type' -eq 'File' |  & { Process {
        $_
        if ($_.Name -match '\.tgc$') {
            $_ | Read-TGC $Stream | Where-Object 'Type' -eq 'File' | & { Process {
                    $_ 
                } }
        }
    } } | Sort-Object FileOffset

if ($ListFiles) {
    switch ($ListFiles) {
        'Object' {
           Write-Output $list
        }
        'json' {
            $list | Select-Object FileOffset, Size, Name, FullName | ConvertTo-Json | Out-File FileList.json
        }
        'Text' {
            $list | Select-Object FileOffset, Size, Name, FullName | Format-Table | Out-File FileList.txt
        }
    }
}

elseif ($Extract) {
    $List = $List | Where-Object 'FullName' -match $Extract
    if ($List) {
        $rom | & { Process {
                Split-File $Stream (join-path $PSScriptRoot $_.Name) -start $_.FileOffset -size $_.Size
            } }
    }
    else {
        Write-Host "Couldn't find any file or path matching the regular expression `"$Extract`"."
    }
}

else {
    $list = $list | Where-Object 'Name' -match '^((ura)?zlp_f|zelda2p)\.n64$'
    if ($list) {
        $list | & { Process {
                if ($_.name -eq 'zlp_f.n64') {
                    Split-File $Stream (join-path $PSScriptRoot 'TLoZ-OoT-GC.z64') -start $_.FileOffset -size $_.Size
                }
                elseif ($_.name -eq 'urazlp_f.n64') {
                    Split-File $Stream (join-path $PSScriptRoot 'TLoZ-OoT-MQ-GC.z64') -start $_.FileOffset -size $_.Size
                }
                <#
        elseif ($_.name -eq 'zelda2p.n64') {
            Split-File $Stream (join-path $PSScriptRoot 'TLoZ-MM-GC.z64') -start $_.FileOffset -size $_.Size
        }
        #>
            } }
    }
    else {
        Write-Host "Couldn't find any PAL OoT or MQ ROM."
    }
}

$Stream.Close()
Exit
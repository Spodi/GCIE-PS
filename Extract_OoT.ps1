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

enum SystemID {
    GameCube = 0x47
    Promotional = 0x44
    GBAPlayer = 0x55
}

enum RegionCode {
    USA_NTSC = 0x45
    Europe_PAL = 0x50
    Japan_NTSC = 0x4a
    Other_PAL = 0x55
}
enum FSTType {
    File = 0
    Directory = 1
}

class GCHeaderGameCodeRaw {
    [byte] $SystemID
    [ValidateCount(0x2, 0x2)][byte[]] $GameID
    [byte] $RegionCode

    GCHeaderGameCodeRaw() {}

    GCHeaderGameCodeRaw([hashtable]$Properties) {
        foreach ($Property in $Properties.Keys) {
            $this.$Property = $Properties.$Property
        } 
    }

    GCHeaderGameCodeRaw([Byte[]]$value) {
        $this.SystemID = $value[0]
        $this.GameID = $value[1..2]
        $this.RegionCode = $value[3]
    }

}

class GCDiskHeaderRaw {
    [ValidateCount(0x4, 0x4)][byte[]] $GameCode
    [ValidateCount(0x2, 0x2)][byte[]] $MakerCode
    [byte] $DiscID
    [byte] $Version
    [byte] $AudioStreaming
    [byte] $StreamBufferSize
    [ValidateCount(0x12, 0x12)][byte[]] $Unknown1 #should be all 0
    [ValidateCount(0x4, 0x4)][byte[]] $DVDMagic #0xc2339f3d
    [ValidateCount(0x3e0, 0x3e0)][byte[]] $GameName
    [ValidateCount(0x4, 0x4)][byte[]] $DebugMonitorOffset
    [ValidateCount(0x4, 0x4)][byte[]] $DebugMonitorAddress
    [ValidateCount(0x18, 0x18)][byte[]] $Unknown2
    [ValidateCount(0x4, 0x4)][byte[]] $MainExecutableOffset
    [ValidateCount(0x4, 0x4)][byte[]] $FSTOffset
    [ValidateCount(0x4, 0x4)][byte[]] $FSTSize
    [ValidateCount(0x4, 0x4)][byte[]] $FSTSizeMax
    [ValidateCount(0x4, 0x4)][byte[]] $CustomOffset
    [ValidateCount(0x4, 0x4)][byte[]] $CustomSize
    [ValidateCount(0x4, 0x4)][byte[]] $Unknown3
    [ValidateCount(0x4, 0x4)][byte[]] $Unknown4


    GCDiskHeaderRaw() {}

    GCDiskHeaderRaw([hashtable]$Properties) {
        foreach ($Property in $Properties.Keys) {
            $this.$Property = $Properties.$Property
        } 
    }

    GCDiskHeaderRaw([Byte[]]$value) {
        if ($value.count -ne 0x0440) {
            throw 'Invalid length of byte array! Must be 1088 bytes long.'
        }
        $this.GameCode = $value[0x0000..0x0003]
        $this.MakerCode = $value[0x0004..0x0005]
        $this.DiscID = $value[0x0006]
        $this.Version = $value[0x0007]
        $this.AudioStreaming = $value[0x0008]
        $this.StreamBufferSize = $value[0x0009]
        $this.Unknown1 = $value[0x000a..0x001b]
        $this.DVDMagic = $value[0x001c..0x001f]
        $this.GameName = $value[0x0020..0x03ff]
        $this.DebugMonitorOffset = $value[0x0400..0x0403]
        $this.DebugMonitorAddress = $value[0x0404..0x0407]
        $this.Unknown2 = $value[0x0408..0x041f]
        $this.MainExecutableOffset = $value[0x0420..0x0423]
        $this.FSTOffset = $value[0x0424..0x0427]
        $this.FSTSize = $value[0x0428..0x042B]
        $this.FSTSizeMax = $value[0x042C..0x042F]
        $this.CustomOffset = $value[0x0430..0x0433]
        $this.CustomSize = $value[0x0434..0x0437]
        $this.Unknown3 = $value[0x0438..0x043b]
        $this.Unknown4 = $value[0x043c..0x043f]
    }
}

class GCHeaderGameCode {
    [string] $SystemID
    [string] $GameID
    [string] $RegionCode

    GCHeaderGameCode() {

    }

    GCHeaderGameCode([hashtable]$Properties) {
        foreach ($Property in $Properties.Keys) {
            $this.$Property = $Properties.$Property
        }
    }

    GCHeaderGameCode([Byte[]]$value) {
        $this.SystemID = [System.Text.Encoding]::GetEncoding(932).GetString($value[0])
        $this.GameID = [System.Text.Encoding]::GetEncoding(932).GetString($value[1..2])
        $this.RegionCode = [System.Text.Encoding]::GetEncoding(932).GetString($value[3])
    }

    [string]ToString() {
        return $this.SystemID + $this.GameID + $this.RegionCode
    }
}

class GCDiskHeader {
    [GCHeaderGameCode] $GameCode
    [string] $MakerCode
    [byte] $DiscID
    [byte] $Version
    [byte] $AudioStreaming
    [byte] $StreamBufferSize
    [ValidateCount(0x12, 0x12)][byte[]] $Unknown1 #should be all 0
    [ValidateCount(0x4, 0x4)][byte[]] $DVDMagic #0xc2339f3d
    [string] $GameName
    [uint32] $DebugMonitorOffset
    [uint32] $DebugMonitorAddress
    [ValidateCount(0x18, 0x18)][byte[]] $Unknown2
    [uint32] $MainExecutableOffset
    [uint32] $FSTOffset
    [uint32] $FSTSize
    [uint32] $FSTSizeMax
    [uint32] $CustomOffset
    [uint32] $CustomSize
    [ValidateCount(0x4, 0x4)][byte[]] $Unknown3
    [ValidateCount(0x4, 0x4)][byte[]] $Unknown4

    GCDiskHeader([Byte[]]$value) {
        if ($value.count -ne 0x0440) {
            throw 'Invalid length of byte array! Must be 1088 bytes long.'
        }
        $this.GameCode = [byte[]]$value[0x0000..0x0003]
        $this.MakerCode = [System.Text.Encoding]::GetEncoding(932).GetString($value[0x0004..0x0005])
        $this.DiscID = $value[0x0006]
        $this.Version = $value[0x0007]
        $this.AudioStreaming = $value[0x0008]
        $this.StreamBufferSize = $value[0x0009]
        $this.Unknown1 = $value[0x000a..0x001b]
        $this.DVDMagic = $value[0x001c..0x001f]
        $this.GameName = [System.Text.Encoding]::GetEncoding(932).GetString($value[0x0020..0x03ff]).Trim([char]0)
        $this.DebugMonitorOffset = [System.Buffers.Binary.BinaryPrimitives]::ReadUInt32BigEndian([byte[]]$value[0x0400..0x0403])
        $this.DebugMonitorAddress = [System.Buffers.Binary.BinaryPrimitives]::ReadUInt32BigEndian([byte[]]$value[0x0404..0x0407])
        $this.Unknown2 = $value[0x0408..0x041f]
        $this.MainExecutableOffset = [System.Buffers.Binary.BinaryPrimitives]::ReadUInt32BigEndian([byte[]]$value[0x0420..0x0423])
        $this.FSTOffset = [System.Buffers.Binary.BinaryPrimitives]::ReadUInt32BigEndian([byte[]]$value[0x0424..0x0427])
        $this.FSTSize = [System.Buffers.Binary.BinaryPrimitives]::ReadUInt32BigEndian([byte[]]$value[0x0428..0x042B])
        $this.FSTSizeMax = [System.Buffers.Binary.BinaryPrimitives]::ReadUInt32BigEndian([byte[]]$value[0x042C..0x042F])
        $this.CustomOffset = [System.Buffers.Binary.BinaryPrimitives]::ReadUInt32BigEndian([byte[]]$value[0x0430..0x0433])
        $this.CustomSize = [System.Buffers.Binary.BinaryPrimitives]::ReadUInt32BigEndian([byte[]]$value[0x0434..0x0437])
        $this.Unknown3 = $value[0x0438..0x043b]
        $this.Unknown4 = $value[0x043c..0x043f]
    }

    GCDiskHeader() {
        $this.GameCode = [GCHeaderGameCode]::new()
    }

    GCDiskHeader([hashtable]$Properties) {
        foreach ($Property in $Properties.Keys) {
            $this.$Property = $Properties.$Property
        } 
        if ($null -eq $this.RawData) {
            $this.GameCode = [GCHeaderGameCode]::new()
        }
    }

}

class GCFSEntryRaw {
    [byte] $DirectoryFlag = 0
    [ValidateCount(0x3, 0x3)][byte[]] $NameOffsetIntoStringTable = [byte[]]::new(3)
    [ValidateCount(0x4, 0x4)][byte[]] $FileOffset_ParentDirIndex = [byte[]]::new(4)
    [ValidateCount(0x4, 0x4)][byte[]] $Size_NextDirIndex_NumEntries = [byte[]]::new(4)

    GCFSEntryRaw() {}

    GCFSEntryRaw([hashtable]$Properties) {
        foreach ($Property in $Properties.Keys) {
            $this.$Property = $Properties.$Property
        } 
    }

    GCFSEntryRaw([Byte[]]$value) {
        if ($value.count -ne 12) {
            throw 'Invalid length of byte array! Must be 12 bytes long.'
        }
        $this.DirectoryFlag = $value[0]
        $this.NameOffsetIntoStringTable = $value[1..3]
        $this.FileOffset_ParentDirIndex = $value[4..7]
        $this.Size_NextDirIndex_NumEntries = $value[8..11]
    }
}
class GCFSEntry {
    [uint32] $Index
    [GCFSEntry] $ParentFile
    [FSTType] $Type
    [string] $Path
    [uint32] $NameOffsetIntoStringTable
    [string] $Name
    [string] $FullName
    [uint32] $ParentDirIndex
    hidden [uint32] $_ParentDirIndex
    [nullable[uint32]] $NextDirIndex
    [nullable[uint32]] $FileOffset
    [int32] $TGCOffsetShift
    [nullable[uint32]] $Size
    hidden [GCFSEntryRaw] $RawData

    static GCFSEntry() {
        Update-TypeData -TypeName 'GCFSEntry' -MemberName 'Type' -MemberType ScriptProperty -Value {
            return [FSTType]$this.RawData.DirectoryFlag
        } -SecondValue {
            param($value)
            $this.RawData.DirectoryFlag = [FSTType]$value
        } -Force
        
        Update-TypeData -TypeName 'GCFSEntry' -MemberName 'NameOffsetIntoStringTable' -MemberType ScriptProperty -Value {
            [byte[]]$value = [byte[]]::new(1) + $this.RawData.NameOffsetIntoStringTable
            return [System.Buffers.Binary.BinaryPrimitives]::ReadUInt32BigEndian($value)
        } -SecondValue {
            param($value)
            $buffer = [byte[]]::new(4)
            [void][System.Buffers.Binary.BinaryPrimitives]::WriteUInt32BigEndian($buffer, $value)
            $this.RawData.NameOffsetIntoStringTable = $buffer[1..3]
        } -Force
        
        Update-TypeData -TypeName 'GCFSEntry' -MemberName 'FileOffset' -MemberType ScriptProperty -Value {
            if ($this.Type -eq 'File') {
                return [nullable[uint32]]([System.Buffers.Binary.BinaryPrimitives]::ReadUInt32BigEndian($this.RawData.FileOffset_ParentDirIndex) + $this.TGCOffsetShift)
            }
            else {
                return [nullable[uint32]]$null
            }
        } -SecondValue {
            param($value)
            if ($this.Type -eq 'File') {
                $buffer = [byte[]]::new(4)
                [void][System.Buffers.Binary.BinaryPrimitives]::WriteUInt32BigEndian($buffer, ($value - $this.TGCOffsetShift))
                $this.RawData.FileOffset_ParentDirIndex = $buffer
            }
        } -Force
        
        Update-TypeData -TypeName 'GCFSEntry' -MemberName 'ParentDirIndex' -MemberType ScriptProperty -Value {
            if ($this.Type -eq 'Directory') {
                return [System.Buffers.Binary.BinaryPrimitives]::ReadUInt32BigEndian($this.RawData.FileOffset_ParentDirIndex)
            }
            else {
                return [uint32]$_ParentDirIndex
            }
        } -SecondValue {
            param($value)
            if ($this.Type -eq 'Directory') {
                $buffer = [byte[]]::new(4)
                [void][System.Buffers.Binary.BinaryPrimitives]::WriteUInt32BigEndian($buffer, $value)
                $this.RawData.FileOffset_ParentDirIndex = $buffer
            }
            else {
                [uint32]$this._ParentDirIndex = $value
            }
        } -Force
        
        Update-TypeData -TypeName 'GCFSEntry' -MemberName 'Size' -MemberType ScriptProperty -Value {
            if ($this.Type -eq 'File') {
                return [nullable[uint32]][System.Buffers.Binary.BinaryPrimitives]::ReadUInt32BigEndian($this.RawData.Size_NextDirIndex_NumEntries)
            }
            else {
                return [nullable[uint32]]$null
            }
        } -SecondValue {
            param($value)
            if ($this.Type -eq 'File') {
                $buffer = [byte[]]::new(4)
                [void][System.Buffers.Binary.BinaryPrimitives]::WriteUInt32BigEndian($buffer, $value)
                $this.RawData.Size_NextDirIndex_NumEntries = $buffer
            }
        } -Force
        
        Update-TypeData -TypeName 'GCFSEntry' -MemberName 'NextDirIndex' -MemberType ScriptProperty -Value {
            if ($this.Type -eq 'Directory') {
                return [nullable[uint32]][System.Buffers.Binary.BinaryPrimitives]::ReadUInt32BigEndian($this.RawData.Size_NextDirIndex_NumEntries)
            }
            else {
                return [nullable[uint32]]$null
            }
        } -SecondValue {
            param($value)
            if ($this.Type -eq 'Directory') {
                $buffer = [byte[]]::new(4)
                [void][System.Buffers.Binary.BinaryPrimitives]::WriteUInt32BigEndian($buffer, $value)
                $this.RawData.Size_NextDirIndex_NumEntries = $buffer
            }
        } -Force
        
        Update-TypeData -TypeName 'GCFSEntry' -MemberName 'FullName' -MemberType ScriptProperty -Value {
            if ($this.Type -eq 'File') { return $this.ParentFile.FullName + $this.Path + $this.Name }
            else { return $this.ParentFile.FullName + $this.Path + $this.Name + '/' }
        } -Force
    }
    
    GCFSEntry() {
        $this.RawData = [GCFSEntryRaw]::new()
    }

    GCFSEntry([hashtable]$Properties) {
        foreach ($Property in $Properties.Keys) {
            $this.$Property = $Properties.$Property
        } 
        if ($null -eq $this.RawData) {
            $this.RawData = [GCFSEntryRaw]::new()
        }
    }

    GCFSEntry([Byte[]]$value) {
        $this.RawData = [GCFSEntryRaw]::new($value)
    }

    [string]ToString() {
        return $this.FullName
    }
}

class GCTGCHeader {

    [uint32] $OwnOffset
    [ValidateCount(0x4, 0x4)][byte[]] $TGCMagic
    [ValidateCount(0x4, 0x4)][byte[]] $Unknown1
    [uint32] $HeaderSize
    [uint32] $RelativeFSTOffset
    [uint32] $FSTOffset
    [uint32] $FSTSize
    [uint32] $FSTSizeMax
    [uint32] $MainExecutableOffset
    [uint32] $MainExecutableSize
    [uint32] $FileAreaOffset
    [ValidateCount(0x4, 0x4)][byte[]] $Unknown2
    [uint32] $BannerOffset
    [uint32] $BannerSize
    [uint32] $VirtualFileAreaOffset
    [int32] $TGCOffsetShift

    static GCTGCHeader() {
        Update-TypeData -TypeName 'GCTGCHeader' -MemberName 'FSTOffset' -MemberType ScriptProperty -Value {
            return [uint32]$this.OwnOffset + $this.RelativeFSTOffset
        } -Force

        Update-TypeData -TypeName 'GCTGCHeader' -MemberName 'TGCOffsetShift' -MemberType ScriptProperty -Value {
            return [int32](($this.FileAreaOffset - $this.VirtualFileAreaOffset) + $this.OwnOffset)
        } -Force
    }
   

    GCTGCHeader() {}

    GCTGCHeader([byte[]]$value) {
        $this.TGCMagic = $value[0x0000..0x0003]
        $this.Unknown1 = $value[0x0004..0x0007]
        $this.HeaderSize = [System.Buffers.Binary.BinaryPrimitives]::ReadUInt32BigEndian([byte[]]$value[0x0008..0x000b])
        $this.RelativeFSTOffset = [System.Buffers.Binary.BinaryPrimitives]::ReadUInt32BigEndian([byte[]]$value[0x0010..0x0013])
        $this.FSTSize = [System.Buffers.Binary.BinaryPrimitives]::ReadUInt32BigEndian([byte[]]$value[0x0014..0x0017])
        $this.FSTSizeMax = [System.Buffers.Binary.BinaryPrimitives]::ReadUInt32BigEndian([byte[]]$value[0x0018..0x001b])
        $this.MainExecutableOffset = [System.Buffers.Binary.BinaryPrimitives]::ReadUInt32BigEndian([byte[]]$value[0x001c..0x001f])
        $this.MainExecutableSize = [System.Buffers.Binary.BinaryPrimitives]::ReadUInt32BigEndian([byte[]]$value[0x0020..0x0023])
        $this.FileAreaOffset = [System.Buffers.Binary.BinaryPrimitives]::ReadUInt32BigEndian([byte[]]$value[0x0024..0x0027])
        $this.Unknown2 = $value[0x0028..0x002b]
        $this.BannerOffset = [System.Buffers.Binary.BinaryPrimitives]::ReadUInt32BigEndian([byte[]]$value[0x002c..0x002f])
        $this.BannerSize = [System.Buffers.Binary.BinaryPrimitives]::ReadUInt32BigEndian([byte[]]$value[0x0030..0x0033])
        $this.VirtualFileAreaOffset = [System.Buffers.Binary.BinaryPrimitives]::ReadUInt32BigEndian([byte[]]$value[0x0034..0x0037])
    }
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
        $buffer = [byte[]]::new(131072)
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

function Read-GCFST {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]                                  [System.IO.Stream] $Stream,
        [Parameter()]                                           [GCFSEntry] $ParentFile,
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)] [uint32] $FSTOffset,
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)] [uint32] $FSTSize,
        [Parameter(ValueFromPipelineByPropertyName)]            [int32] $TGCOffsetShift
        
    )
    begin {
        $buffer = [byte[]]::new(0x0C)
    }
    Process {
        [void]$Stream.seek($FSTOffset, 0)
        [void]$Stream.read($buffer, 0, 0xC)
        $root = [PSCustomObject]@{
            Type       = [FSTType]$buffer[0]
            EntryCount = [System.Buffers.Binary.BinaryPrimitives]::ReadUInt32BigEndian([byte[]]$buffer[8..11])
        }
        $lastFolder = 0
        $FST = & { for ($i = 1; $i -lt ($root.EntryCount); $i++) {
                [void]$Stream.read($buffer, 0, 0xC)
                if ([FSTType]$buffer[0] -eq 'Directory') {
                    $lastFolder = $i
                }
                $Entry = [GCFSEntry]$buffer
                $Entry.Index = $i
                $Entry.ParentFile = $ParentFile
                $Entry._ParentDirIndex = $lastFolder
                $Entry.TGCOffsetShift = $TGCOffsetShift
                $Entry
            } 
        }

        # 1st Pass: Getting the names from the String-Table
        # Funny enough "& {Process { }}"  is MUCH faster then "Foreach-Object { }" and does the same. 

        $StringTableSize = $FSTSize - ($FSTOffset - $Stream.Position)
        $FSTStringTable = [byte[]]::new($StringTableSize)
        [void]$Stream.read($FSTStringTable, 0, $FSTStringTable.Count)

        $FST | & { Process {

                $name = & {
                    $i = $_.NameOffsetIntoStringTable
                    while ($i -lt $FSTStringTable.Count) {
                        if ($FSTStringTable[$i] -ne 0) {
                            $FSTStringTable[$i]
                            $i++
                        }
                        else { break }
                    }
                }
                $_.Name = [System.Text.Encoding]::GetEncoding(932).GetString($name) 
                $_
                
           
            } } | Group-Object ParentDirIndex | & { Process {
                # 2nd Pass: Add Paths
                [System.Collections.ArrayList]$path = @('/')
                $parent = $_.Group[0]
                while ($parent.ParentDirIndex -ne 0) {
                    $parent = $FST[($parent.ParentDirIndex - 1)] # Avoid Where-Object here (slow!). Position in the FST matches the position in the array anyway (root would be [0], but is not in the array, so "-1").
                    $Path.insert(0, $parent.Name)
                    $Path.insert(0, '/')             
                }
                $_.Group.ForEach('Path', -join $Path)
                $_.Group  # ungroup things again
            } } | & { Process {
                # 3rd Pass: Read any TGC
                $_
                $_ |  & { Process {
                        
                        if ($_.Name -match '\.tgc$') {
                            $_ | Read-TGC $Stream
                        } 
                    } }
            } 
        }
    }    
} 

function Read-TGC {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]                          [System.IO.Stream] $Stream,
        [Parameter(ValueFromPipelineByPropertyName)]    [uint32] $FileOffset,
        [Parameter(ValueFromPipeline)]                  [GCFSEntry] $ParentFile
    )
    begin {
        $TGCMagic = [Byte[]]@(0xae, 0x0f, 0x38, 0xa2)
        $buffer = [byte[]]::new(0x38)
    }
    Process {
        [void]$Stream.seek($FileOffset, 0)
        [void]$Stream.read($buffer, 0, 0x38)
        if (!(Compare-object $buffer[0x0000..0x0003] $TGCMagic)) {
            $header = [GCTGCHeader]$buffer
            $header.OwnOffset = $FileOffset
            $header | Read-GCFST $Stream $ParentFile
        }
    }
}

if (!(Test-Path -LiteralPath $fileIn)) {
    Throw "File `"$fileIn`" not found!"
}

$Stream = [System.IO.File]::OpenRead($fileIn)

$buffer = [byte[]]::new(1088)

[void]$Stream.seek(0, 0)
[void]$Stream.read($buffer, 0, 1088)
0xc2339f3d
[GCDiskHeader]$Disc = $buffer
Write-Host $Disc.GameCode ' - ' $Disc.GameName

$list = $Disc | Read-GCFST $Stream | Where-Object Type -eq 'File' | Sort-Object FileOffset

if ($ListFiles) {
    switch ($ListFiles) {
        'Object' {
            Write-Output $list 
        }
        'json' {
            $list | Select-Object FileOffset, Size, Name, FullName | ConvertTo-Json | Out-File FileList.json
        }
        'Text' {
            ($list | Select-Object FileOffset, Size, Name, FullName | Format-Table | Out-String).Trim() | Out-File FileList.txt
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
                # Ocarina of Time
                if ($_.name -eq 'zlp_f.n64') {
                    Split-File $Stream (join-path $PSScriptRoot 'TLoZ-OoT-GC.z64') -start $_.FileOffset -size $_.Size
                }
                # Ocarina of Time - Master Quest
                elseif ($_.name -eq 'urazlp_f.n64') {
                    Split-File $Stream (join-path $PSScriptRoot 'TLoZ-OoT-MQ-GC.z64') -start $_.FileOffset -size $_.Size
                }
                
                # Majoras Mask
                elseif ($_.name -eq 'zelda2p.n64') {
                    Split-File $Stream (join-path $PSScriptRoot 'TLoZ-MM-GC.z64') -start $_.FileOffset -size $_.Size
                }
                 
            } }
    }
    else {
        Write-Host "Couldn't find any PAL OoT or MQ ROM."
    }
}

$Stream.Close()
Exit
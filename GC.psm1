<#
.NOTES
GameCube File System Classes v24.06.01
    
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

# SystemID and RegionCode are probably very incomplete, so they aren't really used.
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

# Just a little thing to not let me confuse those two.
enum FSEntryType {
    File = 0
    Directory = 1
}

class FileAlreadyExistsException :  System.IO.IOException {
    [string]$File
    FileAlreadyExistsException() : base('File already exists.') { }
    FileAlreadyExistsException([string]$File) : base("`"$($File)`" already exists.") {
        $this.File = $File
    }
}

Class GCBitConverter {
    static [uint32]ReadUInt32BigEndian([byte[]]$source) {       
        if ($source.count -ne 4) {
            Throw 'Source Byte Array must contain exact 4 bytes!'
        }
        [byte[]]$value = $source.Clone()
        if ([System.BitConverter]::IsLittleEndian) {
            [Array]::Reverse($value)
        }
        return [System.BitConverter]::ToUInt32($value, 0)
    }
    static [byte[]]WriteUInt32BigEndian([uint32]$source) {
        $value = [System.BitConverter]::GetBytes($source)
        if ([System.BitConverter]::IsLittleEndian) {
            [Array]::Reverse($value)
        }
        return $value
    }

    static [uint32]ReadUInt24BigEndian([byte[]]$source) {       
        if ($source.count -ne 3) {
            Throw 'Source Byte Array must contain exact 3 bytes!'
        }
        [Byte[]]$value = [byte[]]::new(1) + $source.Clone()
        if ([System.BitConverter]::IsLittleEndian) {
            [Array]::Reverse($value)
        }
        return [System.BitConverter]::ToUInt32($value, 0)
    }
    static [byte[]]WriteUInt24BigEndian([uint32]$source) {
        if ($source -gt 16777215) {
            Throw 'Source exceeds the maximum value of 16777215!'
        }
        $value = [System.BitConverter]::GetBytes($source)
        if ([System.BitConverter]::IsLittleEndian) {
            [Array]::Reverse($value)
        }
        return $value[1..3]
    }
}

class GameCode {
    [string] $SystemID
    [string] $GameID
    [string] $RegionCode

    GameCode() {

    }

    GameCode([hashtable]$Properties) {
        foreach ($Property in $Properties.Keys) {
            $this.$Property = $Properties.$Property
        }
    }

    GameCode([Byte[]]$value) {
        $this.SystemID = [System.Text.Encoding]::GetEncoding(932).GetString($value[0])
        $this.GameID = [System.Text.Encoding]::GetEncoding(932).GetString($value[1..2])
        $this.RegionCode = [System.Text.Encoding]::GetEncoding(932).GetString($value[3])
    }

    [string]ToString() {
        return $this.SystemID + $this.GameID + $this.RegionCode
    }
}

class DiscHeader {
    hidden [System.IO.Filestream] $FileStream
    [GameCode] $GameCode
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
    [uint32] $UserOffset
    [uint32] $UserSize
    [ValidateCount(0x4, 0x4)][byte[]] $Unknown3
    [ValidateCount(0x4, 0x4)][byte[]] $Unknown4

    DiscHeader([Byte[]]$value) {
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
        $this.DebugMonitorOffset = [GCBitConverter]::ReadUInt32BigEndian($value[0x0400..0x0403])
        $this.DebugMonitorAddress = [GCBitConverter]::ReadUInt32BigEndian($value[0x0404..0x0407])
        $this.Unknown2 = $value[0x0408..0x041f]
        $this.MainExecutableOffset = [GCBitConverter]::ReadUInt32BigEndian($value[0x0420..0x0423])
        $this.FSTOffset = [GCBitConverter]::ReadUInt32BigEndian($value[0x0424..0x0427])
        $this.FSTSize = [GCBitConverter]::ReadUInt32BigEndian($value[0x0428..0x042B])
        $this.FSTSizeMax = [GCBitConverter]::ReadUInt32BigEndian($value[0x042C..0x042F])
        $this.UserOffset = [GCBitConverter]::ReadUInt32BigEndian($value[0x0430..0x0433])
        $this.UserSize = [GCBitConverter]::ReadUInt32BigEndian($value[0x0434..0x0437])
        $this.Unknown3 = $value[0x0438..0x043b]
        $this.Unknown4 = $value[0x043c..0x043f]
    }

    DiscHeader() {
        $this.GameCode = [GameCode]::new()
    }

    DiscHeader([hashtable]$Properties) {
        foreach ($Property in $Properties.Keys) {
            $this.$Property = $Properties.$Property
        } 
        if ($null -eq $this.RawData) {
            $this.GameCode = [GameCode]::new()
        }
    }

    static [DiscHeader]Read([string]$File) {
        $Stream = [System.IO.File]::OpenRead($File)
        $Stream.Dispose()
        return [DiscHeader]::Read($Stream)
    }
    static [DiscHeader]Read([System.IO.FileInfo]$File) {
        $Stream = [System.IO.File]::OpenRead($File)
        $Stream.Dispose()
        return [DiscHeader]::Read($Stream)
    }

    static [DiscHeader]Read([System.IO.Filestream]$Stream) {
        $WasClosed = $false
        if (!$Stream.CanRead) {
            $WasClosed = $true
            $Stream = [System.IO.File]::OpenRead($Stream.Name)
        }
        $buffer = [byte[]]::new(1088)
        [void]$Stream.Seek(0, 0)
        [void]$Stream.Read($buffer, 0, 1088)
        $Magic = [byte[]]@(0xc2, 0x33, 0x9f, 0x3d)
        if ((Compare-Object $buffer[0x001c..0x001f] $Magic)) {
            Throw "This doesn't seem to be a GameCube Disc! Or wrong endianess for some ungodly reason."
        }
        $Disc = [DiscHeader]$buffer
        $Disc.FileStream = $Stream
        if ($WasClosed) {
            $Stream.Dispose()
        }
        return $Disc
    }

}

class TGCHeader {
    hidden [System.IO.Filestream] $FileStream
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


    TGCHeader() {}

    TGCHeader([byte[]]$value) {
        $this.TGCMagic = $value[0x0000..0x0003]
        $this.Unknown1 = $value[0x0004..0x0007]
        $this.HeaderSize = [GCBitConverter]::ReadUInt32BigEndian($value[0x0008..0x000b])
        $this.RelativeFSTOffset = [GCBitConverter]::ReadUInt32BigEndian($value[0x0010..0x0013])
        $this.FSTSize = [GCBitConverter]::ReadUInt32BigEndian($value[0x0014..0x0017])
        $this.FSTSizeMax = [GCBitConverter]::ReadUInt32BigEndian($value[0x0018..0x001b])
        $this.MainExecutableOffset = [GCBitConverter]::ReadUInt32BigEndian($value[0x001c..0x001f])
        $this.MainExecutableSize = [GCBitConverter]::ReadUInt32BigEndian($value[0x0020..0x0023])
        $this.FileAreaOffset = [GCBitConverter]::ReadUInt32BigEndian($value[0x0024..0x0027])
        $this.Unknown2 = $value[0x0028..0x002b]
        $this.BannerOffset = [GCBitConverter]::ReadUInt32BigEndian($value[0x002c..0x002f])
        $this.BannerSize = [GCBitConverter]::ReadUInt32BigEndian($value[0x0030..0x0033])
        $this.VirtualFileAreaOffset = [GCBitConverter]::ReadUInt32BigEndian($value[0x0034..0x0037])
    }

    static [TGCHeader]Read([System.IO.FileInfo]$File) {
        $Stream = [System.IO.File]::OpenRead($File)
        $Stream.Dispose()
        return [TGCHeader]::Read($Stream, 0)

    }

    static [TGCHeader]Read([FileEntry]$FSEntry) {
        return [TGCHeader]::Read($FSEntry.FileStream, $FSEntry.FileOffset)
    }
        
    static [TGCHeader]Read([System.IO.Filestream]$Stream, [uint32]$FileOffset) {
        $WasClosed = $false
        if (!$Stream.CanRead) {
            $WasClosed = $true
            $Stream = [System.IO.File]::OpenRead($Stream.Name)
        }

        $Magic = [Byte[]]@(0xae, 0x0f, 0x38, 0xa2)
        $buffer = [byte[]]::new(0x38)

        [void]$Stream.Seek($FileOffset, 0)
        [void]$Stream.Read($buffer, 0, 0x38)
        if ((Compare-Object $buffer[0x0000..0x0003] $Magic)) {
            Throw "This doesn't seem to be a TGC file! Or wrong endianess for some ungodly reason.`nIf you are sure this a valid file, this is probably missing a TGC header.`nPlease report the name of the ROM this is from and its hash here: https://github.com/Spodi/GCIE-PS/issues .`nDo NOT send or link the file/ROM!"
        }
        $header = [TGCHeader]$buffer
        $header.OwnOffset = $FileOffset
        $header.FileStream = $Stream

        if ($WasClosed) {
            $Stream.Dispose()
        }
        return $header
    }
}
Update-TypeData -TypeName 'TGCHeader' -MemberName 'FSTOffset' -MemberType ScriptProperty -Value {
    return [uint32]$this.OwnOffset + $this.RelativeFSTOffset
} -Force

Update-TypeData -TypeName 'TGCHeader' -MemberName 'TGCOffsetShift' -MemberType ScriptProperty -Value {
    return [int32](($this.FileAreaOffset - $this.VirtualFileAreaOffset) + $this.OwnOffset)
} -Force

class FSEntryRaw {
    [byte] $DirectoryFlag = 0
    [ValidateCount(0x3, 0x3)][byte[]] $NameOffsetIntoStringTable = [byte[]]::new(3)
    [ValidateCount(0x4, 0x4)][byte[]] $FileOffset_ParentDirIndex = [byte[]]::new(4)
    [ValidateCount(0x4, 0x4)][byte[]] $Size_NextDirIndex_NumEntries = [byte[]]::new(4)

    FSEntryRaw() {}

    FSEntryRaw([hashtable]$Properties) {
        foreach ($Property in $Properties.Keys) {
            $this.$Property = $Properties.$Property
        } 
    }

    FSEntryRaw([Byte[]]$value) {
        if ($value.count -ne 12) {
            throw 'Invalid length of byte array! Must be 12 bytes long.'
        }
        $this.DirectoryFlag = $value[0]
        $this.NameOffsetIntoStringTable = $value[1..3]
        $this.FileOffset_ParentDirIndex = $value[4..7]
        $this.Size_NextDirIndex_NumEntries = $value[8..11]
    }
}
class FSEntry {
    hidden [System.IO.Filestream] $FileStream
    [FSEntryType] $Type
    [uint32] $Index
    [FSEntry] $ParentFile  
    [string] $RelativePath
    [string] $Path
    [uint32] $NameOffsetIntoStringTable
    [string] $Name
    [string] $FullName
    [uint32] $ParentDirIndex
    [FSEntryRaw] $RawData


    [string]ToString() {
        return $this.FullName
    }
    static [FSEntry[]]Read([System.IO.Filestream]$Stream) {
        $Header = [DiscHeader]::Read($Stream)
        return [FSEntry]::Read($Stream, $Header.FSTOffset, $Header.FSTSize, $null, $null)
    }
    static [FSEntry[]]Read([System.IO.Filestream]$Stream, [TGCHeader]$Header) {
        return [FSEntry]::Read($Stream, $Header.FSTOffset, $Header.FSTSize, $Header.TGCOffsetShift, $null)
    }

    static [FSEntry[]]Read([DiscHeader]$Header) {
        return [FSEntry]::Read($Header.FileStream, $Header.FSTOffset, $Header.FSTSize, $null, $null)
    }

    static [FSEntry[]]Read([TGCHeader]$Header) {
        return [FSEntry]::Read($Header.FileStream, $Header.FSTOffset, $Header.FSTSize, $Header.TGCOffsetShift, $null)
    }

    static [FSEntry[]]Read([TGCHeader]$Header, [FileEntry]$ParentFile) {
        return [FSEntry]::Read($Header.FileStream, $Header.FSTOffset, $Header.FSTSize, $Header.TGCOffsetShift, $ParentFile)
    }

    static [FSEntry[]]Read([System.IO.Filestream]$Stream, [DiscHeader]$Header) {
        return [FSEntry]::Read($Stream, $Header.FSTOffset, $Header.FSTSize, $null, $null)
    }
    static [FSEntry[]]Read([System.IO.Filestream]$Stream, [TGCHeader]$Header, [FileEntry]$ParentFile) {
        return [FSEntry]::Read($Stream, $Header.FSTOffset, $Header.FSTSize, $Header.TGCOffsetShift, $ParentFile)
    }
    static [FSEntry[]]Read([System.IO.Filestream]$Stream, [uint32]$FSTOffset, [uint32]$FSTSize, [int32]$TGCOffsetShift, [FileEntry]$ParentFile) {
        $WasClosed = $false
        if (!$Stream.CanRead) {
            $WasClosed = $true
            $Stream = [System.IO.File]::OpenRead($Stream.Name)
        }
        
        $buffer = [byte[]]::new(0x0C)
        [void]$Stream.Seek($FSTOffset, 0)
        [void]$Stream.Read($buffer, 0, 0xC)
        $root = [RootEntry]$buffer
        $lastFolder = 0
        $FST = & { for ($i = 1; $i -lt ($root.EntryCount); $i++) {
                [void]$Stream.Read($buffer, 0, 0xC)
                if ([FSEntryType]$buffer[0] -eq 'Directory') {
                    $lastFolder = $i
                    $Entry = [DirectoryEntry]$buffer   
                }
                else {
                    $Entry = [FileEntry]$buffer
                    $Entry.ParentDirIndex = $lastFolder
                    $Entry.TGCOffsetShift = $TGCOffsetShift
                }
                $Entry.Index = $i
                $Entry.ParentFile = $ParentFile
                $Entry.FileStream = $Stream
                $Entry
            } 
        }

        # 1st Pass: Getting the names from the String-Table
        # Funny enough "& {Process { }}"  is MUCH faster then "Foreach-Object { }" and does the same. 

        $StringTableSize = $FSTSize - ($FSTOffset - $Stream.Position)
        $FSTStringTable = [byte[]]::new($StringTableSize)
        [void]$Stream.Read($FSTStringTable, 0, $FSTStringTable.Count)

        $FST = $FST | & { Process {

                $name = & {
                    $i = $_.NameOffsetIntoStringTable
                    while ($i -lt $FSTStringTable.Count -and $FSTStringTable[$i] -ne 0) {
                        $FSTStringTable[$i]
                        $i++
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
                $_.Group.ForEach('RelativePath', -join $Path)
                $_.Group  # ungroup things again
            } } | & { Process {
                # 3rd Pass: Read any TGC
                
                $_ | & { Process {
                        if ($_.Name -match '\.tgc$') {
                            [TGC]$_
                        }
                        else {
                            $_
                        }
                    } }
            } }
        if ($WasClosed) {
            $Stream.Dispose()
        }
        return $FST
    }

}
Update-TypeData -TypeName 'FSEntry' -MemberName 'Type' -MemberType ScriptProperty -Value {
    return [FSEntryType]$this.RawData.DirectoryFlag
} -SecondValue {
    param($value)
    $this.RawData.DirectoryFlag = [FSEntryType]$value
} -Force
Update-TypeData -TypeName 'FSEntry' -MemberName 'NameOffsetIntoStringTable' -MemberType ScriptProperty -Value {
    return [GCBitConverter]::ReadUInt24BigEndian($this.RawData.NameOffsetIntoStringTable)
} -SecondValue {
    param($value)
    $this.RawData.NameOffsetIntoStringTable = [GCBitConverter]::WriteUInt24BigEndian($value)
} -Force
Update-TypeData -TypeName 'FSEntry' -MemberName 'Path' -MemberType ScriptProperty -Value {
    return $this.ParentFile.FullName + $this.RelativePath
}
Update-TypeData -TypeName 'FSEntry' -DefaultDisplayPropertySet Type, FileOffset, Size, Path, Name

class RootEntry : FSEntry {
    [uint32] $EntryCount

    RootEntry() {}

    RootEntry([byte[]]$value) {
        # Why does the Profiler (Trace-Script) crash here?
        $this.RawData = [FSEntryRaw]::new($value)
    }

}
Update-TypeData -TypeName 'RootEntry' -MemberName 'EntryCount' -MemberType ScriptProperty -Value {
    return [uint32][GCBitConverter]::ReadUInt32BigEndian($this.RawData.Size_NextDirIndex_NumEntries)
} -SecondValue {
    param($value)
    $this.RawData.Size_NextDirIndex_NumEntries = [GCBitConverter]::WriteUInt32BigEndian($value)
} -Force

class FileEntry : FSEntry {
    [uint32] $FileOffset
    [int32] $TGCOffsetShift
    [uint32] $Size

    FileEntry() {}

    FileEntry([byte[]]$value) {
        $this.RawData = [FSEntryRaw]::new($value)
    }

    [void]WriteFile([String]$fileOut) {
        $this.WriteFile($fileOut, $true)
    }

    [void]WriteFile([String]$fileOut, [bool]$force) {
        $prevDir = [System.IO.Directory]::GetCurrentDirectory()
        [System.IO.Directory]::SetCurrentDirectory((Get-Location))
     
        if ((Test-Path -Path $fileOut -PathType Leaf)) {
            
            Throw [FileAlreadyExistsException]::new($fileOut)
        }
        $WasClosed = $false
        if (!$this.FileStream.CanRead) {
            $WasClosed = $true
            $this.FileStream = [System.IO.File]::OpenRead($this.FileStream.Name)
        }
        $destination = [System.IO.Path]::GetDirectoryName($fileOut)
        if ($destination) {
            if (!(Test-Path -LiteralPath $destination -PathType Container)) {
                New-Item $destination -ItemType Directory | Out-Null
            }
        }
        $write = [System.IO.File]::Open($fileOut, 'Create')
        $buffer = [byte[]]::new(131072)
        $BytesToRead = $this.Size
        [void]$this.FileStream.Seek($this.FileOffset, 0)
        while ($BytesToRead -gt 0) {
            if ($BytesToRead -lt $buffer.Count) {
                $n = $this.FileStream.Read($buffer, 0, $BytesToRead)
                [void]$write.Write($buffer, 0, $BytesToRead)
            }
            else {
                $n = $this.FileStream.Read($buffer, 0, $buffer.Count)
                [void]$write.Write($buffer, 0, $buffer.Count)
            }
            if ($n -eq 0) { break }
            $BytesToRead = $BytesToRead - $n
        }
        $write.Dispose()
        if ($WasClosed) {
            $this.FileStream.Dispose()
        }
        [System.IO.Directory]::SetCurrentDirectory($prevDir)
    }

}
Update-TypeData -TypeName 'FileEntry' -MemberName 'FileOffset' -MemberType ScriptProperty -Value {
    return [uint32]([GCBitConverter]::ReadUInt32BigEndian($this.RawData.FileOffset_ParentDirIndex) + $this.TGCOffsetShift)
} -SecondValue {
    param($value)
    $this.RawData.FileOffset_ParentDirIndex = [GCBitConverter]::WriteUInt32BigEndian(($value - $this.TGCOffsetShift))
} -Force
Update-TypeData -TypeName 'FileEntry' -MemberName 'Size' -MemberType ScriptProperty -Value {
    return [uint32][GCBitConverter]::ReadUInt32BigEndian($this.RawData.Size_NextDirIndex_NumEntries)
} -SecondValue {
    param($value)
    $this.RawData.Size_NextDirIndex_NumEntries = [GCBitConverter]::WriteUInt32BigEndian($value)
} -Force
Update-TypeData -TypeName 'FileEntry' -MemberName 'FullName' -MemberType ScriptProperty -Value {
    return $this.Path + $this.Name
} -Force

class DirectoryEntry : FSEntry {
    hidden [uint32] $NextDirIndex

    DirectoryEntry([byte[]]$value) {
        $this.RawData = [FSEntryRaw]::new($value)
    }
}
Update-TypeData -TypeName 'DirectoryEntry' -MemberName 'ParentDirIndex' -MemberType ScriptProperty -Value {
    return [GCBitConverter]::ReadUInt32BigEndian($this.RawData.FileOffset_ParentDirIndex)
} -SecondValue {
    param($value)
    $this.RawData.FileOffset_ParentDirIndex = [GCBitConverter]::WriteUInt32BigEndian($value)
} -Force
Update-TypeData -TypeName 'DirectoryEntry' -MemberName 'NextDirIndex' -MemberType ScriptProperty -Value {
    return [uint32][GCBitConverter]::ReadUInt32BigEndian($this.RawData.Size_NextDirIndex_NumEntries)
} -SecondValue {
    param($value)
    $this.RawData.Size_NextDirIndex_NumEntries = [GCBitConverter]::WriteUInt32BigEndian($value)
} -Force
Update-TypeData -TypeName 'DirectoryEntry' -MemberName 'FullName' -MemberType ScriptProperty -Value {
    return $this.Path + $this.Name + '/'
} -Force

class TGC : FileEntry {
    [TGCHeader] $Header
    [FSEntry[]] $Entries

    TGC([string]$File) {
        $this.Header = [TGCHeader]::read($file)
        $this.Entries = [FSEntry]::read($this.Header)
    }

    TGC([System.IO.FileInfo]$File) {
        $this.Header = [TGCHeader]::read($file)
        $this.Entries = [FSEntry]::read($this.Header)
    }

    TGC([TGCHeader]$Header) {
        $WasClosed = $false
        if (!$Header.FileStream.CanRead) {
            $WasClosed = $true
            $Header.FileStream = [System.IO.File]::OpenRead($Header.FileStream.Name)
        }

        $this.Header = $Header
        $this.Entries = [FSEntry]::read($this.Header)

        if ($WasClosed) {
            $this.FileStream.Dispose()
        }
    }

    TGC([FileEntry]$FSEntry) {
        $WasClosed = $false
        if (!$FSEntry.FileStream.CanRead) {
            $WasClosed = $true
            $FSEntry.FileStream = [System.IO.File]::OpenRead($FSEntry.FileStream.Name)
        }

        $this.Header = [TGCHeader]::read($FSEntry)
        foreach ($Property in ($FSEntry | Get-Member -MemberType Property)) {
            $this.($Property.Name) = $FSEntry.($Property.Name)
        }
        $this.Entries = [FSEntry]::read($this.Header, $FSEntry)

        if ($WasClosed) {
            $this.FileStream.Dispose()
        }
    }

    [FSEntry[]]GetAllEntries() {
        $Files = & {
            ForEach ($Entry in $this.Entries) {
                $Entry
                if ($Entry -is [TGC]) {
                    $Entry.GetAllEntries()
                }
            }
        }
        return $Files
    }
}

class Disc {
    [DiscHeader] $Header
    [FSEntry[]] $Entries

    Disc([string]$File) {
        $Stream = [System.IO.File]::OpenRead($File)
        $this.Header = [DiscHeader]::read($Stream)
        $this.Entries = [FSEntry]::read($this.Header)
        $Stream.Dispose()
    }

    Disc([System.IO.FileInfo]$File) {
        $Stream = [System.IO.File]::OpenRead($File)
        $this.Header = [DiscHeader]::read($Stream)
        $this.Entries = [FSEntry]::read($this.Header)
        $Stream.Dispose()
    }

    Disc([System.IO.FileStream]$Stream) {
        $WasClosed = $false
        if (!$Stream.CanRead) {
            $WasClosed = $true
            $Stream = [System.IO.File]::OpenRead($Stream)
        }

        $this.Header = [DiscHeader]::read($Stream)
        $this.Entries = [FSEntry]::read($this.Header)

        if ($WasClosed) {
            $Stream.Dispose()
        }
    }

    Disc([DiscHeader]$Header) {
        $WasClosed = $false
        if (!$Header.FileStream.CanRead) {
            $WasClosed = $true
            $Header.FileStream = [System.IO.File]::OpenRead($Header.FileStream.Name)
        }

        $this.Header = $Header
        $this.Entries = [FSEntry]::read($this.Header)

        if ($WasClosed) {
            $this.FileStream.Dispose()
        }
    }

    [FSEntry[]]GetAllEntries() {
        $Files = & {
            ForEach ($Entry in $this.Entries) {
                $Entry
                if ($Entry -is [TGC]) {
                    $Entry.GetAllEntries()
                }
            }
        }
        return $Files
    }
}

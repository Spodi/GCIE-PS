<#
.NOTES
GameCube File System Classes v24.02.29
    
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
        $this.DebugMonitorOffset = [System.Buffers.Binary.BinaryPrimitives]::ReadUInt32BigEndian([byte[]]$value[0x0400..0x0403])
        $this.DebugMonitorAddress = [System.Buffers.Binary.BinaryPrimitives]::ReadUInt32BigEndian([byte[]]$value[0x0404..0x0407])
        $this.Unknown2 = $value[0x0408..0x041f]
        $this.MainExecutableOffset = [System.Buffers.Binary.BinaryPrimitives]::ReadUInt32BigEndian([byte[]]$value[0x0420..0x0423])
        $this.FSTOffset = [System.Buffers.Binary.BinaryPrimitives]::ReadUInt32BigEndian([byte[]]$value[0x0424..0x0427])
        $this.FSTSize = [System.Buffers.Binary.BinaryPrimitives]::ReadUInt32BigEndian([byte[]]$value[0x0428..0x042B])
        $this.FSTSizeMax = [System.Buffers.Binary.BinaryPrimitives]::ReadUInt32BigEndian([byte[]]$value[0x042C..0x042F])
        $this.UserOffset = [System.Buffers.Binary.BinaryPrimitives]::ReadUInt32BigEndian([byte[]]$value[0x0430..0x0433])
        $this.UserSize = [System.Buffers.Binary.BinaryPrimitives]::ReadUInt32BigEndian([byte[]]$value[0x0434..0x0437])
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

    static [DiscHeader]Read([System.IO.Filestream]$Stream) {
        $buffer = [byte[]]::new(1088)
        [void]$Stream.seek(0, 0)
        [void]$Stream.read($buffer, 0, 1088)
        $Magic = [byte[]]@(0xc2, 0x33, 0x9f, 0x3d)
        if ((Compare-Object $buffer[0x001c..0x001f] $Magic)) {
            Throw "This doesn't seem to be a GameCube Disc! Or wrong endianess for some ungodly reason."
        }
        $Disc = [DiscHeader]$buffer
        $Disc.FileStream = $Stream
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

    static TGCHeader() {
        Update-TypeData -TypeName 'TGCHeader' -MemberName 'FSTOffset' -MemberType ScriptProperty -Value {
            return [uint32]$this.OwnOffset + $this.RelativeFSTOffset
        } -Force

        Update-TypeData -TypeName 'TGCHeader' -MemberName 'TGCOffsetShift' -MemberType ScriptProperty -Value {
            return [int32](($this.FileAreaOffset - $this.VirtualFileAreaOffset) + $this.OwnOffset)
        } -Force
    }
   

    TGCHeader() {}

    TGCHeader([byte[]]$value) {
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

    static [TGCHeader]Read([System.IO.Filestream]$Stream, [FSEntry]$TGC) {
        $Magic = [Byte[]]@(0xae, 0x0f, 0x38, 0xa2)
        $buffer = [byte[]]::new(0x38)


        [void]$Stream.seek($TGC.FileOffset, 0)
        [void]$Stream.read($buffer, 0, 0x38)
        if ((Compare-Object $buffer[0x0000..0x0003] $Magic)) {
            Throw "This doesn't seem to be a TGC file! Or wrong endianess for some ungodly reason.`nIf you are sure this a valid file, this is probably missing a TGC header.`nPlease report the name of the ROM this is from and its hash here: https://github.com/Spodi/GCIE-PS/issues .`nDo NOT send or link the file/ROM!"
        }
        $header = [TGCHeader]$buffer
        $header.OwnOffset = $TGC.FileOffset
        $header.FileStream = $Stream
        return $header
        

    }
}

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
    [uint32] $Index
    [FSEntry] $ParentFile
    [FSEntryType] $Type
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
    hidden [FSEntryRaw] $RawData

    static FSEntry() {
        Update-TypeData -TypeName 'FSEntry' -MemberName 'Type' -MemberType ScriptProperty -Value {
            return [FSEntryType]$this.RawData.DirectoryFlag
        } -SecondValue {
            param($value)
            $this.RawData.DirectoryFlag = [FSEntryType]$value
        } -Force
        
        Update-TypeData -TypeName 'FSEntry' -MemberName 'NameOffsetIntoStringTable' -MemberType ScriptProperty -Value {
            [byte[]]$value = [byte[]]::new(1) + $this.RawData.NameOffsetIntoStringTable
            return [System.Buffers.Binary.BinaryPrimitives]::ReadUInt32BigEndian($value)
        } -SecondValue {
            param($value)
            $buffer = [byte[]]::new(4)
            [void][System.Buffers.Binary.BinaryPrimitives]::WriteUInt32BigEndian($buffer, $value)
            $this.RawData.NameOffsetIntoStringTable = $buffer[1..3]
        } -Force
        
        Update-TypeData -TypeName 'FSEntry' -MemberName 'FileOffset' -MemberType ScriptProperty -Value {
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
        
        Update-TypeData -TypeName 'FSEntry' -MemberName 'ParentDirIndex' -MemberType ScriptProperty -Value {
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
        
        Update-TypeData -TypeName 'FSEntry' -MemberName 'Size' -MemberType ScriptProperty -Value {
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
        
        Update-TypeData -TypeName 'FSEntry' -MemberName 'NextDirIndex' -MemberType ScriptProperty -Value {
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
        
        Update-TypeData -TypeName 'FSEntry' -MemberName 'FullName' -MemberType ScriptProperty -Value {
            if ($this.Type -eq 'File') { return $this.ParentFile.FullName + $this.Path + $this.Name }
            else { return $this.ParentFile.FullName + $this.Path + $this.Name + '/' }
        } -Force
    }
    
    FSEntry() {
        $this.RawData = [FSEntryRaw]::new()
    }

    FSEntry([hashtable]$Properties) {
        foreach ($Property in $Properties.Keys) {
            $this.$Property = $Properties.$Property
        } 
        if ($null -eq $this.RawData) {
            $this.RawData = [FSEntryRaw]::new()
        }
    }

    FSEntry([Byte[]]$value) {
        $this.RawData = [FSEntryRaw]::new($value)
    }

    [string]ToString() {
        return $this.FullName
    }

    static [FSEntry[]]Read([System.IO.Filestream]$Stream) {
        $Header = [DiscHeader]::Read($Stream)
        return [FSEntry]::Read($Stream, $Header, $null)
    }

    static [FSEntry[]]Read([System.IO.Filestream]$Stream, [TGCHeader]$Header) {
        return [FSEntry]::Read($Stream, $Header, $null)
    }

    static [FSEntry[]]Read([DiscHeader]$Header) {
        return [FSEntry]::Read($Header.FileStream, $Header)
    }

    static [FSEntry[]]Read([TGCHeader]$Header) {
        return [FSEntry]::Read($Header.FileStream, $Header, $null)
    }

    static [FSEntry[]]Read([TGCHeader]$Header, [FSEntry]$ParentFile) {
        return [FSEntry]::Read($Header.FileStream, $Header, $ParentFile)
    }

    static [FSEntry[]]Read([System.IO.Filestream]$Stream, [DiscHeader]$Header) {

        $buffer = [byte[]]::new(0x0C)
        [void]$Stream.seek($header.FSTOffset, 0)
        [void]$Stream.read($buffer, 0, 0xC)
        $root = [PSCustomObject]@{
            Type       = [FSEntryType]$buffer[0]
            EntryCount = [System.Buffers.Binary.BinaryPrimitives]::ReadUInt32BigEndian([byte[]]$buffer[8..11])
        }
        $lastFolder = 0
        $FST = & { for ($i = 1; $i -lt ($root.EntryCount); $i++) {
                [void]$Stream.read($buffer, 0, 0xC)
                if ([FSEntryType]$buffer[0] -eq 'Directory') {
                    $lastFolder = $i
                }
                $Entry = [FSEntry]$buffer
                $Entry.Index = $i
                $Entry._ParentDirIndex = $lastFolder
                $Entry.TGCOffsetShift = $TGCOffsetShift
                $Entry.FileStream = $Stream
                $Entry
            } 
        }

        # 1st Pass: Getting the names from the String-Table
        # Funny enough "& {Process { }}"  is MUCH faster then "Foreach-Object { }" and does the same. 

        $StringTableSize = $header.FSTSize - ($header.FSTOffset - $Stream.Position)
        $FSTStringTable = [byte[]]::new($StringTableSize)
        [void]$Stream.read($FSTStringTable, 0, $FSTStringTable.Count)

        $FST = $FST | & { Process {

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
                $_ | & { Process {
                        if ($_.Name -match '\.tgc$') {
                            $header = [TGCHeader]::Read($Stream, $_)
                            [FSEntry]::Read($Stream, $header, $_)
                        } 
                    } }
            } }
        return [FSEntry[]]$FST
    }

    static [FSEntry[]]Read([System.IO.Filestream]$Stream, [TGCHeader]$Header, [FSEntry]$ParentFile) {
        $buffer = [byte[]]::new(0x0C)
        [void]$Stream.seek($header.FSTOffset, 0)
        [void]$Stream.read($buffer, 0, 0xC)
        $root = [PSCustomObject]@{
            Type       = [FSEntryType]$buffer[0]
            EntryCount = [System.Buffers.Binary.BinaryPrimitives]::ReadUInt32BigEndian([byte[]]$buffer[8..11])
        }
        $lastFolder = 0
        $FST = & { for ($i = 1; $i -lt ($root.EntryCount); $i++) {
                [void]$Stream.read($buffer, 0, 0xC)
                if ([FSEntryType]$buffer[0] -eq 'Directory') {
                    $lastFolder = $i
                }
                $Entry = [FSEntry]$buffer
                $Entry.Index = $i
                $Entry.ParentFile = $ParentFile
                $Entry._ParentDirIndex = $lastFolder
                $Entry.TGCOffsetShift = $TGCOffsetShift
                $Entry.FileStream = $Stream
                $Entry
            } 
        }

        # 1st Pass: Getting the names from the String-Table
        # Funny enough "& {Process { }}"  is MUCH faster then "Foreach-Object { }" and does the same. 

        $StringTableSize = $header.FSTSize - ($header.FSTOffset - $Stream.Position)
        $FSTStringTable = [byte[]]::new($StringTableSize)
        [void]$Stream.read($FSTStringTable, 0, $FSTStringTable.Count)

        $FST = $FST | & { Process {

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
                $_ | & { Process {
                        if ($_.Name -match '\.tgc$') {
                            $header = [TGCHeader]::Read($Stream, $_)
                            [FSEntry]::Read($Stream, $header, $_)
                        } 
                    } }
            } }
        return [FSEntry[]]$FST
    }

    [void]WriteFile([String]$fileOut) {
        if ($this.Type -eq 'Directory') {
            Throw 'This is a directory. This class only supports extracting files!'
        }
        $prevDir = [System.IO.Directory]::GetCurrentDirectory()
        [System.IO.Directory]::SetCurrentDirectory((Get-Location))

        if (Test-Path -Path $fileOut -PathType Leaf) {
            Throw "$fileOut already exists."
        }
        $destination = [System.IO.Path]::GetDirectoryName($fileOut)
        if ($destination) {
            if (!(Test-Path -LiteralPath $destination -PathType Container)) {
                New-Item $destination -ItemType Directory | Out-Null
            }
        }
        $read = $this.FileStream
        $write = [System.IO.File]::OpenWrite($fileOut)
        $buffer = [byte[]]::new(131072)
        $BytesToRead = $this.size
        [void]$read.seek($this.FileOffset, 0)
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
        $write.Dispose()
        [System.IO.Directory]::SetCurrentDirectory($prevDir)
    }

}

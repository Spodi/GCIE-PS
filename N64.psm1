<#
.NOTES
N64 Header Classes v24.06.01
    
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

# SystemIDs are probably very incomplete. Please report if it crashes cause of that.
enum SystemID {
    GamePak = 0x4e #N
    DDDisk = 0x44 #D
    GamePakPart = 0x43 #C
    DDDiskPart = 0x45 #E
    Aleck64GamePak = 0x5a #Z
}

enum RegionCode {
    All = 0x41 #A
    Brazil = 0x42 #B
    China = 0x43 #C
    Germany = 0x44 #D
    NorthAmerica = 0x45 #E
    France = 0x46 #F
    Gateway_NTSC = 0x47 #G
    Unknown_H = 0x48 #H
    Italy = 0x49 #I
    Japan = 0x4a #J
    Korea = 0x4b #K
    Gateway_PAL = 0x4c #L
    Unknown_M = 0x4d #M
    Canada = 0x4e #N
    Unknown_O = 0x4f #O
    Europe_P = 0x50 #P
    Unknown_Q = 0x51 #Q
    Unknown_R = 0x52 #R
    Spain = 0x53 #S
    Unknown_T = 0x54 #T
    Australia = 0x55 #U
    Unknown_V = 0x56 #V
    Scandinavia = 0x57 #W
    Europe_X = 0x58 #X
    Europe_Y = 0x59 #Y
    Europe_Z = 0x5a #Z
}

Class N64BitConverter {
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

    static [uint32]ReadUInt64BigEndian([byte[]]$source) {       
        if ($source.count -ne 8) {
            Throw 'Source Byte Array must contain exact 8 bytes!'
        }
        [Byte[]]$value = [byte[]]::new(1) + $source.Clone()
        if ([System.BitConverter]::IsLittleEndian) {
            [Array]::Reverse($value)
        }
        return [System.BitConverter]::ToUInt32($value, 0)
    }
    static [byte[]]WriteUInt64BigEndian([uint32]$source) {
        if ($source -gt 18446744073709551615) {
            Throw 'Source exceeds the maximum value of 18446744073709551615!'
        }
        $value = [System.BitConverter]::GetBytes($source)
        if ([System.BitConverter]::IsLittleEndian) {
            [Array]::Reverse($value)
        }
        return $value
    }
}

class GameCode {
    [SystemID] $SystemID
    [string] $GameID
    [RegionCode] $RegionCode

    GameCode() {

    }

    GameCode([hashtable]$Properties) {
        foreach ($Property in $Properties.Keys) {
            $this.$Property = $Properties.$Property
        }
    }

    GameCode([Byte[]]$value) {
        $this.SystemID = $value[0]
        $this.GameID = [System.Text.Encoding]::GetEncoding(932).GetString($value[1..2])
        $this.RegionCode = $value[3]
    }

    [string]ToString() {
        return [System.Text.Encoding]::GetEncoding(932).GetString($this.SystemID) + $this.GameID + [System.Text.Encoding]::GetEncoding(932).GetString($this.RegionCode)
    }
}

class LibultraVersion {
    [ValidateCount(0x2, 0x2)][byte[]] $Patch
    [Version] $Version
    [string] $Revision

    LibultraVersion([Byte[]]$value) {
        $this.Patch = $value[0x0..0x1]
        $this.Version = [version]::new("$([Math]::Truncate($value[0x2] / 10)).$($value[0x2] / 10 - [Math]::Truncate($value[0x2] / 10))")
        $this.Revision = [System.Text.Encoding]::GetEncoding(932).GetString($value[0x3])
    }

    [string]ToString() {
        return $this.Version.ToString() + $this.Revision
    }
}

class RomHeader {
    hidden [System.IO.Filestream] $FileStream
    [ValidateCount(0x4, 0x4)][byte[]] $PI_BSD_DOM1_Configuration_Flags # Should be 0x80371240 for official ROMs. This is NOT an indicator for endianess, but flags for the max read speed on the catridge!
    hidden [uint32] $RawClockRate
    [uint32] $ClockRate # Should be 0 except for a few selected ROMs.
    [uint32] $BootAdress
    [LibultraVersion] $LibultraVersion
    [uint64] $CheckCode
    [ValidateCount(0x8, 0x8)][byte[]] $Unknown1
    [string] $GameName
    [ValidateCount(0x7, 0x7)][byte[]] $HombrewConfig
    [GameCode] $GameCode
    [byte] $Version

    RomHeader([Byte[]]$value) {
        if ($value.count -ne 0x003F) {
            throw 'Invalid length of byte array! Must be 0x003F bytes long.'
        }
        $this.PI_BSD_DOM1_Configuration_Flags = $value[0x0000..0x0003]
        $this.RawClockRate = [N64BitConverter]::ReadUInt32BigEndian($value[0x0004..0x0007])
        $this.BootAdress = [N64BitConverter]::ReadUInt32BigEndian($value[0x0008..0x000b])
        $this.LibultraVersion = [byte[]]$value[0x000c..0x000f]
        $this.CheckCode = [N64BitConverter]::ReadUInt64BigEndian($value[0x0010..0x0017])
        $this.Unknown1 = $value[0x0018..0x001f]
        $this.GameName = [System.Text.Encoding]::GetEncoding(932).GetString($value[0x0020..0x0033]).Trim([char]0).Trim()
        $this.HombrewConfig = $value[0x0034..0x003a]
        $this.GameCode = [byte[]]$value[0x003b..0x003e]
        $this.Version = $value[0x003F]
    }

    RomHeader() {
        $this.GameCode = [GameCode]::new()
        $this.GameCode = [LibultraVersion]::new()
    }

    [string]ToString() {
        return "$($this.GameCode) - $($this.GameName)"
    }

    static [RomHeader]Read([string]$File) {
        $Stream = [System.IO.File]::OpenRead($File)
        $Stream.Dispose()
        return [RomHeader]::Read($Stream)
    }
    static [RomHeader]Read([System.IO.FileInfo]$File) {
        $Stream = [System.IO.File]::OpenRead($File)
        $Stream.Dispose()
        return [RomHeader]::Read($Stream)
    }

    static [RomHeader]Read([System.IO.Filestream]$Stream) {
        $WasClosed = $false
        if (!$Stream.CanRead) {
            $WasClosed = $true
            $Stream = [System.IO.File]::OpenRead($Stream.Name)
        }
        $buffer = [byte[]]::new(0x3F)
        [void]$Stream.Seek(0, 0)
        [void]$Stream.Read($buffer, 0, 0x3F)

        $Disc = [RomHeader]$buffer
        $Disc.FileStream = $Stream
        if ($WasClosed) {
            $Stream.Dispose()
        }
        return $Disc
    }

}
Update-TypeData -TypeName 'RomHeader' -MemberName 'ClockRate' -MemberType ScriptProperty -Value {
    return ($this.RawClockRate -band 0xFFFFFFF0) * 0.75
} -SecondValue {
    param($value)
    $this.RawClockRate = $value / 0.75 -bor -bnot 0xFFFFFFF0
} -Force

# GameCube Image Extractor Script for PowerShell
## DESCRIPTION
Extracts or lists files from an uncompressed GameCube image (uncompressed gcm/iso). As this was originally written for "Harbor Masters 64" ports, it tries to extract a PAL OoT, PAL MQ or NTSC-U MM ROM by default. But it can also be used to extract any raw file from the gcm/iso by name or just list its file system.

Requires you to install .NET and Powershell on MacOS and Linux (untested, but should work).

> [!TIP]
> Instead of starting the script the usual way, you can also Drag & Drop your rom on the included batch file to kickstart the automatic extraction.

There is also a C# port of this ported by xoascf (aka Amaro): https://github.com/xoascf/GCIE

## PARAMETER
### -fileIn <String\>
**[MANDATORY]**\
GameCube image file to extract or list files from (uncompressed gcm/iso).

### -Extract <String\>
Extracts all files where their full name (path + name) matches this Regular Expression.

### -ListFiles <String\>
Lists all files in the image. "Object" sends the file infos as objects to the pipeline. "Text" and "Json" saves the infos as "FileList.txt" or "FileList.json".


## SYNTAX
```
C:\Users\Spodi\Documents\GitHub\GCIE-PS\Extract_OoT.ps1 [-fileIn] <String>
C:\Users\Spodi\Documents\GitHub\GCIE-PS\Extract_OoT.ps1 [-fileIn] <String> [-ListFiles] <String>
C:\Users\Spodi\Documents\GitHub\GCIE-PS\Extract_OoT.ps1 [-fileIn] <String> [-Extract] <String>
```
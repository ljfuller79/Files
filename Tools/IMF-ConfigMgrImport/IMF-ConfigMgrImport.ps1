<#
.SYNOPSIS
    Import OS image files to ConfigMgr and create a validation task sequence
.DESCRIPTION
    Import OS image files to ConfigMgr and create a validation task sequence
.EXAMPLE
    New-IMFOSimport.ps1
.NOTES
        ScriptName: New-IMFOSimport
        Author:     Mikael Nystrom
        Twitter:    @mikael_nystrom
        Email:      mikael.nystrom@truesec.se
        Blog:       https://deploymentbunny.com

    Version History
    1.0.0 - Script created [01/16/2019 13:12:16]

Copyright (c) 2019 Mikael Nystrom

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

Param(
    $SourceFileFolder = "D:\MDTBuildLabold\Captures",
    $DestinationFolder = "\\cm01.corp.viamonstra.com\e$\Sources\OSD\OS Images",
    $ConfigMgrServerName = "cm01.corp.viamonstra.com",
    $CMOSFolderPath = ".\OperatingSystemImage\Validation",
    $CMTSFolderPath = ".\TaskSequence\Validation",
    $BootImageName = 'Zero Touch WinPE 10 x64',
    $ClientPackageName = 'Configuration Manager Client Package'
)

$Items = Get-ChildItem -Path $SourceFileFolder -Filter *.wim
foreach($SourceFile in $Items)
{
    <#
    $Credentials = New-Object System.Management.Automation.PSCredential -ArgumentList "VIAMONSTRA\Administrator", ("P@ssw0rd" | ConvertTo-SecureString -AsPlainText -Force)
    net use \\$ConfigMgrServerName\e$ P@ssw0rd /u:viamonstra\administrator
    $session = New-PSSession -ComputerName $ConfigMgrServerName -Credential $Credentials
    #>

    #Connect to CM
    $Session = New-PSSession -ComputerName $ConfigMgrServerName -ErrorAction Stop

    #Check if folder exists
    if(!(Test-Path -Path "$DestinationFolder")){Write-Error "Unable to access $DestinationFolder";exit}

    #Check file exists
    if(!(Test-Path -Path "$SourceFile")){Write-Error "Unable to access $DestinationFolder";exit}

    #Set name
    $item = Get-Item -Path "$SourceFile"
    $OSFolderName = $item.BaseName + "_" + ($item.LastAccessTimeUtc).ToString("yyyyMMddHHmmss")

    #Test if destination folder exists
    if(Test-Path -Path "$DestinationFolder\$OSFolderName"){Write-Error "$DestinationFolder\$OSFolderName already exists"}

    #Create folder
    Try
    {
        $result = New-Item -Path "$DestinationFolder\$OSFolderName" -ItemType Directory -Force

    }
    catch
    {
        exit
    }

    #Copy File
    Try
    {
        $result = Copy-Item -Path $SourceFile -Destination $result.FullName -PassThru

    }
    catch
    {
        exit
    }


    #Import-OS
    $ScriptBlock = 
    {
        #Import Module
        Import-Module "$env:SMS_ADMIN_UI_PATH\..\configurationmanager.psd1" -Force -ErrorAction Stop
        Set-Location -Path C:

        #Get WIM info    
        $WimFile = $using:result
        $WimInfo = Get-WindowsImage -ImagePath $WimFile -ErrorAction Stop
    
        #Switch to PSDrive
        $SiteCode = Get-PSDrive -PSProvider CMSITE
        Push-Location "$($SiteCode.Name):\"

        #Import OS
        $NewCMOperatingSystemImage = New-CMOperatingSystemImage -Name $Using:OSFolderName -Path $WimFile.FullName -Description $WimFile.BaseName -Verbose

        #Move object
        Move-CMObject -FolderPath $Using:CMOSFolderPath -InputObject $NewCMOperatingSystemImage

        Return $NewCMOperatingSystemImage

    }
    $ReturnFromImportOS = Invoke-Command -Session $Session -ScriptBlock $ScriptBlock
    $ReturnFromImportOS

    #Check file exists
    if(!(Test-Path -Path $($ReturnFromImportOS.PkgSourcePath))){Write-Error "Unable to access $DestinationFolder";break}

    #Create validation TS
    $ScriptBlock = 
    {
        #Import Module
        Import-Module "$env:SMS_ADMIN_UI_PATH\..\configurationmanager.psd1" -Force -ErrorAction Stop
        Set-Location -Path C:

        #Switch to PSDrive
        $SiteCode = Get-PSDrive -PSProvider CMSITE
        Push-Location "$($SiteCode.Name):\"

        #Create new Test TS
        $OSImage = $Using:ReturnFromImportOS
        $BootImageID = (Get-CMBootImage -Name $Using:BootImageName).PackageID
        $OSImageID = $OSImage.PackageID
        $ClientPackageID = (Get-CMPackage -Name $Using:ClientPackageName).PackageID
        $CMTaskSequence = New-CMTaskSequence -InstallOperatingSystemImageOption `
            -TaskSequenceName "IMF Validate -  $($OSImage.Name)" `
            -BootImagePackageId $BootImageID `
            -OperatingSystemImagePackageId $OSImageID `
            -OperatingSystemImageIndex '1' `
            -ClientPackagePackageId $ClientPackageID `
            -JoinDomain WORKGROUP `
            -WorkgroupName WORKGROUP `
            -PartitionAndFormatTarget $true `
            -LocalAdminPassword (ConvertTo-SecureString "P@ssw0rd" -AsPlainText -Force)
    
        #Move object
        Move-CMObject -FolderPath $Using:CMTSFolderPath -InputObject $CMTaskSequence
    
        Return $CMTaskSequence

    }
    $ReturnFromCreatevalidationTS = Invoke-Command -Session $Session -ScriptBlock $ScriptBlock
    $ReturnFromCreatevalidationTS
}

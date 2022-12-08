<#
    .DESCRIPTION
        Bootstrap and build script for PowerShell module CI/CD pipeline

    .PARAMETER Tasks
        The task or tasks to run. The default value is '.' (runs the default task).

    .PARAMETER ResolveDependency
        Not yet written.

#>
[CmdletBinding()]
param
(
    [Parameter(Position = 0)]
    [String[]]
    $Tasks = '.',

    [Parameter()]
    [Switch]
    $ResolveDependency
)

function DebugTaskVariables
{
    Write-Build Magenta (Get-ChildItem env: | Out-String)
    Write-Build Cyan (Get-Variable | Out-String)
    Write-Build Yellow ($BuildInfo | Out-String)
}

# Push location
Write-Host -Object '[pre-build] Starting Build Init' -ForegroundColor Green
Push-Location $PSScriptRoot -StackName 'BuildModule'

# Define outputdirectory
$OutputDirectory = Join-Path -Path $PSScriptRoot -ChildPath 'output'

# Define required modules directory
$RequiredModulesDirectory = Join-Path -Path $OutputDirectory 'requiredmodules'
if (-not (Test-Path $RequiredModulesDirectory))
{
    New-Item -ItemType Directory -Force -Path $RequiredModulesDirectory
}

$powerShellModulePaths = $env:PSModulePath -split [System.IO.Path]::PathSeparator

# Pre-pending $requiredModulesPath folder to PSModulePath to resolve from this folder FIRST.
if ( $powerShellModulePaths -notcontains $RequiredModulesDirectory )
{
    Write-Host -Object "[pre-build] Pre-pending '$RequiredModulesDirectory' folder to PSModulePath" -ForegroundColor Green

    $env:PSModulePath = $RequiredModulesDirectory + [System.IO.Path]::PathSeparator + $env:PSModulePath
}

$powerShellYamlModule = Get-Module -Name 'powershell-yaml' -ListAvailable
$invokeBuildModule = Get-Module -Name 'InvokeBuild' -ListAvailable
$psDependModule = Get-Module -Name 'PSDepend' -ListAvailable

# Checking if the user should -ResolveDependency.
if (-not ($powerShellYamlModule -and $invokeBuildModule -and $psDependModule) -and -not $ResolveDependency)
{
    $ResolveDependency = $true
    if ($AutoRestore -or -not $PSBoundParameters.ContainsKey('Tasks') -or $Tasks -contains 'build')
    {
        Write-Host -Object "[pre-build] Dependency missing, getting dependencies before building `r`n" -ForegroundColor Yellow
    }
}

if ($ResolveDependency)
{
    Write-Host -Object '[pre-build] Resolving dependencies.' -ForegroundColor Green

    if ($PSVersionTable.PSVersion.Major -le 5)
    {
        if (-not (Get-Command -Name 'Import-PowerShellDataFile' -ErrorAction 'SilentlyContinue'))
        {
            Import-Module -Name Microsoft.PowerShell.Utility -RequiredVersion '3.1.0.0'
        }

        <#
                Making sure the imported PackageManagement module is not from PS7 module
                path. The VSCode PS extension is changing the $env:PSModulePath and
                prioritize the PS7 path. This is an issue with PowerShellGet because
                it loads an old version if available (or fail to load latest).
                #>
        Get-Module -ListAvailable PackageManagement | Where-Object -Property 'ModuleBase' -NotMatch 'powershell.7' | Select-Object -First 1 | Import-Module -Force
    }

    #
    # Assert Nuget package provider
    #

    Write-Host '[bootstrap] Verifying Nuget as package source' -ForegroundColor Cyan

    $powerShellGetModule = Import-Module -Name 'PowerShellGet' -MinimumVersion '2.0' -MaximumVersion '2.9' -ErrorAction 'SilentlyContinue' -PassThru
    $nuGetProvider = Get-PackageProvider -Name 'NuGet' -ListAvailable | Select-Object -First 1

    if (-not $powerShellGetModule -and -not $nuGetProvider)
    {
        Write-Information -MessageData 'Bootstrap: Installing NuGet Package Provider from the web (Make sure Microsoft addresses/ranges are allowed).'
        $null = Install-PackageProvider -Name 'nuget' -Force -ForceBootstrap -ErrorAction Stop -Scope Currentuser
        $nuGetProvider = Get-PackageProvider -Name 'NuGet' -ListAvailable | Select-Object -First 1
        $nuGetProviderVersion = $nuGetProvider.Version.ToString()
        Write-Information -MessageData "Bootstrap: Importing NuGet Package Provider version $nuGetProviderVersion to current session."
        $Null = Import-PackageProvider -Name 'NuGet' -RequiredVersion $nuGetProviderVersion -Force
    }

    #
    # Assert PSGallery Trusted
    #

    Write-Host '[bootstrap] Ensuring PSGallery is trusted' -ForegroundColor Cyan

    $InstallationPolicy = (Get-PSRepository -Name 'PSGallery' -ErrorAction 'Stop').InstallationPolicy

    if ($InstallationPolicy -ne 'Trusted')
    {
        Set-PSRepository -Name 'PSGallery' -InstallationPolicy 'Trusted' -ErrorAction 'Ignore'
        Write-Host '[bootstrap] Configured PSGallery as trusted' -ForegroundColor Cyan
    }

    #
    # Assert PowershellGet
    #

    Write-Host '[bootstrap] Verifying Powershell module PowershellGet' -ForegroundColor Cyan
    $powerShellGetVersion = (Import-Module -Name 'PowerShellGet' -MinimumVersion '2.0' -MaximumVersion '2.9' -PassThru -ErrorAction 'SilentlyContinue').Version
    Write-Verbose -Message "Bootstrap: The PowerShellGet version is $powerShellGetVersion"

    if (-not $powerShellGetVersion -or ($powerShellGetVersion -lt [System.Version] '2.0'))
    {
        Write-Host '[bootstrap] Installing newer version of PowershellGet' -ForegroundColor Cyan

        Install-Module -Name 'PowershellGet' -Force -SkipPublisherCheck -AllowClobber -Scope CurrentUser -Repository PSGallery

        Remove-Module -Name 'PowerShellGet' -Force -ErrorAction 'SilentlyContinue'
        Remove-Module -Name 'PackageManagement' -Force

        $powerShellGetModule = Import-Module PowerShellGet -Force -PassThru

        $powerShellGetVersion = $powerShellGetModule.Version.ToString()

        Write-Verbose -Message "Bootstrap: PowerShellGet version loaded is $powerShellGetVersion"
    }

    #
    # Assert PSDepend
    #

    Write-Host '[bootstrap] Verifying Powershell module PSDepend' -ForegroundColor Cyan
    if (-not (Get-Module -Name 'PSDepend' -ListAvailable))
    {
        Write-Host "[bootstrap] Saving & Importing PSDepend from PSGallery to $RequiredModulesDirectory" -ForegroundColor Cyan
        Save-Module -Name 'PSDepend' -Repository 'PSGallery' -Path $RequiredModulesDirectory -Force
    }

    Write-Host '[bootstrap] Loading Powershell module PSDepend' -ForegroundColor Cyan
    $null = Import-Module -Name PSDepend -ErrorAction Stop -Force

    #
    # Assert Powershell-Yaml
    #

    Write-Host '[bootstrap] Verifying Powershell module Powershell-Yaml' -ForegroundColor Cyan
    if (-not (Get-Module -Name 'PowerShell-Yaml' -ListAvailable ))
    {
        Write-Host '[bootstrap] Installing Powershell module Powershell-Yaml' -ForegroundColor Cyan
        Write-Verbose -Message "PowerShell-Yaml module not found. Attempting to Save from Gallery '$Gallery' to '$PSDependTarget'."
        Save-Module -Name 'PowerShell-Yaml' -Repository PSGallery -Path $RequiredModulesDirectory -Force
    }
    else
    {
        Write-Verbose 'PowerShell-Yaml is already available'
    }

    #
    # Run PSDepend
    #

    Write-Host '[bootstrap] Invoke PSDepend' -ForegroundColor Cyan

    $resolveDependencyConfigPath = Join-Path -Path $PSScriptRoot -ChildPath '.\required.depend.psd1' -Resolve -ErrorAction 'Stop'
    Invoke-PSDepend -Path $resolveDependencyConfigPath -Confirm:$false

    Write-Host '[bootstrap] Dependencies restored' -ForegroundColor Cyan

    Write-Host '[bootstrap] Bootstrap complete' -ForegroundColor Cyan

}

#
# Invoke Build
#

Invoke-Build -Task $Tasks -File "$PSScriptRoot\build.invoke.ps1"

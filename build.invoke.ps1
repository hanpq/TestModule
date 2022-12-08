
# Locating build config
$BuildConfig = Get-ChildItem -Path "$PSScriptRoot\*" -Include 'build.y*ml'

Write-Host -Object "[build] Loading Configuration from $BuildConfig"

Import-Module -Name 'powershell-yaml' -ErrorAction Stop
$BuildInfo = ConvertFrom-Yaml -Yaml (Get-Content -Raw $BuildConfig)

#
# Set task header
#

if ($BuildInfo.TaskHeader)
{
    Set-BuildHeader -Script ([scriptblock]::Create($BuildInfo.TaskHeader))
}

#
# Define Module output directory
#

# Pre-pending $BuildModuleOutput folder to PSModulePath to resolve built module from this folder.
if ($powerShellModulePaths -notcontains $OutputDirectory)
{
    Write-Host -Object "[build] Pre-pending '$BuildModuleOutput' folder to PSModulePath" -ForegroundColor Green

    $env:PSModulePath = $OutputDirectory + [System.IO.Path]::PathSeparator + $env:PSModulePath
}


Write-Host -Object '[build] Parsing defined tasks' -ForegroundColor Magenta

<#
    Import Tasks from modules via their exported aliases when defined in Build Manifest.
    https://github.com/nightroman/Invoke-Build/tree/master/Tasks/Import#example-2-import-from-a-module-with-tasks
#>

# Loading Build Tasks defined in the .build/ folder (will override the ones imported above if same task name).
Get-ChildItem -Path '.build/' -Recurse -Include '*.ps1' -ErrorAction Ignore | ForEach-Object {
    "Importing file $($_.BaseName)" | Write-Verbose

    . $_.FullName
}

# Synopsis: Empty task, useful to test the bootstrap process.
Task noop { }

# Define default task sequence ("."), can be overridden in the $BuildInfo.
Task . {
    Write-Build -Object 'No sequence currently defined for the default task' -ForegroundColor Yellow
}

Write-Host -Object 'Adding Workflow from configuration:' -ForegroundColor DarkGray

# Load Invoke-Build task sequences/workflows from $BuildInfo.
foreach ($workflow in $BuildInfo.BuildWorkflow.keys)
{
    Write-Verbose -Message "Creating Build Workflow '$Workflow' with tasks $($BuildInfo.BuildWorkflow.($Workflow) -join ', ')."

    $workflowItem = $BuildInfo.BuildWorkflow.($workflow)

    if ($workflowItem.Trim() -match '^\{(?<sb>[\w\W]*)\}$')
    {
        $workflowItem = [ScriptBlock]::Create($Matches['sb'])
    }

    Write-Host -Object "  +-> $workflow" -ForegroundColor DarkGray

    Task $workflow $workflowItem
}

Write-Host -Object "[build] Executing requested workflow: $($Tasks -join ', ')" -ForegroundColor Magenta

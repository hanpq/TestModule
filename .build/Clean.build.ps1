Task Clean {

    Write-Build Blue ($GetPSBuildInfo | Out-String)

    $OutputDirectory = Join-Path -Path $BuildRoot -ChildPath 'output'

    $RequiredModulesDirectory = Join-Path -Path $OutputDirectory -ChildPath 'RequiredModules'

    $FolderToExclude = Split-Path -Leaf -Path $RequiredModulesDirectory

    Write-Build -Color Green "`tRemoving $OutputDirectory\* excluding $FolderToExclude`n"

    Get-ChildItem -Path $OutputDirectory -Exclude $FolderToExclude | Remove-Item -Force -Recurse
}

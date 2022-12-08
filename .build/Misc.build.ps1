Task write_env {
    Write-Build Magenta (Get-ChildItem env: | Out-String)
    Write-Build Cyan (Get-Variable | Out-String)
    Write-Build Yellow ($BuildInfo | Out-String)

    $global:GetPSBuildInfo = @{
        TestProperty = 'TestValue'
    }
}

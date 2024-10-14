$InformationPreference = 'Continue'
$VerbosePreference = 'SilentlyContinue';
$ErrorActionPreference = "Stop"

$script:hasFailed = $false

Write-Output "Running the Installer Script"

#Set a global - this is used to determine if any of the tests have failed
#Assume a failure state, unless specifically changed to FALSE
$script:hasFailed = $true

<#
    .SYNOPSIS
    Test the running of an expected command to ensure it exists and works as expected

    .INPUTS
    command - The command to test
    expectedExitCode - The expected exit code from the command (defaults to 0)

    .OUTPUTS
    True if the command succeeded, false if it failed

    .NOTES
    If any of the tests fail, the script will exit with a non-zero exit code
#>
function Test-Command {
    param (
        [ValidateNotNullOrEmpty()]
        [string]$command,
        [int]$expectedExitCode = 0
    )

    Write-Output "Testing: '$command'"

    ($command | Invoke-Expression) | Write-Verbose
    if ($LASTEXITCODE -ne $expectedExitCode) {
        Write-Error "Test '$command' failured. Exit code was $LASTEXITCODE when $expectedExitCode is expected"
        $script:hasFailed = $true
    }
    else {
        Write-Output "Test '$command' succeeded"
    }
}

#Start the Validation Run
Write-Output "Performing Validation Tests"

#Test to make sure the commands are installed and work as expected

$script:hasFailed = $false # Set to false for now otherwise this will fail every time as there are no tests.

#Add in any other tests here

#If any fail, kill the build

if ($script:hasFailed) {
    Write-Error "Validation tests failed"
    exit 1
} else {
    Write-Output "Validation tests succeeded!"
}
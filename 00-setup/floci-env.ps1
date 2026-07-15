#Requires -Version 5.1
# The PowerShell twin of:  eval "$(floci env)"
#
# `floci env` emits POSIX shell syntax (`export KEY=value`), which PowerShell
# cannot evaluate. This parses the assignments into $env: variables instead.
#
# DOT-SOURCE it so the variables land in YOUR session, not a child scope:
#
#     . .\00-setup\floci-env.ps1
#
# Run it in every new terminal, same as the eval on macOS/Linux.

if ($MyInvocation.InvocationName -ne ".") {
    Write-Host "NOTE: run this dot-sourced or the variables die with the script:"
    Write-Host "    . $($MyInvocation.MyCommand.Path)"
}

foreach ($line in (floci env)) {
    if ($line -match '^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$') {
        $name  = $Matches[1]
        $value = $Matches[2].Trim().Trim('"').Trim("'")
        Set-Item -Path "Env:$name" -Value $value
    }
}

Write-Host "Floci environment set: AWS_ENDPOINT_URL=$env:AWS_ENDPOINT_URL"

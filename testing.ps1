# Automatically find csproj files in the current directory or subdirectories
$csprojPath = Get-ChildItem -Filter *.csproj -Recurse | Select-Object -First 1

if (-not $csprojPath) {
    Write-Error "Error: Could not find .csproj file in the current directory or subdirectories!"
    exit
}

# Read and parse XML content
[xml]$csprojXml = Get-Content $csprojPath.FullName

# Extract target frameworks (compatible with single framework TargetFramework and multiple framework TargetFrameworks)
$frameworks = @()
if ($csprojXml.Project.PropertyGroup.TargetFramework) {
    $frameworks += $csprojXml.Project.PropertyGroup.TargetFramework
}
if ($csprojXml.Project.PropertyGroup.TargetFrameworks) {
    # Multiple frameworks are usually separated by semicolons `;`, split them into arrays and remove spaces.
    $frameworks += $csprojXml.Project.PropertyGroup.TargetFrameworks.Split(';') | ForEach-Object { $_.Trim() }
}

# Remove duplicates and filter out null values
$frameworks = $frameworks | Where-Object { $_ } | Select-Object -Unique

Write-Host "The following target frameworks were dynamically detected:" -ForegroundColor Green
$frameworks | ForEach-Object { Write-Host " - $_" -ForegroundColor Gray }

# Array for storing results
$results = @()

# Enter the directory where the test project is located.
Push-Location "."

foreach ($fw in $frameworks) {
    Write-Host "`n==================== Testing $fw ====================" -ForegroundColor Cyan
    
    # Capture the output of dotnet run
    $rawOutput = dotnet run --framework $fw --no-build 2>&1 | Out-String
    
    # [Key Step] Filter out any possible ANSI color escape characters.
    $cleanOutput = $rawOutput -replace '\x1B\[[0-9;]*[a-zA-Z]', ''
    
    # Regular expressions
    $pattern = "Test count:\s*(\d+),\s*Correct:\s*(\d+),\s*Incorrect:\s*(\d+),\s*Error:\s*(\d+)"
    
    # Use .NET regular expressions directly to match clean text.
    $match = [regex]::Match($cleanOutput, $pattern)
    
    if ($match.Success) {
        # Convert to numbers for calculation
        $total     = [int]$match.Groups[1].Value
        $correct   = [int]$match.Groups[2].Value
        $incorrect = [int]$match.Groups[3].Value
        $error     = [int]$match.Groups[4].Value
        
        $results += [PSCustomObject]@{
            Framework = $fw
            Total = $total
            Passed = $correct
            Failed = $incorrect
            Error = $error
            PassRate = if ($total -gt 0) { 
                          [math]::Round(($correct / $total) * 100, 2)
                       } else { 0 }
        }
    } else {
        Write-Host "Warning: Unable to parse the statistics for $fw. Please check the output format." -ForegroundColor Yellow
        Write-Host "------ Actual output begins ------" -ForegroundColor DarkGray
        Write-Host $cleanOutput -ForegroundColor DarkGray
        Write-Host "------ End of actual output ------" -ForegroundColor DarkGray
    }
}

# Return to original directory
Pop-Location

# The comparison results of all frameworks are clearly presented in tabular form.
Write-Host "`n========== Cross-frame testing statistics summary ==========" -ForegroundColor Green
$results | Format-Table -AutoSize

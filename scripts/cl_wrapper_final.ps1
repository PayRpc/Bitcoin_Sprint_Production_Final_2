# cl_wrapper.ps1 - PowerShell wrapper for MSVC that handles CGO compiler flags
# 
# This script serves as a wrapper for Microsoft's cl.exe compiler to be used with Go's CGO.
# It translates GCC-style arguments that CGO passes to the compiler into MSVC-compatible
# arguments. This allows Go projects with CGO dependencies to be built with MSVC on Windows.
#
# Usage:
#   1. Set CC and CXX environment variables to point to cl_wrapper.bat
#   2. Set CGO_ENABLED=1
#   3. Run go build as usual
#
# Example:
#   $env:CC = "C:\path\to\cl_wrapper.bat"
#   $env:CXX = "C:\path\to\cl_wrapper.bat"
#   $env:CGO_ENABLED = 1
#   go build ./...

# Enable detailed logging for debugging
$enableLogging = $true
$logPath = "C:\temp\cl_wrapper.log"

function Log-Message {
    param([string]$message)
    
    if ($enableLogging) {
        "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $message" | Out-File -FilePath $logPath -Append -Encoding utf8
    }
}

Log-Message "Called with arguments: $($args -join ' ')"

# Special cases that need quick handling
# 1. CGO compiler capability check with -### (dry run)
if ($args -contains "-###") {
    Log-Message "Detected CGO dry run (-###), exiting with success"
    exit 0
}

# 2. CGO preprocessor checks
if (($args -contains "-dM") -and ($args -contains "-E")) {
    Log-Message "Detected CGO preprocessor check (-dM -E), exiting with success"
    exit 0
}

# Build filtered arguments list
$filteredArgs = @()
$skipNext = $false

for ($i = 0; $i -lt $args.Count; $i++) {
    # Skip if this is a value for a previous flag
    if ($skipNext) {
        $skipNext = $false
        continue
    }
    
    $arg = $args[$i]
    
    # 1. Handle GCC flags that take values
    if ($arg -match "^-(fmessage-length|frandom-seed|U|D)$") {
        Log-Message "Skipping GCC flag with value: $arg $($args[$i+1])"
        $skipNext = $true
        continue
    }
    
    # 2. Filter out GCC architecture and optimization flags
    if ($arg -match "^-(m64|mthreads|O[0-9])$") {
        Log-Message "Filtering architecture/optimization flag: $arg"
        continue
    }
    
    # 3. Filter warning and feature flags
    if ($arg -match "^-(W.*|f.*)$") {
        Log-Message "Filtering warning/feature flag: $arg"
        continue
    }
    
    # 4. Filter linker flags
    if ($arg -match "^-Wl,") {
        Log-Message "Filtering linker flag: $arg"
        continue
    }
    
    # 5. Filter preprocessor flags
    if ($arg -match "^-(dM|E|x)$") {
        Log-Message "Filtering preprocessor flag: $arg"
        if ($arg -eq "-x") { $skipNext = $true } # -x is followed by language
        continue
    }
    
    # 6. Convert include paths (-I to /I)
    if ($arg -eq "-I") {
        $includePath = $args[$i+1]
        # Fix trailing backslash issue (add a dot)
        if ($includePath.EndsWith("\")) {
            $includePath += "."
        }
        Log-Message "Converting -I to /I: $includePath"
        $filteredArgs += "/I`"$includePath`""
        $skipNext = $true
        continue
    }
    
    # 7. Handle combined include path (-I/path)
    if ($arg -match "^-I(.+)") {
        $includePath = $arg.Substring(2)
        if ($includePath.EndsWith("\")) {
            $includePath += "."
        }
        Log-Message "Converting -I combined path to /I: $includePath"
        $filteredArgs += "/I`"$includePath`""
        continue
    }
    
    # 8. Convert output flag (-o to /Fo)
    if ($arg -eq "-o") {
        $outputPath = $args[$i+1]
        if ($outputPath.EndsWith("\")) {
            $outputPath += "."
        }
        Log-Message "Converting -o to /Fo: $outputPath"
        $filteredArgs += "/Fo`"$outputPath`""
        $skipNext = $true
        continue
    }
    
    # 9. Convert compile-only flag (-c to /c)
    if ($arg -eq "-c") {
        Log-Message "Converting -c to /c"
        $filteredArgs += "/c"
        continue
    }
    
    # 10. Handle stdin (-) special case
    if ($arg -eq "-") {
        Log-Message "Stdin input (-) detected, exiting with success (CGO check)"
        exit 0
    }
    
    # 11. Add typical MSVC flags if not already present
    if ($arg -eq "/D_CRT_SECURE_NO_WARNINGS" -or 
        $arg -eq "/DWIN32" -or 
        $arg -eq "/D_WIN32" -or 
        $arg -eq "/W3" -or 
        $arg -eq "/O2") {
        Log-Message "Passing through MSVC flag: $arg"
        $filteredArgs += $arg
        continue
    }
    
    # 12. Pass through all other args (likely source files or MSVC flags)
    if ($arg -match '\s') {
        # Properly quote arguments with spaces
        $filteredArgs += "`"$arg`""
    } else {
        $filteredArgs += $arg
    }
}

# Find cl.exe
$clExe = "cl.exe"  # Use PATH-based lookup first (from vcvarsall.bat)

# Fallbacks if cl.exe not in PATH
$vsBasePaths = @(
    "C:\Program Files\Microsoft Visual Studio\2022",
    "C:\Program Files (x86)\Microsoft Visual Studio\2022",
    "C:\Program Files\Microsoft Visual Studio\2019",
    "C:\Program Files (x86)\Microsoft Visual Studio\2019"
)

$editions = @("Community", "Professional", "Enterprise")

# Only search for cl.exe if not found in PATH
if (-not (Get-Command $clExe -ErrorAction SilentlyContinue)) {
    Log-Message "cl.exe not found in PATH, searching in Visual Studio directories"
    
    foreach ($basePath in $vsBasePaths) {
        if (-not (Test-Path $basePath)) { continue }
        
        foreach ($edition in $editions) {
            $clPath = Join-Path $basePath "$edition\VC\Tools\MSVC"
            if (-not (Test-Path $clPath)) { continue }
            
            # Find the latest version
            $versions = Get-ChildItem -Path $clPath -Directory | Sort-Object Name -Descending
            foreach ($version in $versions) {
                $candidatePath = Join-Path $version.FullName "bin\Hostx64\x64\cl.exe"
                if (Test-Path $candidatePath) {
                    $clExe = $candidatePath
                    Log-Message "Found cl.exe at: $clExe"
                    break
                }
            }
            if ($clExe -ne "cl.exe") { break }
        }
        if ($clExe -ne "cl.exe") { break }
    }
}

Log-Message "Final command: $clExe $filteredArgs"

try {
    $process = Start-Process -FilePath $clExe -ArgumentList $filteredArgs -NoNewWindow -Wait -PassThru
    $exitCode = $process.ExitCode
    Log-Message "cl.exe exited with code: $exitCode"
    exit $exitCode
}
catch {
    Log-Message "Error executing cl.exe: $_"
    exit 1
}

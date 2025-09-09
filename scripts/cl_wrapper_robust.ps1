# cl_wrapper_robust.ps1 - Robust PowerShell-based MSVC wrapper for Go's CGO
# Log all arguments for debugging
$logPath = "C:\temp\cl_args.log"
"Called with arguments: $($args -join ' ')" | Out-File -FilePath $logPath -Append

# Quick exit for specific cases that don't need compilation
# Case 1: CGO is checking compiler capabilities with -### -x c -c -
if (($args -contains "-###") -or 
    (($args -contains "-dM") -and ($args -contains "-E") -and ($args -contains "-"))) {
    "Detected CGO capability check, exiting with success" | Out-File -FilePath $logPath -Append
    exit 0
}

# Build filtered arguments list
$filteredArgs = @()
$skipNext = $false

for ($i = 0; $i -lt $args.Count; $i++) {
    if ($skipNext) {
        $skipNext = $false
        continue
    }
    
    $arg = $args[$i]
    
    # Handle flags that take values (need to skip the next argument)
    if ($arg -eq "-fmessage-length" -or $arg -eq "-frandom-seed") {
        "Filtering out GCC flag with value: $arg $($args[$i+1])" | Out-File -FilePath $logPath -Append
        $skipNext = $true
        continue
    }
    
    # Filter GCC-specific flags
    if ($arg -match "^-m64$|^-mthreads$") {
        "Filtering out GCC architecture flag: $arg" | Out-File -FilePath $logPath -Append
        continue
    }
    
    if ($arg -match "^-Wall$|^-Werror$|^-Wdeclaration-after-statement$") {
        "Filtering out GCC warning flag: $arg" | Out-File -FilePath $logPath -Append
        continue
    }
    
    if ($arg -match "^-fPIC$|^-fPIE$|^-fno-stack-protector$") {
        "Filtering out GCC feature flag: $arg" | Out-File -FilePath $logPath -Append
        continue
    }
    
    if ($arg -match "^-Wl,") {
        "Filtering out GCC linker flag: $arg" | Out-File -FilePath $logPath -Append
        continue
    }
    
    # Skip preprocessor flags
    if ($arg -eq "-dM" -or $arg -eq "-E") {
        "Filtering out CGO preprocessor flag: $arg" | Out-File -FilePath $logPath -Append
        continue
    }
    
    # Skip language specification
    if ($arg -eq "-x") {
        "Filtering out language specification: $arg $($args[$i+1])" | Out-File -FilePath $logPath -Append
        $skipNext = $true
        continue
    }
    
    # Convert -I to /I (include paths)
    if ($arg -eq "-I") {
        $includePath = $args[$i+1]
        # Handle trailing backslash in path
        if ($includePath -match '\\$') {
            $includePath = "$includePath."
        }
        "Converting -I to /I: $includePath" | Out-File -FilePath $logPath -Append
        $filteredArgs += "/I`"$includePath`""
        $skipNext = $true
        continue
    }
    
    # Handle -I combined with path
    if ($arg -match "^-I(.+)") {
        $includePath = $arg.Substring(2)
        # Handle trailing backslash in path
        if ($includePath -match '\\$') {
            $includePath = "$includePath."
        }
        "Converting -I combined path to /I: $includePath" | Out-File -FilePath $logPath -Append
        $filteredArgs += "/I`"$includePath`""
        continue
    }
    
    # Convert -o to /Fo (output file)
    if ($arg -eq "-o") {
        $outputPath = $args[$i+1]
        # Handle trailing backslash
        if ($outputPath -match '\\$') {
            $outputPath = "$outputPath."
        }
        "Converting -o to /Fo: $outputPath" | Out-File -FilePath $logPath -Append
        $filteredArgs += "/Fo`"$outputPath`""
        $skipNext = $true
        continue
    }
    
    # Convert -c to /c (compile only)
    if ($arg -eq "-c") {
        "Converting -c to /c" | Out-File -FilePath $logPath -Append
        $filteredArgs += "/c"
        continue
    }
    
    # Handle stdin input
    if ($arg -eq "-") {
        $tmpFile = [System.IO.Path]::GetTempFileName() + ".c"
        "Reading from stdin to temp file: $tmpFile" | Out-File -FilePath $logPath -Append
        
        # For stdin cases, create a temporary dummy file and return success
        # This is for CGO compiler capability checks that should return success
        "// Empty stub for CGO stdin check" | Out-File -FilePath $tmpFile
        "Bypassing stdin read, assuming compiler capability check" | Out-File -FilePath $logPath -Append
        exit 0
        continue
    }
    
    # Pass through all other arguments (likely source files or MSVC flags)
    # Make sure to properly quote arguments with spaces
    if ($arg -match '\s') {
        $filteredArgs += "`"$arg`""
    }
    else {
        $filteredArgs += $arg
    }
}

# Locate cl.exe in the MSVC tools directory
$clExe = "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\cl.exe"
if (-not (Test-Path $clExe)) {
    "Could not find cl.exe at expected path: $clExe, looking in PATH" | Out-File -FilePath $logPath -Append
    $clExe = (Get-Command cl -ErrorAction SilentlyContinue).Source
    if (-not $clExe) {
        "cl.exe not found in PATH either, build will fail" | Out-File -FilePath $logPath -Append
        exit 1
    }
}

# Log the final command
"Executing: $clExe $filteredArgs" | Out-File -FilePath $logPath -Append

# Execute cl.exe with the filtered arguments
try {
    $process = Start-Process -FilePath $clExe -ArgumentList $filteredArgs -NoNewWindow -Wait -PassThru
    $exitCode = $process.ExitCode
    "cl.exe exited with code: $exitCode" | Out-File -FilePath $logPath -Append
    exit $exitCode
}
catch {
    "Error executing cl.exe: $_" | Out-File -FilePath $logPath -Append
    exit 1
}

param([Parameter(ValueFromRemainingArguments=$true)] [string[]] $Args)

$log = "C:\temp\cl_wrapper_ps_log.txt"
"Called with args: $($Args -join ' ')" | Out-File -FilePath $log -Append -Encoding utf8

# Quick checks
if ($Args -contains '-###') {
    "Detected dry-run (-###), exiting 0" | Out-File -FilePath $log -Append
    exit 0
}

if ($Args.Count -ge 3 -and $Args[0] -eq '-dM' -and $Args[1] -eq '-E' -and $Args[2] -eq '-') {
    "Detected compiler capability check (-dM -E -), exiting 0" | Out-File -FilePath $log -Append
    exit 0
}

$msvcArgs = New-Object System.Collections.Generic.List[string]

for ($i = 0; $i -lt $Args.Count; $i++) {
    $a = $Args[$i]

    switch -Regex ($a) {
        '^-Wl,' { "Filtering linker flag: $a" | Out-File -FilePath $log -Append; continue }
        '^-m'   { "Filtering arch flag: $a" | Out-File -FilePath $log -Append; continue }
        '^-f'   { "Filtering gcc -f flag: $a" | Out-File -FilePath $log -Append; continue }
        '^(-Wall|-Werror)$' { "Filtering warning flag: $a" | Out-File -FilePath $log -Append; continue }
        '^-$'   {
            # read stdin to temp file
            $tmp = [System.IO.Path]::Combine($env:TEMP, "cgo_stdin_$([System.Guid]::NewGuid().ToString()).c")
            "Reading stdin to $tmp" | Out-File -FilePath $log -Append
            $content = [Console]::In.ReadToEnd()
            Set-Content -LiteralPath $tmp -Value $content -Encoding Ascii
            $msvcArgs.Add(('"{0}"' -f $tmp))
            continue
        }
        '^-I$' {
            # next token is include path
            $i++;
            if ($i -ge $Args.Count) { break }
            $path = $Args[$i]
            if ($path.EndsWith('\')) { $path = $path + '.' }
            $msvcArgs.Add(('/I"{0}"' -f $path))
            continue
        }
        '^-I(.+)' {
            $path = $a.Substring(2)
            if ($path.EndsWith('\')) { $path = $path + '.' }
            $msvcArgs.Add(('/I"{0}"' -f $path))
            continue
        }
        '^-o$' {
            $i++;
            if ($i -ge $Args.Count) { break }
            $out = $Args[$i]
            if ($out.EndsWith('\')) { $out = $out + '.' }
            $msvcArgs.Add(('/Fo"{0}"' -f $out))
            continue
        }
        '^ -c$' { $msvcArgs.Add('/c'); continue }
        '^\-c$' { $msvcArgs.Add('/c'); continue }
        default {
            # pass through other args (quote if contains spaces)
            if ($a -match '\s') { $msvcArgs.Add(('"{0}"' -f $a)) } else { $msvcArgs.Add($a) }
        }
    }
}

"Final MSVC args: $($msvcArgs -join ' ')" | Out-File -FilePath $log -Append

try {
    # Use cl.exe from PATH (vcvarsall should have set it)
    $proc = Start-Process -FilePath cl.exe -ArgumentList $msvcArgs -NoNewWindow -PassThru -Wait
    exit $proc.ExitCode
} catch {
    "Failed to invoke cl.exe: $_" | Out-File -FilePath $log -Append
    exit 1
}

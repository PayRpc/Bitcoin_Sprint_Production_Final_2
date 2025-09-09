Title: cgo/MSVC compilation failure in workspaces with spaces in the path

Description:

When running `go build` in this repository on Windows with CGO enabled and the MSVC toolchain, cgo may fail to execute the configured C compiler (CC) when the workspace path contains spaces (for example: `C:\Projects 2\...`). The failure message is similar to:

    cgo: C compiler "C:\Projects" not found: exec: "C:\Projects": executable file not found in %PATH%

This appears to be a quoting/CreateProcess issue where the path supplied to the C compiler is split at the space and the executable is not found.

Steps already taken:

- Replaced references to legacy `cl_wrapper` script variants and pointed smoke scripts to canonical `scripts/cl_wrapper_fixed.bat`.
- Attempted multiple mitigations in `build-smoke-test-timeout.bat` to avoid spaces:
  - Quoted CC/CXX values
  - Copied wrapper to `%TEMP%` and repo-local `scripts\tmp_wrapper` (both with and without 8.3 short path)
  - Added the repo-local temp wrapper folder to `PATH` and used bare filename (so Windows resolves via PATH)
  - Used short (8.3) path expansion for scripts directory before copying
  - Observed `detected was unexpected at this time.` which indicates the wrapper itself or the invocation context might be interpreting arguments unexpectedly when invoked by cgo.

Why this is deferred:

This is an environment-specific problem involving how Go/cgo invokes the C compiler on Windows and how wrapper scripts are resolved. It requires reproducing in a clean CI environment and potentially changing the way CC is set (e.g., use a tiny shim in a path without spaces, or adjust cgo flags) or changing the wrapper to be an executable rather than a batch script.

Proposed next steps (separate task):

1. Reproduce the failure in an isolated CI runner (Windows) with a workspace path that includes spaces.
2. Run an instrumented cgo invocation to capture the exact exec call arguments (e.g., small Go program that calls cgo with verbose logging or modify the wrapper to record its argv when executed by cgo).
3. Consider changing the wrapper to a small native executable (compiled Go or small .exe) placed in a no-space path, or modify CI to use a workspace path without spaces.
4. Document the final fix and update smoke/CI scripts accordingly.

Attachments:
- build-smoke-test-timeout.bat (modified to reference canonical wrapper and use repo-local tmp folder)
- logs from local attempts (available in the repo's working directory if captured during runs)

Assignee: TBD
Priority: Medium


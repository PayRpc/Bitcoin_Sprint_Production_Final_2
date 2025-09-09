# SecureBuffer FFI Setup (v2)

Yes, bring it back. It’s high‑leverage docs: it reduces build friction, speeds onboarding, and prevents platform‑specific linking errors. This v2 guide corrects a critical detail (CGO cannot link Rust **.rlib**; produce **staticlib/cdylib**), adds verification tests, and includes CI‑ready steps for Linux/macOS/Windows.

---

## Quickstart (happy path)

```bash
# 1) Ensure toolchains
rustup show                          # Rust toolchain
cargo --version
Go version                           # go1.2x+

# 2) Build SecureBuffer as a C‑ABI library
cd secure/rust
rustup target add x86_64-unknown-linux-gnu aarch64-apple-darwin x86_64-pc-windows-gnu
cargo build --release                # produces libsecurebuffer.{a,so|dylib|dll}

# 3) Build Bitcoin Sprint (CGO on)
cd ../../
export CGO_ENABLED=1
go build -v ./cmd/sprint

# 4) Run the FFI smoke test (see below)
go test ./internal/secure -run TestFFI -v
```

---

## Prerequisites

### Common

* Go ≥ 1.20, Rust ≥ 1.70
* `pkg-config` (Linux/macOS) for optional discovery
* C toolchain (gcc/clang or MSVC)

### Linux (Debian/Ubuntu)

```bash
sudo apt update
sudo apt install -y build-essential pkg-config
```

### macOS

```bash
xcode-select --install
# Recommended: brew install llvm pkg-config
```

### Windows (two supported paths)

**MSYS2/MinGW (recommended GNU toolchain)**

```bash
# https://www.msys2.org
pacman -S --needed mingw-w64-x86_64-gcc mingw-w64-x86_64-pkg-config
```

**MSVC toolchain**

* Install *Visual Studio Build Tools* (C++ workload)
* Use `x86_64-pc-windows-msvc` Rust target

> Keep Rust target family consistent with your C toolchain (GNU vs MSVC).

---

## Rust crate configuration

`secure/rust/Cargo.toml` (excerpt):

```toml
[package]
name = "securebuffer"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["staticlib", "cdylib"] # CGO needs these, not .rlib

[dependencies]
# your deps here
```

**Header generation (recommended):** add `cbindgen` to produce a stable C header.

```toml
[build-dependencies]
cbindgen = "~0.26"
```

`build.rs` (optional):

```rust
fn main() {
    let crate_dir = std::env::var("CARGO_MANIFEST_DIR").unwrap();
    cbindgen::generate(crate_dir)
        .expect("Unable to generate bindings")
        .write_to_file("include/securebuffer.h");
}
```

Your Rust `src/lib.rs` must expose **C ABI** symbols:

```rust
#[no_mangle]
pub extern "C" fn sb_version() -> u32 { 1 }

#[no_mangle]
pub extern "C" fn sb_init() { /* init */ }
```

> Replace with real functions; keep `extern "C"` and `#[no_mangle]`.

Artifacts (per OS) under `secure/rust/target/release/`:

* Linux: `libsecurebuffer.a`, `libsecurebuffer.so`
* macOS: `libsecurebuffer.a`, `libsecurebuffer.dylib`
* Windows: `securebuffer.lib` + `securebuffer.dll` (MSVC) or `libsecurebuffer.a` + `securebuffer.dll` (GNU)

---

## Go CGO wrapper

`internal/secure/securebuffer.go` (skeleton):

```go
package secure

/*
#cgo CFLAGS: -I${SRCDIR}/../../secure/rust/include
#cgo linux LDFLAGS: -L${SRCDIR}/../../secure/rust/target/release -lsecurebuffer -Wl,-rpath,'$ORIGIN/../../secure/rust/target/release'
#cgo darwin LDFLAGS: -L${SRCDIR}/../../secure/rust/target/release -lsecurebuffer -Wl,-rpath,${SRCDIR}/../../secure/rust/target/release
#cgo windows LDFLAGS: -L${SRCDIR}/../../secure/rust/target/release -lsecurebuffer
#include "securebuffer.h"
*/
import "C"

func Version() uint32 { return uint32(C.sb_version()) }
func Init()           { C.sb_init() }
```

> Adjust header name/symbols to your actual exported API.

**Note on rpath:** the `-Wl,-rpath,...` ensures the runtime loader finds the shared lib next to your binary. Alternatively, ship the static `.a` to avoid rpath concerns.

---

## FFI verification test

`internal/secure/securebuffer_test.go`:

```go
package secure

import "testing"

func TestFFI(t *testing.T) {
    Init()
    if v := Version(); v == 0 {
        t.Fatalf("unexpected version: %d", v)
    }
}
```

Run:

```bash
go test ./internal/secure -run TestFFI -v
```

---

## Build & run

```bash
# Build Rust once per change
( cd secure/rust && cargo build --release )

# Build app (CGO on)
export CGO_ENABLED=1
GOFLAGS="-ldflags=-extldflags=-Wl,-rpath,'$ORIGIN/../secure/rust/target/release'"
go build -v ./cmd/sprint
```

**macOS Gatekeeper:** for unsigned `.dylib`, you may need `codesign --force --sign - <path>` during local dev, or prefer static linking.

---

## Troubleshooting

* **`gcc/clang not found`** → install toolchain; ensure it’s on `PATH`.
* **`undefined reference` / `symbol not found`** → verify functions are `extern "C"` + `#[no_mangle]`; correct lib name; rebuild release.
* **`cannot find -lsecurebuffer`** → confirm library in `target/release`; check `-L` path; ensure correct target triple for your OS/arch.
* **rpath / loader errors** (`dlopen` fail) → use static `.a`, or set loader env: `LD_LIBRARY_PATH`, `DYLD_FALLBACK_LIBRARY_PATH`, or keep rpath flags above.
* **Windows**: match Rust target to toolchain (`-msvc` vs `-gnu`); if using MSYS2, run the *MINGW64* shell for build and execution.

---

## Optional: pkg‑config integration

Create `securebuffer.pc` (installed or kept in repo):

```
prefix=${pcfiledir}/..
libdir=${prefix}/secure/rust/target/release
includedir=${prefix}/secure/rust/include

Name: securebuffer
Description: SecureBuffer FFI library
Version: 0.1.0
Libs: -L${libdir} -lsecurebuffer
Cflags: -I${includedir}
```

Then CGO flags can be simplified to `#cgo pkg-config: securebuffer`.

---

## CI matrix (GitHub Actions snippet)

```yaml
name: build
on: [push, pull_request]
jobs:
  matrix:
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest, windows-latest]
  steps:
    - uses: actions/checkout@v4
    - uses: actions/setup-go@v5
      with: { go-version: '1.22.x' }
    - uses: dtolnay/rust-toolchain@stable
    - name: Build Rust
      run: |
        cd secure/rust
        cargo build --release
    - name: Build Go (CGO)
      env:
        CGO_ENABLED: 1
      run: |
        go build -v ./cmd/sprint
    - name: FFI test
      run: go test ./internal/secure -run TestFFI -v
```

---

## Repository layout (reference)

```
Bitcoin Sprint
├── cmd/sprint/            # Go application entry point
├── internal/secure/       # Go FFI wrapper (CGO)
└── secure/rust/           # Rust SecureBuffer implementation
    ├── src/
    ├── include/          # cbindgen-generated header
    └── target/release/   # libsecurebuffer.(a|so|dylib|dll)
```

---

## Why this doc matters (benefit)

* **Prevents platform‑specific pitfalls** (rlib vs staticlib/cdylib, rpath, toolchain mismatch).
* **Accelerates onboarding** (copy‑paste commands + smoke test).
* **Stabilizes CI** (matrix build, deterministic artifacts).
* **Reduces support toil** by answering common errors upfront.

> Keep this file at `docs/securebuffer_ffi_setup.md`. Link it from the main README and the SecureBuffer module README. Commit a minimal FFI smoke test to keep it green.

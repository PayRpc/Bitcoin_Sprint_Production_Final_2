# Bitcoin Sprint Repository Organization

This document outlines the organization of the Bitcoin Sprint repository to help developers navigate the codebase efficiently.

## Directory Structure

- **bin/** - Compiled executables
  - bitcoin-sprint.exe - Main application executable
  - cb-chaos.exe - Circuit breaker chaos testing tool
  - smoke.exe - Smoke test executable
  - sprintd.exe - Sprint daemon executable

- **build/** - Build-related files
  - **artifacts/** - Build artifacts and temporary files
  - **native/** - Native build outputs

- **cmd/** - Command-line application entry points
  - **sprintd/** - Main Bitcoin Sprint daemon
  - **cb-chaos/** - Circuit breaker chaos testing
  - **cb-loadtest/** - Circuit breaker load testing
  - **cb-monitor/** - Circuit breaker monitoring
  - **p2p/** - P2P networking utilities
  - **runtime-demo/** - Runtime demonstration tools

- **config/** - Configuration files
  - **env/** - Environment configuration files for different environments
  - Various configuration files for Bitcoin, Docker, etc.

- **contracts/** - Smart contract code

- **docs/** - Documentation
  - **technical/** - Technical documentation about architecture and implementation
  - **user/** - User guides and deployment instructions
  - **summaries/** - Development summaries and progress reports
  - DOCUMENTATION_INDEX.md - Index of all documentation

- **internal/** - Internal packages (not exported)
  - **accel/** - Acceleration functionality
  - **api/** - API implementation
  - **cache/** - Caching implementation
  - **headers/** - Blockchain headers processing
  - **mempool/** - Mempool management
  - **p2p/** - P2P networking implementation
  - **precache/** - Precaching functionality
  - **securebuf/** - Secure buffer implementation
  - Various other internal packages

- **logs/** - Application logs

- **scripts/** - Utility scripts
  - Build scripts, wrapper scripts, and other utilities

- **secure/** - Security-related code

- **sprintclient/** - Client library code

- **web/** - Web interface and dashboard

## Repository Organization Principles

1. **Root Directory** - Contains only essential files:
   - README.md and LICENSE
   - go.mod and go.sum
   - Main configuration files
   - Makefile for build commands

2. **Documentation Organization**:
   - Technical documentation in docs/technical/
   - User guides in docs/user/
   - Development summaries in docs/summaries/

3. **Code Organization**:
   - Entry points in cmd/
   - Core implementation in internal/
   - Client libraries in sprintclient/

4. **Build Artifacts**:
   - Executables in bin/
   - Other build outputs in build/

5. **Configuration**:
   - Environment files in config/env/
   - Other configuration in config/

## Development Workflow

1. Use the `bin/` directory for working with executables
2. Reference the documentation index at `docs/DOCUMENTATION_INDEX.md`
3. Keep the root directory clean by placing new files in appropriate directories
4. Use the scripts in the `scripts/` directory for common operations

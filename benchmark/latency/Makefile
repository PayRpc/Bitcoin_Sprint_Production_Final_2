# Makefile for p99 latency benchmarks

.PHONY: build run clean report

# Default target
all: build run

# Build the benchmark server
build:
	@echo Building p99 benchmark server...
	go build -o ../../bin/p99_server.exe ./p99_server.go

# Run the benchmarks
run: build
	@echo Running p99 latency benchmarks...
	pwsh -File ./p99_benchmark.ps1

# Run just the server (for manual testing)
server: build
	@echo Starting p99 server on port 8765...
	../../bin/p99_server.exe -port 8765

# Generate report
report:
	@echo Generating HTML report from benchmark results...
	go run ./gen_report.go -input benchmark_results.json -output p99_report.html

# Clean up binaries
clean:
	@echo Cleaning up...
	rm -f ../../bin/p99_server.exe
	rm -f benchmark_results.json
	rm -f p99_report.html

package main_test

import (
    "fmt"
    "testing"
    "time"
)

func TestSimple(t *testing.T) {
    fmt.Println("Simple Go test - no CGO dependencies")
    fmt.Println("Current time:", time.Now())
    fmt.Println("Test completed successfully!")
}

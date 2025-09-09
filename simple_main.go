package main

import (
    "fmt"
    "time"
)

func main() {
    fmt.Println("Simple Go test - no CGO dependencies")
    fmt.Println("Current time:", time.Now())
    fmt.Println("Test completed successfully!")
}

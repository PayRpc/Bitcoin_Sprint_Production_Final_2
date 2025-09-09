-- p99_load_test.lua
-- This script performs advanced load testing with wrk

-- Initialize the random number generator
math.randomseed(os.time())

-- Initialize counters
local counter = 0
local totalRequests = 0
local startTime = os.time()

-- Define the request function that will be called by wrk
function request()
    -- Increment counter
    counter = counter + 1
    totalRequests = totalRequests + 1
    
    -- Define endpoints to test
    local paths = {
        "/v1/latest",
        "/v1/status",
    }
    
    -- Select endpoint based on distribution
    -- 80% latest, 20% status (adjust as needed)
    local path
    if math.random() < 0.8 then
        path = paths[1]
    else
        path = paths[2]
    end
    
    -- Return the request object
    local req = {
        method = "GET",
        path = path,
        headers = {
            ["User-Agent"] = "wrk Load Test",
            ["Accept"] = "application/json"
        }
    }
    
    return req
end

-- This function is called when a response is received
function response(status, headers, body)
    -- Only log occasional responses to reduce overhead
    if counter % 1000 == 0 then
        local now = os.time()
        local elapsed = now - startTime
        io.write(string.format("[%d sec] Requests: %d, Last status: %d, Last body length: %d\n", 
            elapsed, totalRequests, status, #body))
    end
end

-- This function is called when the benchmark is done
function done(summary, latency, requests)
    io.write("\n----- P99 Latency Test Results -----\n")
    
    io.write(string.format("Total requests: %d\n", totalRequests))
    io.write(string.format("RPS: %.2f\n", requests.rate))
    
    io.write("\nLatency Distribution:\n")
    for _, p in pairs({ 50, 75, 90, 95, 99, 99.9 }) do
        n = latency:percentile(p)
        io.write(string.format("  %g%%: %.3f ms\n", p, n / 1000.0))
    end
    
    io.write("\nTarget met? ")
    if latency:percentile(99) / 1000.0 <= 5.0 then
        io.write("YES - p99 latency is within 5ms target!\n")
    else
        io.write("NO - p99 latency exceeds 5ms target.\n")
    end
end

param(
    [Parameter(Mandatory=$true)]
    [string]$CsvFile,
    
    [Parameter(Mandatory=$true)]
    [string]$OutputDir
)

# Check if CSV exists
if (!(Test-Path $CsvFile)) {
    Write-Error "CSV file not found: $CsvFile"
    exit 1
}

# Check if output directory exists
if (!(Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

# Load CSV data
$data = Import-Csv -Path $CsvFile

# Load Chart.js template for latency comparison
$latencyChartTemplate = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Provider Latency Comparison</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .chart-container { width: 800px; height: 500px; margin: 0 auto; }
        h1, h2 { text-align: center; }
    </style>
</head>
<body>
    <h1>Bitcoin Sprint Acceleration Layer vs. Third-Party Providers</h1>
    <h2>Latency Comparison</h2>
    <div class="chart-container">
        <canvas id="latencyChart"></canvas>
    </div>
    <script>
        const ctx = document.getElementById('latencyChart').getContext('2d');
        
        const chart = new Chart(ctx, {
            type: 'bar',
            data: {
                labels: [PROVIDER_LABELS],
                datasets: [
                    {
                        label: 'Average Latency (ms)',
                        data: [AVG_LATENCY_DATA],
                        backgroundColor: [
                            'rgba(54, 162, 235, 0.5)',
                            'rgba(54, 162, 235, 0.5)',
                            'rgba(255, 99, 132, 0.5)',
                            'rgba(255, 99, 132, 0.5)'
                        ],
                        borderColor: [
                            'rgb(54, 162, 235)',
                            'rgb(54, 162, 235)',
                            'rgb(255, 99, 132)',
                            'rgb(255, 99, 132)'
                        ],
                        borderWidth: 1
                    },
                    {
                        label: 'Maximum Latency (ms)',
                        data: [MAX_LATENCY_DATA],
                        backgroundColor: [
                            'rgba(75, 192, 192, 0.5)',
                            'rgba(75, 192, 192, 0.5)',
                            'rgba(255, 159, 64, 0.5)',
                            'rgba(255, 159, 64, 0.5)'
                        ],
                        borderColor: [
                            'rgb(75, 192, 192)',
                            'rgb(75, 192, 192)',
                            'rgb(255, 159, 64)',
                            'rgb(255, 159, 64)'
                        ],
                        borderWidth: 1
                    }
                ]
            },
            options: {
                responsive: true,
                plugins: {
                    legend: {
                        position: 'top',
                    },
                    title: {
                        display: true,
                        text: 'Lower is Better: Sprint Acceleration vs. Third-Party Providers'
                    }
                },
                scales: {
                    y: {
                        beginAtZero: true,
                        title: {
                            display: true,
                            text: 'Latency (ms)'
                        }
                    }
                }
            }
        });
    </script>
</body>
</html>
"@

# Load Chart.js template for reliability comparison
$reliabilityChartTemplate = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Provider Reliability Comparison</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .chart-container { width: 800px; height: 500px; margin: 0 auto; }
        h1, h2 { text-align: center; }
    </style>
</head>
<body>
    <h1>Bitcoin Sprint Acceleration Layer vs. Third-Party Providers</h1>
    <h2>Reliability Comparison</h2>
    <div class="chart-container">
        <canvas id="reliabilityChart"></canvas>
    </div>
    <script>
        const ctx = document.getElementById('reliabilityChart').getContext('2d');
        
        const chart = new Chart(ctx, {
            type: 'bar',
            data: {
                labels: [PROVIDER_LABELS],
                datasets: [
                    {
                        label: 'Success Rate (%)',
                        data: [SUCCESS_RATE_DATA],
                        backgroundColor: [
                            'rgba(75, 192, 192, 0.5)',
                            'rgba(75, 192, 192, 0.5)',
                            'rgba(255, 99, 132, 0.5)',
                            'rgba(255, 99, 132, 0.5)'
                        ],
                        borderColor: [
                            'rgb(75, 192, 192)',
                            'rgb(75, 192, 192)',
                            'rgb(255, 99, 132)',
                            'rgb(255, 99, 132)'
                        ],
                        borderWidth: 1
                    },
                    {
                        label: 'Error Rate (%)',
                        data: [ERROR_RATE_DATA],
                        backgroundColor: [
                            'rgba(54, 162, 235, 0.5)',
                            'rgba(54, 162, 235, 0.5)',
                            'rgba(255, 159, 64, 0.5)',
                            'rgba(255, 159, 64, 0.5)'
                        ],
                        borderColor: [
                            'rgb(54, 162, 235)',
                            'rgb(54, 162, 235)',
                            'rgb(255, 159, 64)',
                            'rgb(255, 159, 64)'
                        ],
                        borderWidth: 1
                    }
                ]
            },
            options: {
                responsive: true,
                plugins: {
                    legend: {
                        position: 'top',
                    },
                    title: {
                        display: true,
                        text: 'Higher Success Rate is Better: Sprint Acceleration vs. Third-Party Providers'
                    }
                },
                scales: {
                    y: {
                        beginAtZero: true,
                        max: 100,
                        title: {
                            display: true,
                            text: 'Percentage (%)'
                        }
                    }
                }
            }
        });
    </script>
</body>
</html>
"@

# Prepare data for charts
$groupedData = $data | Group-Object -Property Provider
$providers = ($groupedData | ForEach-Object { "'$($_.Name)'" }) -join ", "

# Calculate averages for each provider
$avgLatencies = ($groupedData | ForEach-Object { 
    [math]::Round(($_.Group | Measure-Object -Property AvgLatency_ms -Average).Average, 1)
}) -join ", "

$maxLatencies = ($groupedData | ForEach-Object { 
    [math]::Round(($_.Group | Measure-Object -Property MaxLatency_ms -Average).Average, 1)
}) -join ", "

$successRates = ($groupedData | ForEach-Object { 
    [math]::Round((($_.Group | ForEach-Object { [double]$_.SuccessRate } | Measure-Object -Average).Average * 100), 1)
}) -join ", "

$errorRates = ($groupedData | ForEach-Object { 
    [math]::Round(100 - (($_.Group | ForEach-Object { [double]$_.SuccessRate } | Measure-Object -Average).Average * 100), 1)
}) -join ", "

# Generate latency chart
$latencyChart = $latencyChartTemplate -replace '\[PROVIDER_LABELS\]', $providers
$latencyChart = $latencyChart -replace '\[AVG_LATENCY_DATA\]', $avgLatencies
$latencyChart = $latencyChart -replace '\[MAX_LATENCY_DATA\]', $maxLatencies

$latencyChartPath = Join-Path $OutputDir "latency_chart.html"
$latencyChart | Out-File -FilePath $latencyChartPath -Encoding utf8

# Generate reliability chart
$reliabilityChart = $reliabilityChartTemplate -replace '\[PROVIDER_LABELS\]', $providers
$reliabilityChart = $reliabilityChart -replace '\[SUCCESS_RATE_DATA\]', $successRates
$reliabilityChart = $reliabilityChart -replace '\[ERROR_RATE_DATA\]', $errorRates

$reliabilityChartPath = Join-Path $OutputDir "reliability_chart.html"
$reliabilityChart | Out-File -FilePath $reliabilityChartPath -Encoding utf8

# Create PNG versions (if Chrome is available)
try {
    $chromePath = "C:\Program Files\Google\Chrome\Application\chrome.exe"
    if (Test-Path $chromePath) {
        $latencyPngPath = Join-Path $OutputDir "latency_chart.png"
        $reliabilityPngPath = Join-Path $OutputDir "reliability_chart.png"
        
        # Using Chrome headless to convert HTML to PNG
        & $chromePath --headless --disable-gpu --screenshot="$latencyPngPath" --window-size=1000,600 $latencyChartPath
        & $chromePath --headless --disable-gpu --screenshot="$reliabilityPngPath" --window-size=1000,600 $reliabilityChartPath
        
        Write-Host "PNG charts generated successfully" -ForegroundColor Green
    }
}
catch {
    Write-Host "Could not generate PNG charts: $_" -ForegroundColor Yellow
    Write-Host "HTML charts are still available" -ForegroundColor Yellow
}

Write-Host "Charts generated successfully:" -ForegroundColor Green
Write-Host "- Latency Chart: $latencyChartPath" -ForegroundColor Cyan
Write-Host "- Reliability Chart: $reliabilityChartPath" -ForegroundColor Cyan

return @{
    LatencyChartPath = $latencyChartPath
    ReliabilityChartPath = $reliabilityChartPath
}

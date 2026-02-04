#Requires -Version 5.1

<#
.SYNOPSIS
    Pester tests for Ralph Howell Loop utilities
.DESCRIPTION
    Tests for utils.ps1 functions including logging, state management,
    signal parsing, rate limiting, and circuit breaker logic.
    Compatible with Pester 3.4+
#>

$ScriptDir = Split-Path -Parent $PSScriptRoot
. (Join-Path $ScriptDir "scripts\utils.ps1")

Describe "Signal Parsing" {
    Context "Find-CompletionSignal" {
        It "Should find COMPLETE signal" {
            $result = Find-CompletionSignal "<PROMISE>COMPLETE</PROMISE>"
            $result | Should Be "COMPLETE"
        }

        It "Should find BLOCKED signal" {
            $result = Find-CompletionSignal "<PROMISE>BLOCKED</PROMISE>"
            $result | Should Be "BLOCKED"
        }

        It "Should be case-insensitive" {
            $result = Find-CompletionSignal "<promise>complete</promise>"
            $result | Should Be "COMPLETE"
        }

        It "Should handle mixed case" {
            $result = Find-CompletionSignal "<Promise>Complete</Promise>"
            $result | Should Be "COMPLETE"
        }

        It "Should be whitespace tolerant" {
            $result = Find-CompletionSignal "< promise > COMPLETE < / promise >"
            $result | Should Be "COMPLETE"
        }

        It "Should handle extra whitespace in tags" {
            $result = Find-CompletionSignal "<  PROMISE  >BLOCKED<  /  PROMISE  >"
            $result | Should Be "BLOCKED"
        }

        It "Should return null when no signal found" {
            $result = Find-CompletionSignal "Some random text without a signal"
            $result | Should BeNullOrEmpty
        }

        It "Should find signal in longer text" {
            $text = @"
I have completed the task successfully.
All tests are passing and the feature works as expected.

<PROMISE>COMPLETE</PROMISE>
"@
            $result = Find-CompletionSignal $text
            $result | Should Be "COMPLETE"
        }
    }

    Context "Find-BlockerReason" {
        It "Should find blocker with XML tags" {
            $result = Find-BlockerReason "<BLOCKER>Need API key</BLOCKER>"
            $result | Should Be "Need API key"
        }

        It "Should find blocker with BLOCKED: prefix" {
            $result = Find-BlockerReason "BLOCKED: Missing configuration file"
            $result | Should Be "Missing configuration file"
        }

        It "Should find blocker with Blocker: prefix" {
            $result = Find-BlockerReason "Blocker: External dependency unavailable"
            $result | Should Be "External dependency unavailable"
        }

        It "Should return null when no blocker found" {
            $result = Find-BlockerReason "Everything is working fine"
            $result | Should BeNullOrEmpty
        }
    }
}

Describe "Directory Management" {
    $TestDir = Join-Path $env:TEMP "ralph-tests-$(Get-Random)"

    Context "Initialize-RalphDirectory" {
        BeforeEach {
            $script:testProjectDir = Join-Path $TestDir "test-project-$(Get-Random)"
            New-Item -Path $script:testProjectDir -ItemType Directory -Force | Out-Null
            Push-Location $script:testProjectDir
        }

        AfterEach {
            Pop-Location
            if (Test-Path $script:testProjectDir) {
                Remove-Item -Path $script:testProjectDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should create .ralph directory" {
            Initialize-RalphDirectory | Out-Null
            Test-RalphExists | Should Be $true
        }

        It "Should create config.json with defaults" {
            Initialize-RalphDirectory | Out-Null
            $config = Get-RalphConfig
            $config.model | Should Not BeNullOrEmpty
            $config.maxIterations | Should BeGreaterThan 0
        }

        It "Should create state.json" {
            Initialize-RalphDirectory | Out-Null
            $state = Get-RalphState
            $state.status | Should Be "initialized"
        }

        It "Should overwrite when -Force is used" {
            Initialize-RalphDirectory | Out-Null
            Update-RalphState -Updates @{ status = "modified" }
            Initialize-RalphDirectory -Force | Out-Null
            $state = Get-RalphState
            $state.status | Should Be "initialized"
        }
    }

    # Cleanup
    if (Test-Path $TestDir) {
        Remove-Item -Path $TestDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "State Management" {
    $TestDir = Join-Path $env:TEMP "ralph-state-test-$(Get-Random)"
    New-Item -Path $TestDir -ItemType Directory -Force | Out-Null
    Push-Location $TestDir
    Initialize-RalphDirectory | Out-Null

    Context "Get-RalphState" {
        It "Should return state object" {
            $state = Get-RalphState
            $state | Should Not BeNullOrEmpty
            $state.status | Should Not BeNullOrEmpty
        }
    }

    Context "Update-RalphState" {
        It "Should update single property" {
            Update-RalphState -Updates @{ currentIteration = 5 }
            $state = Get-RalphState
            $state.currentIteration | Should Be 5
        }

        It "Should update multiple properties" {
            Update-RalphState -Updates @{
                status = "running"
                noChangeCount = 2
            }
            $state = Get-RalphState
            $state.status | Should Be "running"
            $state.noChangeCount | Should Be 2
        }

        It "Should preserve existing properties" {
            Update-RalphState -Updates @{ currentIteration = 10 }
            Update-RalphState -Updates @{ status = "paused" }
            $state = Get-RalphState
            $state.currentIteration | Should Be 10
            $state.status | Should Be "paused"
        }
    }

    Pop-Location
    Remove-Item -Path $TestDir -Recurse -Force -ErrorAction SilentlyContinue
}

Describe "Config Management" {
    $TestDir = Join-Path $env:TEMP "ralph-config-test-$(Get-Random)"
    New-Item -Path $TestDir -ItemType Directory -Force | Out-Null
    Push-Location $TestDir
    Initialize-RalphDirectory | Out-Null

    Context "Get-RalphConfig" {
        It "Should return config with defaults" {
            $config = Get-RalphConfig
            $config.model | Should Not BeNullOrEmpty
            $config.maxIterations | Should BeGreaterThan 0
            $config.rateLimiting.maxCallsPerHour | Should BeGreaterThan 0
        }
    }

    Context "Save-RalphConfig" {
        It "Should save and retrieve custom config" {
            $customConfig = @{
                model = "test-model"
                maxIterations = 99
                rateLimiting = @{
                    maxCallsPerHour = 50
                    cooldownSeconds = 5
                    retryCount = 2
                }
                circuitBreaker = @{
                    maxNoChangeIterations = 5
                    maxSameErrorIterations = 10
                    maxTotalMinutes = 120
                }
                git = @{
                    autoCommit = $false
                    autoInit = $false
                    commitMessagePrefix = "Test"
                }
                dashboard = @{
                    enabled = $false
                }
            }
            Save-RalphConfig -Config $customConfig

            $loaded = Get-RalphConfig
            $loaded.model | Should Be "test-model"
            $loaded.maxIterations | Should Be 99
        }
    }

    Pop-Location
    Remove-Item -Path $TestDir -Recurse -Force -ErrorAction SilentlyContinue
}

Describe "Rate Limiting" {
    $TestDir = Join-Path $env:TEMP "ralph-rate-test-$(Get-Random)"
    New-Item -Path $TestDir -ItemType Directory -Force | Out-Null
    Push-Location $TestDir
    Initialize-RalphDirectory | Out-Null

    # Set low rate limit for testing
    $config = Get-RalphConfig
    $config.rateLimiting.maxCallsPerHour = 3
    Save-RalphConfig -Config $config

    Context "Add-CallTimestamp and Test-RateLimitOk" {
        It "Should allow calls under limit" {
            Save-CallTimestamps -Timestamps @()

            Add-CallTimestamp
            $result = Test-RateLimitOk
            $result.Ok | Should Be $true
            $result.CallsInWindow | Should Be 1
        }

        It "Should block when at limit" {
            Save-CallTimestamps -Timestamps @()

            Add-CallTimestamp
            Add-CallTimestamp
            Add-CallTimestamp

            $result = Test-RateLimitOk
            $result.Ok | Should Be $false
            $result.CallsInWindow | Should Be 3
            $result.WaitSeconds | Should BeGreaterThan 0
        }
    }

    Pop-Location
    Remove-Item -Path $TestDir -Recurse -Force -ErrorAction SilentlyContinue
}

Describe "Stop Signal" {
    $TestDir = Join-Path $env:TEMP "ralph-stop-test-$(Get-Random)"
    New-Item -Path $TestDir -ItemType Directory -Force | Out-Null
    Push-Location $TestDir
    Initialize-RalphDirectory | Out-Null

    Context "Stop Signal Operations" {
        It "Should not have stop signal initially" {
            Clear-StopSignal
            Test-StopSignal | Should Be $false
        }

        It "Should set and detect stop signal" {
            Set-StopSignal
            Test-StopSignal | Should Be $true
        }

        It "Should clear stop signal" {
            Set-StopSignal
            Clear-StopSignal
            Test-StopSignal | Should Be $false
        }
    }

    Pop-Location
    Remove-Item -Path $TestDir -Recurse -Force -ErrorAction SilentlyContinue
}

Describe "Port Management" {
    Context "Find-AvailablePort" {
        It "Should find an available port" {
            $port = Find-AvailablePort -StartPort 5000
            $port | Should Not Be $null
            ($port -ge 5000) | Should Be $true
        }

        It "Should skip ports in use" {
            $testPort = 5555
            $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $testPort)
            $listener.Start()

            try {
                $port = Find-AvailablePort -StartPort $testPort
                $port | Should BeGreaterThan $testPort
            } finally {
                $listener.Stop()
            }
        }
    }

    Context "Test-PortInUse" {
        It "Should return false for available port" {
            $result = Test-PortInUse -Port 59999
            $result | Should Be $false
        }

        It "Should return true for port in use" {
            $testPort = 5556
            # Bind to Any (0.0.0.0) to match what Test-PortInUse checks
            $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $testPort)
            $listener.Start()

            try {
                $result = Test-PortInUse -Port $testPort
                $result | Should Be $true
            } finally {
                $listener.Stop()
            }
        }
    }
}

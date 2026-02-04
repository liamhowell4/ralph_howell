#Requires -Version 5.1

<#
.SYNOPSIS
    Pester tests for Ralph Howell Loop dependency management
.DESCRIPTION
    Tests for dependency validation, circular dependency detection,
    dependency graph building, and dependency-aware task selection.
    Compatible with Pester 3.4+
#>

$ScriptDir = Split-Path -Parent $PSScriptRoot
. (Join-Path $ScriptDir "scripts\utils.ps1")

Describe "Dependency Validation" {
    Context "Test-DependencyValidation" {
        It "Should pass validation for PRD with no dependencies" {
            $prd = @{
                tasks = @(
                    @{ id = 1; title = "Task 1"; dependencies = @() },
                    @{ id = 2; title = "Task 2"; dependencies = @() }
                )
            }
            $result = Test-DependencyValidation -Prd $prd
            $result.Valid | Should Be $true
            $result.Errors.Count | Should Be 0
        }

        It "Should pass validation for valid dependencies" {
            $prd = @{
                tasks = @(
                    @{ id = 1; title = "Task 1"; dependencies = @() },
                    @{ id = 2; title = "Task 2"; dependencies = @(1) },
                    @{ id = 3; title = "Task 3"; dependencies = @(1, 2) }
                )
            }
            $result = Test-DependencyValidation -Prd $prd
            $result.Valid | Should Be $true
            $result.Errors.Count | Should Be 0
        }

        It "Should fail validation for non-existent dependency" {
            $prd = @{
                tasks = @(
                    @{ id = 1; title = "Task 1"; dependencies = @() },
                    @{ id = 2; title = "Task 2"; dependencies = @(99) }
                )
            }
            $result = Test-DependencyValidation -Prd $prd
            $result.Valid | Should Be $false
            $result.Errors.Count | Should BeGreaterThan 0
            $result.Errors[0] | Should Match "non-existent task 99"
        }

        It "Should fail validation for self-reference" {
            $prd = @{
                tasks = @(
                    @{ id = 1; title = "Task 1"; dependencies = @(1) }
                )
            }
            $result = Test-DependencyValidation -Prd $prd
            $result.Valid | Should Be $false
            $result.Errors[0] | Should Match "cannot depend on itself"
        }

        It "Should handle empty tasks array" {
            $prd = @{ tasks = @() }
            $result = Test-DependencyValidation -Prd $prd
            $result.Valid | Should Be $true
        }

        It "Should handle null dependencies array" {
            $prd = @{
                tasks = @(
                    @{ id = 1; title = "Task 1" },
                    @{ id = 2; title = "Task 2" }
                )
            }
            $result = Test-DependencyValidation -Prd $prd
            $result.Valid | Should Be $true
        }
    }

    Context "Test-DependencyValidation with subtasks" {
        It "Should allow subtasks to depend on siblings" {
            $prd = @{
                tasks = @(
                    @{
                        id = 1
                        title = "Parent Task"
                        subtasks = @(
                            @{ id = "1.1"; title = "Subtask 1"; dependencies = @() },
                            @{ id = "1.2"; title = "Subtask 2"; dependencies = @("1.1") }
                        )
                    }
                )
            }
            $result = Test-DependencyValidation -Prd $prd
            $result.Valid | Should Be $true
        }

        It "Should block subtasks from depending on subtasks of different parent" {
            $prd = @{
                tasks = @(
                    @{
                        id = 1
                        title = "Parent Task 1"
                        subtasks = @(
                            @{ id = "1.1"; title = "Subtask 1.1"; dependencies = @() }
                        )
                    },
                    @{
                        id = 2
                        title = "Parent Task 2"
                        subtasks = @(
                            @{ id = "2.1"; title = "Subtask 2.1"; dependencies = @("1.1") }
                        )
                    }
                )
            }
            $result = Test-DependencyValidation -Prd $prd
            $result.Valid | Should Be $false
            $result.Errors[0] | Should Match "different parent"
        }

        It "Should allow subtasks to depend on parent task" {
            $prd = @{
                tasks = @(
                    @{ id = 1; title = "First Task"; dependencies = @() },
                    @{
                        id = 2
                        title = "Parent Task"
                        subtasks = @(
                            @{ id = "2.1"; title = "Subtask"; dependencies = @(1) }
                        )
                    }
                )
            }
            $result = Test-DependencyValidation -Prd $prd
            $result.Valid | Should Be $true
        }

        It "Should block top-level task from depending on subtask" {
            $prd = @{
                tasks = @(
                    @{
                        id = 1
                        title = "First Task"
                        subtasks = @(
                            @{ id = "1.1"; title = "Subtask"; dependencies = @() }
                        )
                    },
                    @{ id = 2; title = "Second Task"; dependencies = @("1.1") }
                )
            }
            $result = Test-DependencyValidation -Prd $prd
            $result.Valid | Should Be $false
            $result.Errors[0] | Should Match "cannot depend on subtask"
        }
    }
}

Describe "Circular Dependency Detection" {
    Context "Test-CircularDependencies" {
        It "Should detect no cycle in valid DAG" {
            $prd = @{
                tasks = @(
                    @{ id = 1; title = "Task 1"; dependencies = @() },
                    @{ id = 2; title = "Task 2"; dependencies = @(1) },
                    @{ id = 3; title = "Task 3"; dependencies = @(1, 2) }
                )
            }
            $result = Test-CircularDependencies -Prd $prd
            $result.HasCycle | Should Be $false
        }

        It "Should detect simple cycle" {
            $prd = @{
                tasks = @(
                    @{ id = 1; title = "Task 1"; dependencies = @(2) },
                    @{ id = 2; title = "Task 2"; dependencies = @(1) }
                )
            }
            $result = Test-CircularDependencies -Prd $prd
            $result.HasCycle | Should Be $true
            $result.CyclePath.Count | Should BeGreaterThan 1
        }

        It "Should detect longer cycle" {
            $prd = @{
                tasks = @(
                    @{ id = 1; title = "Task 1"; dependencies = @(3) },
                    @{ id = 2; title = "Task 2"; dependencies = @(1) },
                    @{ id = 3; title = "Task 3"; dependencies = @(2) }
                )
            }
            $result = Test-CircularDependencies -Prd $prd
            $result.HasCycle | Should Be $true
        }

        It "Should handle empty task list" {
            $prd = @{ tasks = @() }
            $result = Test-CircularDependencies -Prd $prd
            $result.HasCycle | Should Be $false
        }

        It "Should handle single task with no dependencies" {
            $prd = @{
                tasks = @(
                    @{ id = 1; title = "Only Task"; dependencies = @() }
                )
            }
            $result = Test-CircularDependencies -Prd $prd
            $result.HasCycle | Should Be $false
        }
    }
}

Describe "Dependency Graph Building" {
    Context "Build-DependencyGraph" {
        It "Should build graph with correct nodes" {
            $prd = @{
                tasks = @(
                    @{ id = 1; title = "Task 1"; dependencies = @() },
                    @{ id = 2; title = "Task 2"; dependencies = @(1) },
                    @{ id = 3; title = "Task 3"; dependencies = @(1) }
                )
            }
            $graph = Build-DependencyGraph -Prd $prd
            $graph.nodes.Count | Should Be 3
            ($graph.nodes -contains 1) | Should Be $true
            ($graph.nodes -contains 2) | Should Be $true
            ($graph.nodes -contains 3) | Should Be $true
        }

        It "Should build graph with correct edges" {
            $prd = @{
                tasks = @(
                    @{ id = 1; title = "Task 1"; dependencies = @() },
                    @{ id = 2; title = "Task 2"; dependencies = @(1) }
                )
            }
            $graph = Build-DependencyGraph -Prd $prd
            $graph.edges.Count | Should Be 1
            $graph.edges[0].from | Should Be 1
            $graph.edges[0].to | Should Be 2
        }

        It "Should build correct adjacency list" {
            $prd = @{
                tasks = @(
                    @{ id = 1; title = "Task 1"; dependencies = @() },
                    @{ id = 2; title = "Task 2"; dependencies = @(1) },
                    @{ id = 3; title = "Task 3"; dependencies = @(1) }
                )
            }
            $graph = Build-DependencyGraph -Prd $prd
            # Task 1 should have tasks 2 and 3 as dependents
            $graph.adjacencyList[1].Count | Should Be 2
            ($graph.adjacencyList[1] -contains 2) | Should Be $true
            ($graph.adjacencyList[1] -contains 3) | Should Be $true
        }

        It "Should handle empty PRD" {
            $prd = @{ tasks = @() }
            $graph = Build-DependencyGraph -Prd $prd
            $graph.nodes.Count | Should Be 0
            $graph.edges.Count | Should Be 0
        }

        It "Should include subtasks in graph" {
            $prd = @{
                tasks = @(
                    @{
                        id = 1
                        title = "Task 1"
                        subtasks = @(
                            @{ id = "1.1"; title = "Subtask 1"; dependencies = @() },
                            @{ id = "1.2"; title = "Subtask 2"; dependencies = @("1.1") }
                        )
                    }
                )
            }
            $graph = Build-DependencyGraph -Prd $prd
            ($graph.nodes -contains 1) | Should Be $true
            ($graph.nodes -contains "1.1") | Should Be $true
            ($graph.nodes -contains "1.2") | Should Be $true
        }
    }
}

Describe "Dependency-Aware Task Selection" {
    Context "Get-NextAvailableTask" {
        It "Should return first pending task when no dependencies" {
            $prd = @{
                tasks = @(
                    @{ id = 1; title = "Task 1"; status = "pending"; dependencies = @() },
                    @{ id = 2; title = "Task 2"; status = "pending"; dependencies = @() }
                )
            }
            $task = Get-NextAvailableTask -Prd $prd
            $task.id | Should Be 1
        }

        It "Should return task with satisfied dependencies" {
            $prd = @{
                tasks = @(
                    @{ id = 1; title = "Task 1"; status = "completed"; dependencies = @() },
                    @{ id = 2; title = "Task 2"; status = "pending"; dependencies = @(1) }
                )
            }
            $task = Get-NextAvailableTask -Prd $prd
            $task.id | Should Be 2
        }

        It "Should skip task with unsatisfied dependencies" {
            $prd = @{
                tasks = @(
                    @{ id = 1; title = "Task 1"; status = "pending"; dependencies = @() },
                    @{ id = 2; title = "Task 2"; status = "pending"; dependencies = @(1) }
                )
            }
            $task = Get-NextAvailableTask -Prd $prd
            $task.id | Should Be 1
        }

        It "Should return null when all pending tasks have unmet dependencies" {
            $prd = @{
                tasks = @(
                    @{ id = 1; title = "Task 1"; status = "blocked"; dependencies = @() },
                    @{ id = 2; title = "Task 2"; status = "pending"; dependencies = @(1) }
                )
            }
            $task = Get-NextAvailableTask -Prd $prd
            $task | Should Be $null
        }

        It "Should return in_progress task" {
            $prd = @{
                tasks = @(
                    @{ id = 1; title = "Task 1"; status = "completed"; dependencies = @() },
                    @{ id = 2; title = "Task 2"; status = "in_progress"; dependencies = @(1) },
                    @{ id = 3; title = "Task 3"; status = "pending"; dependencies = @(1) }
                )
            }
            $task = Get-NextAvailableTask -Prd $prd
            $task.id | Should Be 2
        }

        It "Should return null when all tasks completed" {
            $prd = @{
                tasks = @(
                    @{ id = 1; title = "Task 1"; status = "completed"; dependencies = @() },
                    @{ id = 2; title = "Task 2"; status = "completed"; dependencies = @(1) }
                )
            }
            $task = Get-NextAvailableTask -Prd $prd
            $task | Should Be $null
        }

        It "Should handle multiple dependencies" {
            $prd = @{
                tasks = @(
                    @{ id = 1; title = "Task 1"; status = "completed"; dependencies = @() },
                    @{ id = 2; title = "Task 2"; status = "completed"; dependencies = @() },
                    @{ id = 3; title = "Task 3"; status = "pending"; dependencies = @(1, 2) }
                )
            }
            $task = Get-NextAvailableTask -Prd $prd
            $task.id | Should Be 3
        }

        It "Should block task when not all dependencies completed" {
            $prd = @{
                tasks = @(
                    @{ id = 1; title = "Task 1"; status = "completed"; dependencies = @() },
                    @{ id = 2; title = "Task 2"; status = "pending"; dependencies = @() },
                    @{ id = 3; title = "Task 3"; status = "pending"; dependencies = @(1, 2) }
                )
            }
            $task = Get-NextAvailableTask -Prd $prd
            # Should return task 2 since task 3's dependency on task 2 is not met
            $task.id | Should Be 2
        }
    }
}

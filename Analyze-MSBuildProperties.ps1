#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Analyzes .sln and project files to display all MSBuild properties that can be set with /p parameter.

.DESCRIPTION
    Parses a solution file and its linked projects to extract and display all MSBuild properties
    that can be overridden using the /p:PropertyName=Value parameter.

.PARAMETER SolutionPath
    Path to the .sln file to analyze. If not provided, searches for .sln files in current directory.

.EXAMPLE
    .\Analyze-MSBuildProperties.ps1 -SolutionPath "MySolution.sln"

.EXAMPLE
    .\Analyze-MSBuildProperties.ps1
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$SolutionPath
)

# Color output helper
function Write-ColorOutput {
    param(
        [string]$Message,
        [ConsoleColor]$ForegroundColor = [ConsoleColor]::White
    )
    $originalColor = $Host.UI.RawUI.ForegroundColor
    $Host.UI.RawUI.ForegroundColor = $ForegroundColor
    Write-Output $Message
    $Host.UI.RawUI.ForegroundColor = $originalColor
}

# Parse solution file to extract project paths
function Get-ProjectsFromSolution {
    param([string]$SolutionFile)
    
    if (-not (Test-Path $SolutionFile)) {
        Write-ColorOutput "Error: Solution file not found: $SolutionFile" Red
        return @()
    }
    
    $solutionDir = Split-Path -Parent $SolutionFile
    $content = Get-Content $SolutionFile -Raw
    
    # Regex to match project lines in .sln file
    # Format: Project("{GUID}") = "ProjectName", "RelativePath", "{ProjectGUID}"
    $projectPattern = 'Project\("\{[A-F0-9\-]+\}"\)\s*=\s*"[^"]+",\s*"([^"]+\.(?:csproj|vbproj|fsproj|vcxproj))"\s*,'
    
    $projects = @()
    $matches = [regex]::Matches($content, $projectPattern)
    
    foreach ($match in $matches) {
        $relativePath = $match.Groups[1].Value
        $projectPath = Join-Path $solutionDir $relativePath
        $projectPath = [System.IO.Path]::GetFullPath($projectPath)
        
        if (Test-Path $projectPath) {
            $projects += $projectPath
        } else {
            Write-ColorOutput "Warning: Project file not found: $projectPath" Yellow
        }
    }
    
    return $projects
}

# Parse project file to extract properties
function Get-MSBuildProperties {
    param([string]$ProjectFile)
    
    if (-not (Test-Path $ProjectFile)) {
        return @{}
    }
    
    $properties = @{}
    
    try {
        [xml]$projectXml = Get-Content $ProjectFile -Raw
        
        # Find all PropertyGroup elements
        $propertyGroups = $projectXml.Project.PropertyGroup
        
        foreach ($group in $propertyGroups) {
            if ($null -eq $group) { continue }
            
            # Get all child elements (properties)
            $groupProperties = $group.ChildNodes
            
            foreach ($prop in $groupProperties) {
                if ($prop.NodeType -eq 'Element') {
                    $propName = $prop.LocalName
                    $propValue = $prop.InnerText
                    $condition = $prop.Condition
                    
                    if (-not $properties.ContainsKey($propName)) {
                        $properties[$propName] = @{
                            Values = @()
                            Conditions = @()
                        }
                    }
                    
                    $properties[$propName].Values += $propValue
                    if ($condition) {
                        $properties[$propName].Conditions += $condition
                    }
                }
            }
        }
        
        # Also check for common imported properties from SDK-style projects
        $sdk = $projectXml.Project.Sdk
        if ($sdk) {
            $properties['_SDKReference'] = @{
                Values = @($sdk)
                Conditions = @()
            }
        }
        
    } catch {
        Write-ColorOutput "Error parsing project file $ProjectFile : $_" Red
    }
    
    return $properties
}

# Get common MSBuild properties with descriptions
function Get-CommonMSBuildProperties {
    return @{
        # Build Configuration
        'Configuration' = 'Build configuration (e.g., Debug, Release)'
        'Platform' = 'Target platform (e.g., AnyCPU, x86, x64)'
        'TargetFramework' = 'Target framework (e.g., net8.0, net472)'
        'RuntimeIdentifier' = 'Runtime identifier for self-contained deployments'
        
        # Output
        'OutputPath' = 'Output directory path'
        'OutDir' = 'Output directory (alternative to OutputPath)'
        'BaseOutputPath' = 'Base output path before configuration'
        'BaseIntermediateOutputPath' = 'Base path for intermediate build outputs'
        'IntermediateOutputPath' = 'Intermediate output path (obj folder)'
        
        # Assembly Info
        'AssemblyName' = 'Name of the output assembly'
        'RootNamespace' = 'Root namespace for the project'
        'AssemblyVersion' = 'Assembly version number'
        'FileVersion' = 'File version number'
        'InformationalVersion' = 'Informational version (display version)'
        'Version' = 'Package/NuGet version'
        'PackageVersion' = 'NuGet package version'
        
        # Compilation
        'DefineConstants' = 'Preprocessor definitions (e.g., DEBUG;TRACE)'
        'Optimize' = 'Enable code optimization (true/false)'
        'DebugType' = 'Debug symbol type (none, full, pdbonly, portable, embedded)'
        'DebugSymbols' = 'Generate debug symbols (true/false)'
        'TreatWarningsAsErrors' = 'Treat warnings as errors (true/false)'
        'WarningLevel' = 'Warning level (0-4)'
        'NoWarn' = 'Suppress specific warning codes'
        'AllowUnsafeBlocks' = 'Allow unsafe code blocks (true/false)'
        
        # Language
        'LangVersion' = 'C# language version (e.g., latest, 11.0, 10.0)'
        'Nullable' = 'Nullable reference types (enable, disable, warnings, annotations)'
        
        # .NET/NuGet
        'RestorePackages' = 'Enable NuGet package restore (true/false)'
        'GeneratePackageOnBuild' = 'Generate NuGet package on build (true/false)'
        'PackageId' = 'NuGet package identifier'
        'Authors' = 'Package authors'
        'Company' = 'Company name'
        'Product' = 'Product name'
        'Description' = 'Package description'
        'Copyright' = 'Copyright information'
        'PackageTags' = 'Package tags for NuGet'
        'RepositoryUrl' = 'Source repository URL'
        
        # Publishing
        'PublishDir' = 'Publish output directory'
        'PublishSingleFile' = 'Publish as single file (true/false)'
        'PublishTrimmed' = 'Enable trimming for self-contained apps (true/false)'
        'PublishReadyToRun' = 'Enable ReadyToRun compilation (true/false)'
        'SelfContained' = 'Build as self-contained (true/false)'
        
        # Code Analysis
        'RunAnalyzersDuringBuild' = 'Run analyzers during build (true/false)'
        'EnableNETAnalyzers' = 'Enable .NET code analyzers (true/false)'
        'AnalysisLevel' = 'Code analysis level (e.g., latest, 6.0)'
        'CodeAnalysisRuleSet' = 'Code analysis ruleset file'
        
        # Other
        'GenerateDocumentationFile' = 'Generate XML documentation file (true/false)'
        'DocumentationFile' = 'XML documentation file path'
        'AppendTargetFrameworkToOutputPath' = 'Append framework to output path (true/false)'
        'Deterministic' = 'Enable deterministic builds (true/false)'
        'ContinuousIntegrationBuild' = 'CI build mode (true/false)'
        'VersionPrefix' = 'Version prefix for versioning'
        'VersionSuffix' = 'Version suffix (e.g., beta, alpha)'
    }
}

# Main script
try {
    Write-ColorOutput "`n=== MSBuild Properties Analyzer ===" Cyan
    Write-ColorOutput "Analyzes .sln files and projects to show MSBuild /p properties`n" Gray
    
    # Find or validate solution file
    if (-not $SolutionPath) {
        $slnFiles = Get-ChildItem -Path . -Filter "*.sln" -File
        if ($slnFiles.Count -eq 0) {
            Write-ColorOutput "No solution files found in current directory." Red
            Write-ColorOutput "Please specify a solution file with -SolutionPath parameter." Yellow
            exit 1
        } elseif ($slnFiles.Count -eq 1) {
            $SolutionPath = $slnFiles[0].FullName
            Write-ColorOutput "Found solution: $($slnFiles[0].Name)" Green
        } else {
            Write-ColorOutput "Multiple solution files found:" Yellow
            $slnFiles | ForEach-Object { Write-ColorOutput "  - $($_.Name)" White }
            Write-ColorOutput "`nPlease specify one with -SolutionPath parameter." Yellow
            exit 1
        }
    }
    
    $SolutionPath = [System.IO.Path]::GetFullPath($SolutionPath)
    
    Write-ColorOutput "`nSolution: $SolutionPath" White
    Write-ColorOutput ("─" * 80) Gray
    
    # Parse solution
    $projects = Get-ProjectsFromSolution -SolutionFile $SolutionPath
    
    if ($projects.Count -eq 0) {
        Write-ColorOutput "`nNo projects found in solution." Red
        exit 1
    }
    
    Write-ColorOutput "`nFound $($projects.Count) project(s):" Green
    
    # Collect all properties from all projects
    $allProperties = @{}
    
    foreach ($projectPath in $projects) {
        $projectName = Split-Path -Leaf $projectPath
        Write-ColorOutput "  ├─ $projectName" Cyan
        
        $projectProps = Get-MSBuildProperties -ProjectFile $projectPath
        
        foreach ($propName in $projectProps.Keys) {
            if (-not $allProperties.ContainsKey($propName)) {
                $allProperties[$propName] = @{
                    Projects = @()
                    Values = @()
                }
            }
            
            $allProperties[$propName].Projects += $projectName
            $allProperties[$propName].Values += ($projectProps[$propName].Values | Select-Object -Unique)
        }
    }
    
    # Get common properties with descriptions
    $commonProps = Get-CommonMSBuildProperties
    
    Write-ColorOutput "`n`n=== MSBuild Properties Available for /p Parameter ===" Cyan
    Write-ColorOutput ("─" * 80) Gray
    
    Write-ColorOutput "`n[1] PROPERTIES FOUND IN PROJECT FILES" Yellow
    Write-ColorOutput "These properties are defined in your project files:`n" Gray
    
    $sortedProps = $allProperties.Keys | Sort-Object
    foreach ($propName in $sortedProps) {
        $prop = $allProperties[$propName]
        $uniqueValues = $prop.Values | Select-Object -Unique
        
        Write-ColorOutput "  • $propName" Green
        if ($commonProps.ContainsKey($propName)) {
            Write-ColorOutput "    Description: $($commonProps[$propName])" Gray
        }
        Write-ColorOutput "    Current value(s): $($uniqueValues -join ', ')" White
        Write-ColorOutput "    Used in: $($prop.Projects -join ', ')" DarkGray
        Write-ColorOutput "    Usage: /p:$propName=<value>`n" Cyan
    }
    
    Write-ColorOutput "`n[2] COMMON MSBUILD PROPERTIES NOT IN YOUR PROJECTS" Yellow
    Write-ColorOutput "These are common properties you can override:`n" Gray
    
    foreach ($propName in ($commonProps.Keys | Sort-Object)) {
        if (-not $allProperties.ContainsKey($propName)) {
            Write-ColorOutput "  • $propName" Magenta
            Write-ColorOutput "    Description: $($commonProps[$propName])" Gray
            Write-ColorOutput "    Usage: /p:$propName=<value>`n" Cyan
        }
    }
    
    Write-ColorOutput "`n=== USAGE EXAMPLES ===" Cyan
    Write-ColorOutput ("─" * 80) Gray
    Write-ColorOutput ""
    Write-ColorOutput "Build with specific configuration:" White
    Write-ColorOutput "  msbuild `"$SolutionPath`" /p:Configuration=Release" Gray
    Write-ColorOutput ""
    Write-ColorOutput "Build for specific platform:" White
    Write-ColorOutput "  msbuild `"$SolutionPath`" /p:Platform=x64" Gray
    Write-ColorOutput ""
    Write-ColorOutput "Multiple properties:" White
    Write-ColorOutput "  msbuild `"$SolutionPath`" /p:Configuration=Release /p:Platform=x64 /p:OutputPath=C:\Output" Gray
    Write-ColorOutput ""
    Write-ColorOutput "Set version during build:" White
    Write-ColorOutput "  msbuild `"$SolutionPath`" /p:Version=1.2.3 /p:AssemblyVersion=1.2.3.0" Gray
    Write-ColorOutput ""
    Write-ColorOutput "Enable optimizations:" White
    Write-ColorOutput "  msbuild `"$SolutionPath`" /p:Optimize=true /p:DebugType=none" Gray
    Write-ColorOutput ""
    
    Write-ColorOutput "`n=== SUMMARY ===" Cyan
    Write-ColorOutput ("─" * 80) Gray
    Write-ColorOutput "Total projects analyzed: $($projects.Count)" White
    Write-ColorOutput "Properties found in projects: $($allProperties.Count)" White
    Write-ColorOutput "Additional common properties: $(($commonProps.Keys | Where-Object { -not $allProperties.ContainsKey($_) }).Count)" White
    Write-ColorOutput ""
    
} catch {
    Write-ColorOutput "`nError: $_" Red
    Write-ColorOutput $_.ScriptStackTrace Red
    exit 1
}

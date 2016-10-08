properties {
  $zipFileName = "GraphQLParser.zip"
  $majorWithReleaseVersion = "2.0.0"
  $nugetPrerelease = $null
  $packageId = "GraphQL-Parser"
  $signAssemblies = $false
  $signKeyPath = "notspecified"
  $buildDocumentation = $false
  $buildNuGet = $true
  $treatWarningsAsErrors = $false
  $workingName = if ($workingName) {$workingName} else {"Working"}
  $netCliVersion = "1.0.0-preview3-003171"
  $revision = @{ $true = $env:APPVEYOR_BUILD_NUMBER; $false = 1 }[$env:APPVEYOR_BUILD_NUMBER -ne $NULL];

  if ($env:APPVEYOR_REPO_BRANCH -ne "master" -or $env:APPVEYOR_PULL_REQUEST_NUMBER -ne $NULL) {
    $nugetPrerelease = "build" + $revision
  }

  $baseDir  = resolve-path ..
  $buildDir = "$baseDir\Build"
  $sourceDir = "$baseDir\Src"
  $toolsDir = "$baseDir\Tools"
  $docDir = "$baseDir\Doc"
  $releaseDir = "$baseDir\Release"
  $workingDir = "$baseDir\$workingName"
  $workingSourceDir = "$workingDir\Src"
  $builds = @(
    @{Name = "GraphQLParser"; TestsName = "GraphQLParser.Tests"; BuildFunction = "NetCliBuild"; TestsFunction = "NetCliTests"; Constants="dotnet"; FinalDir="netstandard1.1"; NuGetDir = "net45,netstandard1.1"; Framework=$null}
  )
}

framework '4.6x86'

task default -depends Test

# Ensure a clean working directory
task Clean {
  Write-Host "Setting location to $baseDir"
  Set-Location $baseDir

  if (Test-Path -path $workingDir)
  {
    Write-Host "Deleting existing working directory $workingDir"

    Execute-Command -command { del $workingDir -Recurse -Force }
  }

  Write-Host "Creating working directory $workingDir"
  New-Item -Path $workingDir -ItemType Directory
}

# Build each solution, optionally signed
task Build -depends Clean {
  Write-Host "Copying source to working source directory $workingSourceDir"
  robocopy $sourceDir $workingSourceDir /MIR /NP /XD bin obj TestResults AppPackages $packageDirs .vs artifacts /XF *.suo *.user *.lock.json | Out-Default

  Write-Host -ForegroundColor Green "Updating assembly version"
  Write-Host
  Update-AssemblyInfoFiles $workingSourceDir ($majorWithReleaseVersion + '.' + $revision)

  Update-Project $workingSourceDir\GraphQLParser\project.json $signAssemblies

  foreach ($build in $builds)
  {
    $name = $build.Name
    if ($name -ne $null)
    {
      Write-Host -ForegroundColor Green "Building " $name
      Write-Host -ForegroundColor Green "Signed " $signAssemblies
      Write-Host -ForegroundColor Green "Key " $signKeyPath

      & $build.BuildFunction $build
    }
  }
}

# Optional build documentation, add files to final zip
task Package -depends Build {
  foreach ($build in $builds)
  {
    $name = $build.TestsName
    $finalDir = $build.FinalDir

    robocopy "$workingSourceDir\GraphQLParser\bin\Release\$finalDir" $workingDir\Package\Bin\$finalDir *.dll *.pdb *.xml /NFL /NDL /NJS /NC /NS /NP /XO /XF *.CodeAnalysisLog.xml | Out-Default
  }

  if ($buildNuGet)
  {
    Write-Host -ForegroundColor Green "Building NuGet"
    Write-Host
    exec { dotnet pack "$workingSourceDir\GraphQLParser" -o "$workingDir\NuGet" -c Release --version-suffix $revision  | Out-Default }
  }


  Write-Host "Build documentation: $buildDocumentation"

  if ($buildDocumentation)
  {
    $mainBuild = $builds | where { $_.Name -eq "GraphQLParser" } | select -first 1
    $mainBuildFinalDir = $mainBuild.FinalDir
    $documentationSourcePath = "$workingDir\Package\Bin\$mainBuildFinalDir"
    $docOutputPath = "$workingDir\Documentation\"
    Write-Host -ForegroundColor Green "Building documentation from $documentationSourcePath"
    Write-Host "Documentation output to $docOutputPath"

    # Sandcastle has issues when compiling with .NET 4 MSBuild - http://shfb.codeplex.com/Thread/View.aspx?ThreadId=50652
    exec { msbuild "/t:Clean;Rebuild" /p:Configuration=Release "/p:DocumentationSourcePath=$documentationSourcePath" "/p:OutputPath=$docOutputPath" $docDir\doc.shfbproj | Out-Default } "Error building documentation. Check that you have Sandcastle, Sandcastle Help File Builder and HTML Help Workshop installed."

    move -Path $workingDir\Documentation\LastBuild.log -Destination $workingDir\Documentation.log
  }

  Copy-Item -Path $docDir\readme.txt -Destination $workingDir\Package\
  Copy-Item -Path $docDir\license.txt -Destination $workingDir\Package\

  robocopy $workingSourceDir $workingDir\Package\Source\Src /MIR /NFL /NDL /NJS /NC /NS /NP /XD bin obj TestResults AppPackages .vs artifacts /XF *.suo *.user *.lock.json | Out-Default
  robocopy $buildDir $workingDir\Package\Source\Build /MIR /NFL /NDL /NJS /NC /NS /NP /XF runbuild.txt | Out-Default
  robocopy $docDir $workingDir\Package\Source\Doc /MIR /NFL /NDL /NJS /NC /NS /NP | Out-Default
  robocopy $toolsDir $workingDir\Package\Source\Tools /MIR /NFL /NDL /NJS /NC /NS /NP | Out-Default

  exec { .\Tools\7-zip\7za.exe a -tzip $workingDir\$zipFileName $workingDir\Package\* | Out-Default } "Error zipping"
}

# Unzip package to a location
task Deploy -depends Package {
  exec { .\Tools\7-zip\7za.exe x -y "-o$workingDir\Deployed" $workingDir\$zipFileName | Out-Default } "Error unzipping"
}

# Run tests on deployed files
task Test -depends Deploy {

  Update-Project $workingSourceDir\GraphQLParser\project.json $false

  foreach ($build in $builds)
  {
    if ($build.TestsFunction -ne $null)
    {
      & $build.TestsFunction $build
    }
  }
}

function MSBuildBuild($build)
{
  $name = $build.Name
  $finalDir = $build.FinalDir

  Write-Host
  Write-Host "Restoring $workingSourceDir\$name.sln" -ForegroundColor Green
  [Environment]::SetEnvironmentVariable("EnableNuGetPackageRestore", "true", "Process")
  exec { .\Tools\NuGet\NuGet.exe update -self }
  exec { .\Tools\NuGet\NuGet.exe restore "$workingSourceDir\$name.sln" -verbosity detailed -configfile $workingSourceDir\nuget.config | Out-Default } "Error restoring $name"

  $constants = GetConstants $build.Constants $signAssemblies

  Write-Host
  Write-Host "Building $workingSourceDir\$name.sln" -ForegroundColor Green
  exec { msbuild "/t:Clean;Rebuild" /p:Configuration=Release "/p:CopyNuGetImplementations=true" "/p:Platform=Any CPU" "/p:PlatformTarget=AnyCPU" /p:OutputPath=bin\Release\$finalDir\ /p:AssemblyOriginatorKeyFile=$signKeyPath "/p:SignAssembly=$signAssemblies" "/p:TreatWarningsAsErrors=$treatWarningsAsErrors" "/p:VisualStudioVersion=14.0" /p:DefineConstants=`"$constants`" "$workingSourceDir\$name.sln" | Out-Default } "Error building $name"
}

function NetCliBuild($build)
{
  $name = $build.Name
  $projectPath = "$workingSourceDir\GraphQLParser\project.json"

  # exec { .\Tools\Dotnet\dotnet-install.ps1 -Version $netCliVersion | Out-Default }
  exec { dotnet --version | Out-Default }

  Write-Host -ForegroundColor Green "Restoring packages for $name"
  Write-Host
  exec { dotnet restore $projectPath | Out-Default }

  Write-Host -ForegroundColor Green "Building $projectPath"
  exec { dotnet build $projectPath -c Release | Out-Default }
  exec { dotnet build $projectPath -c Debug | Out-Default }
}

function NetCliTests($build)
{
  $name = $build.TestsName

  # exec { .\Tools\Dotnet\dotnet-install.ps1 -Version $netCliVersion | Out-Default }
  exec { dotnet --version | Out-Default }

  Write-Host -ForegroundColor Green "Restoring packages for $name"
  Write-Host
  exec { dotnet restore "$workingSourceDir\GraphQLParser.Tests\project.json" | Out-Default }

  Write-Host -ForegroundColor Green "Ensuring test project builds for $name"
  Write-Host

  try
  {
    Set-Location "$workingSourceDir\GraphQLParser.Tests"
    exec { dotnet test "$workingSourceDir\GraphQLParser.Tests" -c Release | Out-Default }
  }
  finally
  {
    Set-Location $baseDir
  }
}

function NUnitTests($build)
{
  $name = $build.TestsName
  $finalDir = $build.FinalDir
  $framework = $build.Framework

  Write-Host -ForegroundColor Green "Copying test assembly $name to deployed directory"
  Write-Host
  robocopy "$workingSourceDir\GraphQLParser.Tests\bin\Release\$finalDir" $workingDir\Deployed\Bin\$finalDir /MIR /NFL /NDL /NJS /NC /NS /NP /XO | Out-Default

  Copy-Item -Path "$workingSourceDir\GraphQLParser.Tests\bin\Release\$finalDir\GraphQLParser.Tests.dll" -Destination $workingDir\Deployed\Bin\$finalDir\

  Write-Host -ForegroundColor Green "Running NUnit tests " $name
  Write-Host
  exec { .\Tools\NUnit\nunit-console.exe "$workingDir\Deployed\Bin\$finalDir\GraphQLParser.Tests.dll" /framework=$framework /xml:$workingDir\$name.xml | Out-Default } "Error running $name tests"
}

function GetNuGetVersion()
{
  $nugetVersion = $majorWithReleaseVersion
  if ($nugetPrerelease -ne $null)
  {
    $nugetVersion = $nugetVersion + "-" + $nugetPrerelease
  }

  return $nugetVersion
}

function GetConstants($constants, $includeSigned)
{
  $signed = switch($includeSigned) { $true { ";SIGNED" } default { "" } }

  return "CODE_ANALYSIS;TRACE;$constants$signed"
}

function Update-AssemblyInfoFiles ([string] $workingSourceDir, [string] $assemblyVersionNumber)
{
    $assemblyVersionPattern = 'AssemblyVersion\("[0-9]+(\.([0-9]+|\*)){1,3}"\)'
    $fileVersionPattern = 'AssemblyFileVersion\("[0-9]+(\.([0-9]+|\*)){1,3}"\)'
    $assemblyVersion = 'AssemblyVersion("' + $assemblyVersionNumber + '")';
    $fileVersion = 'AssemblyFileVersion("' + $assemblyVersionNumber + '")';

    Get-ChildItem -Path $workingSourceDir -r -filter AssemblyInfo.cs | ForEach-Object {

        $filename = $_.Directory.ToString() + '\' + $_.Name
        Write-Host $filename + ' -> ' + $assemblyVersionNumber

        (Get-Content $filename) | ForEach-Object {
            % {$_ -replace $assemblyVersionPattern, $assemblyVersion } |
            % {$_ -replace $fileVersionPattern, $fileVersion }
        } | Set-Content $filename
    }
}

function Edit-XmlNodes {
    param (
        [xml] $doc,
        [string] $xpath = $(throw "xpath is a required parameter"),
        [string] $value = $(throw "value is a required parameter")
    )

    $nodes = $doc.SelectNodes($xpath)
    $count = $nodes.Count

    Write-Host "Found $count nodes with path '$xpath'"

    foreach ($node in $nodes) {
        if ($node -ne $null) {
            if ($node.NodeType -eq "Element")
            {
                $node.InnerXml = $value
            }
            else
            {
                $node.Value = $value
            }
        }
    }
}

function Update-Project {
  param (
    [string] $projectPath,
    [string] $sign
  )

  $file = switch($sign) { $true { $signKeyPath } default { $null } }

  $json = (Get-Content $projectPath) -join "`n" | ConvertFrom-Json
  $options = @{"warningsAsErrors" = $true; "xmlDoc" = $false; "keyFile" = $file; "define" = ((GetConstants "dotnet" $sign) -split ";") }
  Add-Member -InputObject $json -MemberType NoteProperty -Name "buildOptions" -Value $options -Force

  $json.version = GetNuGetVersion

  ConvertTo-Json $json -Depth 10 | Set-Content $projectPath
}

function Execute-Command($command) {
    $currentRetry = 0
    $success = $false
    do {
        try
        {
            & $command
            $success = $true
        }
        catch [System.Exception]
        {
            if ($currentRetry -gt 5) {
                throw $_.Exception.ToString()
            } else {
                write-host "Retry $currentRetry"
                Start-Sleep -s 1
            }
            $currentRetry = $currentRetry + 1
        }
    } while (!$success)
}

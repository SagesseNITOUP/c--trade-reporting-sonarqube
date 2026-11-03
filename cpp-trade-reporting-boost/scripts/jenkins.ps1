[CmdletBinding()]
param(
    [ValidateSet('start', 'build', 'status', 'all')]
    [string]$Action = 'start'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$localDirectory = Join-Path $projectRoot '.local'
$credentialsPath = Join-Path $localDirectory 'jenkins-credentials.json'
$jenkinsUrl = 'http://localhost:8080'
$jobName = 'trade-reporting-coverage'

function Invoke-Docker {
    param([string[]]$DockerArguments)
    & docker @DockerArguments
    if ($LASTEXITCODE -ne 0) { throw "Docker a echoue (code $LASTEXITCODE)." }
}

function New-BasicHeaders {
    param([string]$Username, [string]$Password)
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("${Username}:$Password"))
    return @{ Authorization = "Basic $encoded" }
}

function Initialize-LocalSecrets {
    New-Item -ItemType Directory -Path $localDirectory -Force | Out-Null
    if (-not (Test-Path -LiteralPath $credentialsPath)) {
        [pscustomobject]@{
            serverUrl = $jenkinsUrl
            username = 'admin'
            password = ([guid]::NewGuid().ToString('N') + 'aA1!')
        } | ConvertTo-Json | Set-Content -LiteralPath $credentialsPath -Encoding UTF8
    }
    $credentials = Get-Content -Raw -LiteralPath $credentialsPath | ConvertFrom-Json
    $credentials.password | Set-Content -LiteralPath (Join-Path $localDirectory 'jenkins-admin-password') -Encoding ASCII

    $sonarTokenPath = Join-Path $localDirectory 'jenkins-sonar-token'
    if (-not (Test-Path -LiteralPath $sonarTokenPath)) {
        if ($env:SONAR_TOKEN) {
            $tokenValue = $env:SONAR_TOKEN
        } else {
            $sonarCredentialsPath = Join-Path $localDirectory 'sonar-credentials.json'
            if (-not (Test-Path -LiteralPath $sonarCredentialsPath)) {
                throw 'Definir SONAR_TOKEN, ou initialiser SonarQube avec scripts/sonar.ps1 all.'
            }
            $sonarCredentials = Get-Content -Raw -LiteralPath $sonarCredentialsPath | ConvertFrom-Json
            $headers = New-BasicHeaders $sonarCredentials.username $sonarCredentials.password
            $generatedToken = Invoke-RestMethod 'http://localhost:9000/api/user_tokens/generate' -Method Post -Headers $headers -Body @{
                name = ('jenkins-coverage-' + [guid]::NewGuid().ToString('N'))
                type = 'PROJECT_ANALYSIS_TOKEN'; projectKey = 'trade-reporting-boost-demo'
            }
            $tokenValue = $generatedToken.token
        }
        $tokenValue | Set-Content -LiteralPath $sonarTokenPath -Encoding ASCII
    }
}

function Get-JenkinsHeaders {
    if (-not (Test-Path -LiteralPath $credentialsPath)) {
        throw 'Identifiants absents. Lancer scripts/jenkins.ps1 start.'
    }
    $credentials = Get-Content -Raw -LiteralPath $credentialsPath | ConvertFrom-Json
    return New-BasicHeaders $credentials.username $credentials.password
}

function Wait-Jenkins {
    $headers = Get-JenkinsHeaders
    Write-Host 'Attente de Jenkins et du job de couverture (premier demarrage : plusieurs minutes)...'
    $deadline = (Get-Date).AddMinutes(10)
    do {
        try {
            Invoke-RestMethod "$jenkinsUrl/job/$jobName/api/json" -Headers $headers -TimeoutSec 5 | Out-Null
            return
        } catch { }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)
    throw 'Jenkins indisponible. Consulter : docker compose logs --tail 100 jenkins'
}

function Start-Jenkins {
    Initialize-LocalSecrets
    Invoke-Docker -DockerArguments @('compose', 'up', '-d', '--build', 'jenkins')
    Wait-Jenkins
    Write-Host "Jenkins : $jenkinsUrl/job/$jobName/"
    Write-Host "Identifiants locaux : $credentialsPath"
}

function Start-CoverageBuild {
    Wait-Jenkins
    $headers = Get-JenkinsHeaders
    $webSession = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    $crumb = Invoke-RestMethod "$jenkinsUrl/crumbIssuer/api/json" -Headers $headers -WebSession $webSession
    $headers[$crumb.crumbRequestField] = $crumb.crumb
    $response = Invoke-WebRequest -UseBasicParsing "$jenkinsUrl/job/$jobName/build" -Method Post -Headers $headers -WebSession $webSession
    $queueUrl = [string]$response.Headers['Location']
    if (-not $queueUrl) { throw 'Jenkins ne retourne pas de numero de file de build.' }
    $deadline = (Get-Date).AddMinutes(25)
    Write-Host 'Build Jenkins declenche. Attente des tests, de la couverture et du Quality Gate...'
    do {
        $queued = Invoke-RestMethod "${queueUrl}api/json" -Headers $headers -WebSession $webSession
        if ($queued.cancelled) { throw 'Build Jenkins annule.' }
        if ($queued.executable.url) { break }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)
    if (-not $queued.executable.url) { throw 'Delai depasse dans la file Jenkins.' }
    $buildUrl = $queued.executable.url
    do {
        $build = Invoke-RestMethod "${buildUrl}api/json" -Headers $headers -WebSession $webSession
        if (-not $build.building) { break }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)
    $build | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $localDirectory 'jenkins-last-build.json') -Encoding UTF8
    Invoke-RestMethod "${buildUrl}consoleText" -Headers $headers -WebSession $webSession |
        Set-Content -LiteralPath (Join-Path $localDirectory 'jenkins-last-console.log') -Encoding UTF8
    Write-Host "Build #$($build.number) : $($build.result) - $buildUrl"
    if ($build.result -ne 'SUCCESS') {
        throw "Build non valide. Lire ${buildUrl}console ou .local/jenkins-last-console.log."
    }
}

Push-Location $projectRoot
try {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw 'Docker et Compose sont requis.' }
    switch ($Action) {
        'start' { Start-Jenkins }
        'build' { Start-CoverageBuild }
        'all' { Start-Jenkins; Start-CoverageBuild }
        'status' {
            Invoke-Docker -DockerArguments @('compose', 'ps', 'jenkins')
            Invoke-RestMethod "$jenkinsUrl/job/$jobName/api/json" -Headers (Get-JenkinsHeaders) |
                Select-Object name, color, nextBuildNumber
        }
    }
} finally {
    Pop-Location
}

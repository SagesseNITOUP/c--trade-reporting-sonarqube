[CmdletBinding()]
param(
    [ValidateSet('coverage', 'start', 'init', 'analyze', 'all', 'status')]
    [string]$Action = 'coverage'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$serverUrl = 'http://localhost:9000'
$projectKey = 'trade-reporting-boost-demo'
$credentialsPath = Join-Path $projectRoot '.local/sonar-credentials.json'

function Invoke-Docker {
    param([string[]]$DockerArguments)
    & docker @DockerArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Docker a echoue (code $LASTEXITCODE). Voir la sortie ci-dessus."
    }
}

function Wait-Sonar {
    Write-Host 'Attente de SonarQube (le premier demarrage peut prendre plusieurs minutes)...'
    $deadline = (Get-Date).AddMinutes(5)
    do {
        try {
            $state = Invoke-RestMethod "$serverUrl/api/system/status" -TimeoutSec 5
            if ($state.status -eq 'UP') { return }
        } catch { }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)
    throw 'SonarQube indisponible. Consulter : docker compose logs --tail 100 sonarqube'
}

function Start-Sonar {
    $pluginName = 'sonar-cxx-plugin-2.3.1.1656.jar'
    $pluginPath = Join-Path $projectRoot "sonar-extensions/plugins/$pluginName"
    $expectedHash = 'b64327bf680a9fe4a04bb04f13ecbe679f4611c6908ec9eb0df027229d183a8a'
    if (-not (Test-Path -LiteralPath $pluginPath)) {
        Write-Host 'Telechargement du plugin open source sonar-cxx 2.3.1...'
        $downloadPath = "$pluginPath.download"
        Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/SonarOpenCommunity/sonar-cxx/releases/download/cxx-2.3.1/$pluginName" -OutFile $downloadPath
        if ((Get-FileHash -LiteralPath $downloadPath -Algorithm SHA256).Hash -ne $expectedHash) {
            Remove-Item -LiteralPath $downloadPath
            throw 'SHA256 du plugin incorrect : installation annulee.'
        }
        Move-Item -LiteralPath $downloadPath -Destination $pluginPath
    }
    if ((Get-FileHash -LiteralPath $pluginPath -Algorithm SHA256).Hash -ne $expectedHash) {
        throw "SHA256 du plugin incorrect : verifier $pluginPath"
    }
    Invoke-Docker -DockerArguments @('compose', 'up', '-d', 'sonarqube')
    Wait-Sonar
    Write-Host "SonarQube disponible : $serverUrl"
}

function Get-BasicHeaders {
    param([string]$Username, [string]$Password)
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("${Username}:$Password"))
    return @{ Authorization = "Basic $encoded" }
}

function Save-LocalCredentials {
    param($Credentials)
    New-Item -ItemType Directory -Path (Split-Path -Parent $credentialsPath) -Force | Out-Null
    $Credentials | ConvertTo-Json | Set-Content -LiteralPath $credentialsPath -Encoding UTF8
}

function Initialize-Sonar {
    Wait-Sonar
    if ($env:SONAR_TOKEN) {
        Write-Host 'SONAR_TOKEN fourni : utiliser le projet existant avec cette cle.'
        return
    }
    $localCredentials = $null
    if (Test-Path -LiteralPath $credentialsPath) {
        $localCredentials = Get-Content -Raw -LiteralPath $credentialsPath | ConvertFrom-Json
        if ($localCredentials.token) {
            Write-Host 'Initialisation locale deja effectuee.'
            return
        }
        $headers = Get-BasicHeaders $localCredentials.username $localCredentials.password
    } else {
        $headers = Get-BasicHeaders 'admin' 'admin'
        try {
            $auth = Invoke-RestMethod "$serverUrl/api/authentication/validate" -Headers $headers
            if (-not $auth.valid) { throw 'Identifiants par defaut inactifs.' }
        } catch {
            throw 'Instance deja configuree : creer le projet et fournir son jeton via SONAR_TOKEN.'
        }
        $password = [guid]::NewGuid().ToString('N') + 'aA1!'
        Invoke-RestMethod "$serverUrl/api/users/change_password" -Method Post -Headers $headers -Body @{
            login = 'admin'; previousPassword = 'admin'; password = $password
        } | Out-Null
        $localCredentials = [pscustomobject]@{
            serverUrl = $serverUrl; username = 'admin'; password = $password
            projectKey = $projectKey; token = $null
        }
        # Sauvegarder immediatement pour pouvoir reprendre si une requete suivante echoue.
        Save-LocalCredentials $localCredentials
        $headers = Get-BasicHeaders 'admin' $password
    }
    try {
        Invoke-RestMethod "$serverUrl/api/components/show?component=$projectKey" -Headers $headers | Out-Null
    } catch {
        if ([int]$_.Exception.Response.StatusCode -ne 404) { throw }
        Invoke-RestMethod "$serverUrl/api/projects/create" -Method Post -Headers $headers -Body @{
            project = $projectKey; name = 'Trade Reporting C++ - Boost.Test'; visibility = 'private'
        } | Out-Null
    }
    $token = Invoke-RestMethod "$serverUrl/api/user_tokens/generate" -Method Post -Headers $headers -Body @{
        name = ('local-coverage-' + [guid]::NewGuid().ToString('N'))
        type = 'PROJECT_ANALYSIS_TOKEN'; projectKey = $projectKey
    }
    $localCredentials.token = $token.token
    Save-LocalCredentials $localCredentials
    Write-Host "Projet initialise. Identifiants locaux : $credentialsPath (fichier ignore par Git)."
}

function Invoke-Coverage {
    Invoke-Docker -DockerArguments @('compose', 'build', 'coverage')
    Invoke-Docker -DockerArguments @('compose', 'run', '--rm', 'coverage')
}

function Invoke-Analysis {
    $previousToken = $env:SONAR_TOKEN
    try {
        if (-not $env:SONAR_TOKEN -and (Test-Path -LiteralPath $credentialsPath)) {
            $env:SONAR_TOKEN = (Get-Content -Raw -LiteralPath $credentialsPath | ConvertFrom-Json).token
        }
        if (-not $env:SONAR_TOKEN) {
            throw 'Jeton absent : lancer init sur une instance neuve, ou definir SONAR_TOKEN.'
        }
        Wait-Sonar
        $languages = Invoke-RestMethod "$serverUrl/api/languages/list" -Headers @{
            Authorization = "Bearer $env:SONAR_TOKEN"
        }
        if (-not ($languages.languages | Where-Object { $_.key -eq 'cxx' })) {
            throw 'Langue cxx absente. Redemarrer : docker compose restart sonarqube'
        }
        # Un echec de compilation/tests interdit tout envoi d'une ancienne couverture.
        Invoke-Coverage
        Invoke-Docker -DockerArguments @('compose', 'run', '--rm', 'scanner')
        $metrics = 'coverage,line_coverage,branch_coverage,lines_to_cover,uncovered_lines,conditions_to_cover,uncovered_conditions,alert_status'
        $measures = Invoke-RestMethod "$serverUrl/api/measures/component?component=$projectKey&metricKeys=$metrics" -Headers @{
            Authorization = "Bearer $env:SONAR_TOKEN"
        }
        $measures | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $projectRoot 'reports/sonarqube-measures.json') -Encoding UTF8
        $measures.component.measures | Select-Object metric, value | Format-Table -AutoSize
        Write-Host "$serverUrl/dashboard?id=$projectKey"
    } finally {
        $env:SONAR_TOKEN = $previousToken
    }
}

Push-Location $projectRoot
try {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw 'Installer Docker Engine + Compose sous Linux/WSL, ou utiliser Docker Desktop deja installe.'
    }
    Invoke-Docker -DockerArguments @('info', '--format', '{{.ServerVersion}}')
    switch ($Action) {
        'coverage' { Invoke-Coverage }
        'start' { Start-Sonar }
        'init' { Initialize-Sonar }
        'analyze' { Invoke-Analysis }
        'all' { Start-Sonar; Initialize-Sonar; Invoke-Analysis }
        'status' { Invoke-Docker -DockerArguments @('compose', 'ps'); Invoke-RestMethod "$serverUrl/api/system/status" }
    }
} finally {
    Pop-Location
}

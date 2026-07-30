<#
.SYNOPSIS
    Publica o Client Global neste repositorio de distribuicao e gera o manifest.json.

.DESCRIPTION
    Le a pasta do client (-Source), copia para ca APENAS o que os players devem receber
    e gera o manifest.json que o ValdrakenLauncherGlobal consome.

    Tres coisas que este script resolve e que um "copiar tudo" nao resolveria:

    1. LIMITE DE 100 MB DO GITHUB. O push do GitHub recusa qualquer arquivo individual
       acima de 100 MB, e bin\Qt6WebEngineCore.dll tem 189 MB (e o Chromium do Qt
       WebEngine; nao da para remover, o Qt6WebEngineQuick.dll importa ele). Todo
       arquivo acima de -MaxRawMB e publicado em GZip (189 MB -> ~77 MB) e o launcher
       descomprime na maquina do player, conferindo o SHA256 antes e depois.

    2. DADOS PESSOAIS E DE RUNTIME. A pasta do client contem screenshots (95 MB),
       minimapa explorado, characterdata e o conf\clientoptions.json - que guarda o
       loginEmailAddress da conta. Nada disso pode ser distribuido, e por isso a
       exclusao e por lista explicita (allowlist do que sai, nao "o que eu lembrei").

    3. ARQUIVOS ORFAOS. Se um asset sai do client (ex.: appearances antigo, que tem o
       hash no nome), ele e removido daqui tambem, senao o repositorio so cresce.

.EXAMPLE
    # Fluxo normal de release:
    .\publish-global.ps1 -Version 15.24.36
    git add -A; git commit -m "client global 15.24.36"; git push

.EXAMPLE
    # Confere se o manifest esta coerente com o que esta no repo (nao escreve nada).
    .\publish-global.ps1 -Check
#>

[CmdletBinding()]
param(
    # Pasta do client de onde os arquivos sao copiados.
    [string]$Source = 'C:\Valdraken-Client-Global-Final',

    # Nova versao (ex.: 15.24.36). Se omitido, reaproveita a de version.txt.
    [string]$Version,

    # Acima disso o arquivo e publicado em GZip. 95 deixa margem para os 100 do GitHub.
    [int]$MaxRawMB = 95,

    # Apenas valida o repositorio contra o manifest.json atual. Nao escreve nada.
    [switch]$Check
)

$ErrorActionPreference = 'Stop'

$repo = $PSScriptRoot
if (-not $repo) { $repo = (Get-Location).Path }

$maxRawBytes = [int64]$MaxRawMB * 1MB

# ---------------------------------------------------------------------------
# O que NAO vai para os players.
# ---------------------------------------------------------------------------

# Pastas de primeiro nivel: estado do jogador, nao conteudo do client.
$excludeTopDirs = @(
    'screenshots',      # 95 MB de screenshots pessoais
    'minimap',          # minimapa explorado (cada player tem o seu)
    'characterdata',    # configs por personagem
    'cache',
    'crashdump',
    'log',
    'logs'
)

# Arquivos especificos, por caminho relativo.
$excludeRelFiles = @(
    'conf/clientoptions.json'   # contem loginEmailAddress da conta - NUNCA publicar
)

# Padroes de nome: backups de desenvolvimento e sobras de download.
$excludeNamePatterns = @('*bak*', '*.part', '*.unpack', '*.gz.part')

# Arquivos que pertencem ao repositorio (nao ao client) e sobrevivem a limpeza.
$repoOwnFiles = @(
    'manifest.json',
    'version.txt',
    'publish-global.ps1',
    'README.md',
    '.gitignore',
    '.gitattributes'
)

function Test-Excluded {
    param([string]$Rel, [string]$Name)

    $top = $Rel.Split('/')[0]
    if ($excludeTopDirs -contains $top.ToLowerInvariant()) { return $true }
    if ($excludeRelFiles -contains $Rel) { return $true }
    if ($Rel.Split('/') | Where-Object { $_.StartsWith('.') }) { return $true }
    foreach ($p in $excludeNamePatterns) { if ($Name -like $p) { return $true } }
    return $false
}

# ---------------------------------------------------------------------------
# Versao
# ---------------------------------------------------------------------------

$versionFile = Join-Path $repo 'version.txt'

if ($Version) {
    $ver = $Version.Trim()
} elseif (Test-Path $versionFile) {
    $ver = (Get-Content -Path $versionFile -Raw).Trim()
} else {
    throw "Sem versao: passe -Version (ex.: -Version 15.24.36) ou crie o version.txt."
}

# ---------------------------------------------------------------------------
# Modo -Check: valida o repositorio contra o proprio manifest.json
# ---------------------------------------------------------------------------

$manifestPath = Join-Path $repo 'manifest.json'

if ($Check) {
    if (-not (Test-Path $manifestPath)) { Write-Error "manifest.json nao existe."; exit 1 }

    $m = Get-Content -Path $manifestPath -Raw | ConvertFrom-Json
    $problems = New-Object System.Collections.Generic.List[string]

    foreach ($e in $m.files) {
        # O arquivo servido pelo raw GitHub e o .gz quando ha compressao.
        if ($e.compression) { $remote = $e.archivePath; $expect = $e.archiveSha256; $expectSize = $e.archiveSize }
        else                { $remote = $e.path;        $expect = $e.sha256;        $expectSize = $e.size }

        $local = Join-Path $repo ($remote -replace '/', '\')
        if (-not (Test-Path $local)) { $problems.Add("FALTA no repo: $remote"); continue }

        $fi = Get-Item $local
        if ($fi.Length -ne $expectSize) { $problems.Add("TAMANHO difere: $remote"); continue }

        $h = (Get-FileHash -Path $local -Algorithm SHA256).Hash.ToLower()
        if ($h -ne $expect.ToLower()) { $problems.Add("SHA256 difere: $remote") }

        if ($fi.Length -gt 100MB) { $problems.Add("ACIMA DE 100MB (o GitHub vai recusar): $remote") }
    }

    if ($m.version -ne $ver) { $problems.Add("version.txt ($ver) != manifest.version ($($m.version))") }

    if ($problems.Count -gt 0) {
        Write-Host "manifest.json INCONSISTENTE:" -ForegroundColor Red
        $problems | Select-Object -First 40 | ForEach-Object { Write-Host "  - $_" }
        if ($problems.Count -gt 40) { Write-Host "  ... e mais $($problems.Count - 40)" }
        exit 1
    }

    Write-Host "OK: $($m.files.Count) arquivos conferidos, versao $ver." -ForegroundColor Green
    exit 0
}

# ---------------------------------------------------------------------------
# Publicacao
# ---------------------------------------------------------------------------

if (-not (Test-Path $Source)) { throw "Pasta de origem nao encontrada: $Source" }

Write-Host "Origem : $Source"
Write-Host "Repo   : $repo"
Write-Host "Versao : $ver"
Write-Host ""

# Manifest anterior: usado para saber se o .gz de um arquivo grande ainda corresponde
# ao arquivo de origem atual (assim nao recomprimimos 189 MB a cada release).
$oldByPath = @{}
if (Test-Path $manifestPath) {
    try {
        $old = Get-Content -Path $manifestPath -Raw | ConvertFrom-Json
        foreach ($e in $old.files) { $oldByPath[$e.path] = $e }
    } catch {
        Write-Warning "manifest.json anterior ilegivel; tudo sera reprocessado."
    }
}

$srcRootLen = (Resolve-Path $Source).Path.TrimEnd('\').Length + 1

Write-Host "Lendo e hasheando a origem..."
$entries  = New-Object System.Collections.Generic.List[object]
$expected = New-Object System.Collections.Generic.HashSet[string]   # arquivos que devem existir no repo
$copied = 0; $gzipped = 0; $skipped = 0

foreach ($f in (Get-ChildItem -Path $Source -Recurse -File -Force)) {
    $rel = $f.FullName.Substring($srcRootLen).Replace('\', '/')
    if (Test-Excluded -Rel $rel -Name $f.Name) { $skipped++; continue }

    $srcHash = (Get-FileHash -Path $f.FullName -Algorithm SHA256).Hash.ToLower()
    $compress = $f.Length -gt $maxRawBytes

    if (-not $compress) {
        # --- Arquivo publicado cru ---
        $dest = Join-Path $repo ($rel -replace '/', '\')
        [void]$expected.Add($rel)

        $need = $true
        if (Test-Path $dest) {
            $d = Get-Item $dest
            if ($d.Length -eq $f.Length -and
                (Get-FileHash -Path $dest -Algorithm SHA256).Hash.ToLower() -eq $srcHash) {
                $need = $false
            }
        }
        if ($need) {
            New-Item -ItemType Directory -Force -Path (Split-Path $dest -Parent) | Out-Null
            Copy-Item -Path $f.FullName -Destination $dest -Force
            $copied++
        }

        $entries.Add([ordered]@{ path = $rel; sha256 = $srcHash; size = $f.Length })
    }
    else {
        # --- Arquivo publicado em GZip (acima do limite do GitHub) ---
        $relGz  = "$rel.gz"
        $destGz = Join-Path $repo ($relGz -replace '/', '\')
        [void]$expected.Add($relGz)

        # Recomprime so se o arquivo de origem mudou ou o .gz nao esta ok.
        $reuse = $false
        $prev = $oldByPath[$rel]
        if ($prev -and $prev.sha256 -eq $srcHash -and $prev.archiveSha256 -and (Test-Path $destGz)) {
            $gz = Get-Item $destGz
            if ($gz.Length -eq $prev.archiveSize -and
                (Get-FileHash -Path $destGz -Algorithm SHA256).Hash.ToLower() -eq $prev.archiveSha256.ToLower()) {
                $reuse = $true
            }
        }

        if (-not $reuse) {
            Write-Host ("  comprimindo {0} ({1:N1} MB)..." -f $rel, ($f.Length / 1MB))
            New-Item -ItemType Directory -Force -Path (Split-Path $destGz -Parent) | Out-Null

            $in = [System.IO.File]::OpenRead($f.FullName)
            try {
                $out = [System.IO.File]::Create($destGz)
                try {
                    $gzs = New-Object System.IO.Compression.GZipStream(
                        $out, [System.IO.Compression.CompressionLevel]::Optimal)
                    try { $in.CopyTo($gzs, 1MB) } finally { $gzs.Dispose() }
                } finally { $out.Dispose() }
            } finally { $in.Dispose() }

            $gzipped++
        }

        $gzInfo = Get-Item $destGz
        $gzHash = (Get-FileHash -Path $destGz -Algorithm SHA256).Hash.ToLower()

        if ($gzInfo.Length -gt 100MB) {
            throw ("'$relGz' ficou com {0:N1} MB mesmo comprimido - acima do limite de 100 MB do GitHub. " +
                   "Este arquivo precisa ser hospedado fora do repositorio (ex.: GitHub Releases)." -f ($gzInfo.Length / 1MB))
        }

        $entries.Add([ordered]@{
            path          = $rel
            sha256        = $srcHash
            size          = $f.Length
            compression   = 'gzip'
            archivePath   = $relGz
            archiveSha256 = $gzHash
            archiveSize   = $gzInfo.Length
        })
    }
}

# ---------------------------------------------------------------------------
# Limpeza: remove do repo o que nao faz mais parte do client
# ---------------------------------------------------------------------------

$repoRootLen = $repo.TrimEnd('\').Length + 1
$removed = 0

foreach ($f in (Get-ChildItem -Path $repo -Recurse -File -Force)) {
    $rel = $f.FullName.Substring($repoRootLen).Replace('\', '/')
    if ($rel -like '.git/*') { continue }
    if ($repoOwnFiles -contains $rel) { continue }
    if ($expected.Contains($rel)) { continue }

    Remove-Item -Path $f.FullName -Force
    $removed++
}

# Pastas que ficaram vazias depois da limpeza.
do {
    $empty = Get-ChildItem -Path $repo -Recurse -Directory -Force |
             Where-Object { $_.FullName -notlike "*\.git*" } |
             Where-Object { -not (Get-ChildItem -Path $_.FullName -Force) }
    $empty | ForEach-Object { Remove-Item -Path $_.FullName -Force }
} while ($empty)

# ---------------------------------------------------------------------------
# manifest.json + version.txt
# ---------------------------------------------------------------------------

$sorted = $entries | Sort-Object { $_.path } -Culture ([System.Globalization.CultureInfo]::InvariantCulture)

$manifest = [ordered]@{
    version   = $ver
    generated = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:sszzz')
    count     = $sorted.Count
    files     = @($sorted)
}

# PS 5.1 grava UTF-16 por padrao; o launcher espera UTF-8 sem BOM.
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 6), $utf8NoBom)
[System.IO.File]::WriteAllText($versionFile, $ver, $utf8NoBom)

# ---------------------------------------------------------------------------
# Resumo
# ---------------------------------------------------------------------------

$totalFinal    = ($sorted | ForEach-Object { $_.size } | Measure-Object -Sum).Sum
$totalTransfer = ($sorted | ForEach-Object { if ($_.archiveSize) { $_.archiveSize } else { $_.size } } |
                  Measure-Object -Sum).Sum

Write-Host ""
Write-Host "Publicado: $($sorted.Count) arquivos, versao $ver." -ForegroundColor Green
Write-Host ("  no disco do player : {0:N1} MB" -f ($totalFinal / 1MB))
Write-Host ("  download (com gzip): {0:N1} MB" -f ($totalTransfer / 1MB))
Write-Host "  copiados: $copied   comprimidos: $gzipped   removidos: $removed   ignorados na origem: $skipped"
Write-Host ""
Write-Host "Proximo passo:  git add -A; git commit -m ""client global $ver""; git push"

#requires -Version 5.1
<#
.SYNOPSIS
    Backup logico de la base foodstore con pg_dump (formato custom).

.DESCRIPTION
    Genera un respaldo en formato custom de la base de origen 'foodstore' (PostgreSQL 17)
    con nombre con fecha y hora. Guarda log local en logs/, verifica existencia y
    no vacio del archivo, y comprueba con pg_restore --list que pueda leerse.
    NO incluye contrasenas (usar .pgpass, PGPASSWORD en entorno seguro o trust/peer
    segun corresponda). NO sobrescribe respaldos existentes. Termina con codigo distinto
    de cero si falla pg_dump o la comprobacion del respaldo.

.NOTES
    Entorno: Windows / PostgreSQL 17. Origen: foodstore. Repositorio relativo.
#>

[CmdletBinding()]
param(
    [string]$PgHost = "localhost",
    [int]$PgPort = 5432,
    [string]$PgUser = "postgres",
    [string]$PgBin = ""  # Si vacio, intenta rutas comunes PostgreSQL 17 y luego PATH
)

$ErrorActionPreference = "Stop"

function Get-RepoRoot {
    $dir = $PSScriptRoot
    while ($dir -ne $null) {
        if (Test-Path (Join-Path $dir ".git")) {
            return $dir
        }
        $parent = Split-Path $dir -Parent
        if ($parent -eq $dir) { break }
        $dir = $parent
    }
    # Fallback: subir desde scripts/
    $fallback = Resolve-Path (Join-Path $PSScriptRoot "..")
    return $fallback.Path
}

function Find-PgTool {
    param([string]$ToolName, [string]$ExplicitBin)
    if ($ExplicitBin -ne "") {
        $cand = Join-Path $ExplicitBin $ToolName
        if ($ToolName -notlike "*.exe") { $cand = "$cand.exe" }
        if (Test-Path $cand) { return $cand }
    }
    # Rutas comunes PostgreSQL 17 Windows
    $common = @(
        "C:\Program Files\PostgreSQL\17\bin\$ToolName.exe",
        "C:\Program Files (x86)\PostgreSQL\17\bin\$ToolName.exe"
    )
    foreach ($c in $common) {
        if (Test-Path $c) { return $c }
    }
    # PATH
    $cmd = Get-Command $ToolName -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw "No se encontro $ToolName. Especificar -PgBin o agregarlo al PATH."
}

$RepoRoot = Get-RepoRoot
$BackupDir = Join-Path $RepoRoot "backups"
$LogDir = Join-Path $RepoRoot "logs"
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$PgDump = Find-PgTool -ToolName "pg_dump" -ExplicitBin $PgBin
$PgRestore = Find-PgTool -ToolName "pg_restore" -ExplicitBin $PgBin

$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$DbName = "foodstore"
$DumpFile = Join-Path $BackupDir "${DbName}_$Timestamp.dump"
$LogFile = Join-Path $LogDir "backup_${DbName}_$Timestamp.log"

# Evitar sobrescritura (por si hay colision improbable)
if (Test-Path $DumpFile) {
    Write-Error "El archivo de respaldo ya existe: $DumpFile. No se sobrescribira."
    exit 1
}

"[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] INICIO backup $DbName" | Tee-Object -FilePath $LogFile -Append | Out-Null
"Origen: host=$PgHost port=$PgPort db=$DbName user=$PgUser" | Tee-Object -FilePath $LogFile -Append | Out-Null
"Formato: custom (-Fc) | Destino: $DumpFile" | Tee-Object -FilePath $LogFile -Append | Out-Null
"NOTA: no se incluyen contrasenas en este script; usar .pgpass/PGPASSWORD/credenciales seguras." | Tee-Object -FilePath $LogFile -Append | Out-Null

# Ejecutar pg_dump formato custom (invocacion nativa con & y array de argumentos)
$dumpArgs = @(
    "-h", $PgHost,
    "-p", "$PgPort",
    "-U", $PgUser,
    "-Fc",
    "-f", $DumpFile,
    $DbName
)

$dumpStderr = Join-Path $LogDir "backup_${DbName}_$Timestamp.stderr.log"
"[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Ejecutando: $PgDump $($dumpArgs -join ' ')" | Tee-Object -FilePath $LogFile -Append | Out-Null
& $PgDump @dumpArgs 2> $dumpStderr
$dumpExit = $LASTEXITCODE
"[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] pg_dump exitcode=$dumpExit" | Tee-Object -FilePath $LogFile -Append | Out-Null
if ($dumpExit -ne 0) {
    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] FALLO: pg_dump termino con codigo distinto de cero. Ver stderr: $dumpStderr" | Tee-Object -FilePath $LogFile -Append | Out-Null
    exit $dumpExit
}

# Comprobacion: archivo no vacio
if (-not (Test-Path $DumpFile)) {
    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] FALLO: no existe el archivo de respaldo." | Tee-Object -FilePath $LogFile -Append | Out-Null
    exit 1
}
$len = (Get-Item $DumpFile).Length
"[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Tamano del dump: $len bytes" | Tee-Object -FilePath $LogFile -Append | Out-Null
if ($len -le 0) {
    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] FALLO: archivo de respaldo vacio." | Tee-Object -FilePath $LogFile -Append | Out-Null
    exit 1
}

# Comprobacion obligatoria: pg_restore --list debe poder leerlo
$listOut = Join-Path $LogDir "backup_${DbName}_$Timestamp.list.txt"
$listStderr = Join-Path $LogDir "backup_${DbName}_$Timestamp.list.stderr.log"
$listArgs = @("--list", $DumpFile)
"[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Ejecutando: $PgRestore $($listArgs -join ' ')" | Tee-Object -FilePath $LogFile -Append | Out-Null
& $PgRestore @listArgs > $listOut 2> $listStderr
$listExit = $LASTEXITCODE
"[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] pg_restore --list exitcode=$listExit" | Tee-Object -FilePath $LogFile -Append | Out-Null
if ($listExit -ne 0) {
    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] FALLO: pg_restore --list no pudo leer el respaldo. Ver stderr: $listStderr" | Tee-Object -FilePath $LogFile -Append | Out-Null
    exit $listExit
}
"[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] VERIFICACION OK: pg_restore --list pudo leer el archivo." | Tee-Object -FilePath $LogFile -Append | Out-Null

"[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] FIN OK: $DumpFile" | Tee-Object -FilePath $LogFile -Append | Out-Null
exit 0

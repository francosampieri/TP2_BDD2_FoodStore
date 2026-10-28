#requires -Version 5.1
<#
.SYNOPSIS
    Restauracion de prueba a foodstore_restore_test (solo validacion).

.DESCRIPTION
    Restaura UNICAMENTE desde la ruta .dump pasada como parametro obligatorio
    hacia una base NUEVA llamada foodstore_restore_test. Antes de crearla
    verifica que NO exista; si existe se detiene con error. No incluye
    DROP DATABASE, no sobrescribe ni toca foodstore.

    Usa createdb, pg_restore y psql (PostgreSQL 17 / Windows). Sin contrasenas
    en el archivo. Rutas con espacios manejadas con invocacion nativa (&) y
    arrays de argumentos. pg_restore usa --no-owner, --no-privileges y
    --exit-on-error. Si falla, conserva la base de prueba para inspeccion.

    Valida conteos contra los registrados antes del respaldo:
      categoria=8, usuario=9, producto=25, pedido=21, detalle_pedido=37
    (tabla real: usuario, NO cliente)
    y chequea integridad minima: precio>=0/stock>=0 en producto;
    cantidad>0 y precio_unitario>=0 en detalle_pedido.

    Mide RTO desde inmediatamente antes de crear la base hasta completar
    las validaciones. Registra fecha/hora del respaldo desde el nombre
    foodstore_yyyyMMdd_HHmmss.dump (inicio registrado) y su antiguedad
    al iniciar el simulacro como RPO observado (estimacion, no medida).
    Guarda log ASCII en logs/ (excluido de Git).
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DumpPath,
    [string]$PgHost = "localhost",
    [int]$PgPort = 5432,
    [string]$PgUser = "postgres",
    [string]$PgBin = ""
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
    $common = @(
        "C:\Program Files\PostgreSQL\17\bin\$ToolName.exe",
        "C:\Program Files (x86)\PostgreSQL\17\bin\$ToolName.exe"
    )
    foreach ($c in $common) {
        if (Test-Path $c) { return $c }
    }
    $cmd = Get-Command $ToolName -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw "No se encontro $ToolName. Especificar -PgBin o agregarlo al PATH."
}

function Parse-DumpTimestamp {
    param([string]$FileName)
    # Espera foodstore_yyyyMMdd_HHmmss.dump
    if ($FileName -match 'foodstore_(\d{8})_(\d{6})\.dump$') {
        $dateStr = $Matches[1]
        $timeStr = $Matches[2]
        $year = $dateStr.Substring(0,4)
        $month = $dateStr.Substring(4,2)
        $day = $dateStr.Substring(6,2)
        $hour = $timeStr.Substring(0,2)
        $min = $timeStr.Substring(2,2)
        $sec = $timeStr.Substring(4,2)
        return [DateTime]::ParseExact("$year-$month-$day $hour`:$min`:$sec", "yyyy-MM-dd HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)
    }
    return $null
}

function Get-IntFromPsql {
    param([string]$PsqlPath, [string[]]$BaseArgs, [string]$Query)
    $qArgs = $BaseArgs + @("-t", "-A", "-c", $Query)
    $tmpOut = [System.IO.Path]::GetTempFileName()
    $tmpErr = [System.IO.Path]::GetTempFileName()
    try {
        & $PsqlPath @qArgs 1> $tmpOut 2> $tmpErr
        $exit = $LASTEXITCODE
        if ($exit -ne 0) {
            throw "psql fallo con exitcode=$exit. Ver $tmpErr"
        }
        $content = (Get-Content -Path $tmpOut -Raw).Trim()
        if ($content -eq "") {
            throw "psql devolvio salida vacia para la consulta."
        }
        if ($content -notmatch '^-?\d+$') {
            throw "psql devolvio un valor no entero: '$content'"
        }
        return [int]$content
    }
    finally {
        Remove-Item -Path $tmpOut, $tmpErr -ErrorAction SilentlyContinue
    }
}

$RepoRoot = Get-RepoRoot
$LogDir = Join-Path $RepoRoot "logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$Createdb = Find-PgTool -ToolName "createdb" -ExplicitBin $PgBin
$PgRestore = Find-PgTool -ToolName "pg_restore" -ExplicitBin $PgBin
$Psql = Find-PgTool -ToolName "psql" -ExplicitBin $PgBin

$TargetDb = "foodstore_restore_test"
$SourceDbExpected = "foodstore"

# Ruta obligatoria de .dump (no elegir uno silenciosamente)
# Resolver desde raiz del repositorio si es relativa
if ([System.IO.Path]::IsPathRooted($DumpPath)) {
    $DumpCandidate = $DumpPath
} else {
    $DumpCandidate = Join-Path $RepoRoot $DumpPath
}
$DumpFull = Resolve-Path $DumpCandidate -ErrorAction Stop
if (-not (Test-Path $DumpFull)) {
    Write-Error "No existe el archivo .dump indicado: $DumpPath"
    exit 1
}
if ($DumpFull.Path -notlike "*.dump") {
    Write-Error "El parametro debe apuntar a un archivo .dump"
    exit 1
}

$DumpItem = Get-Item $DumpFull.Path
# Antiguedad desde nombre del archivo (inicio registrado del respaldo), no LastWriteTime
$DumpStartTime = Parse-DumpTimestamp -FileName $DumpItem.Name
$NowStart = Get-Date
if ($DumpStartTime -ne $null) {
    $RpoAge = $NowStart - $DumpStartTime
    $DumpTimeSource = "nombre $($DumpItem.Name)"
} else {
    $RpoAge = $NowStart - $DumpItem.LastWriteTime
    $DumpTimeSource = "LastWriteTime (fallback)"
}

$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile = Join-Path $LogDir "restore_test_${TargetDb}_$Timestamp.log"

function Log {
    param([string]$Msg)
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Msg"
    $line | Out-File -FilePath $LogFile -Append -Encoding ASCII
    Write-Host $line
}

Log "INICIO RESTAURACION DE PRUEBA"
Log "Dump obligatorio: $($DumpFull.Path)"
if ($DumpStartTime -ne $null) {
    Log "Fecha/hora del respaldo (desde nombre): $($DumpStartTime.ToString('yyyy-MM-dd HH:mm:ss'))"
} else {
    Log "Fecha/hora del respaldo: NO se pudo parsear desde nombre; usando $DumpTimeSource $($DumpItem.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))"
}
Log "RPO observado (estimacion de antiguedad al iniciar): $($RpoAge.ToString()) - fuente: $DumpTimeSource (NO es perdida medida)"
Log "Destino EXCLUSIVO: $TargetDb (NO se toca $SourceDbExpected)"
Log "Herramientas: createdb=$Createdb | pg_restore=$PgRestore | psql=$Psql"

# Verificar que la base destino NO exista con UNA SOLA invocacion de psql
$checkDbOutFile = Join-Path $LogDir "restore_test_${TargetDb}_$Timestamp.checkdb.out.txt"
$checkDbErrFile = Join-Path $LogDir "restore_test_${TargetDb}_$Timestamp.checkdb.stderr.log"
$checkDbArgs = @("-h", $PgHost, "-p", "$PgPort", "-U", $PgUser, "-d", "postgres", "-t", "-A", "-c", "SELECT 1 FROM pg_database WHERE datname='$TargetDb';")
Log "Comprobando existencia de $TargetDb en postgres (una sola invocacion)..."
& $Psql @checkDbArgs 1> $checkDbOutFile 2> $checkDbErrFile
$checkDbExit = $LASTEXITCODE
if ($checkDbExit -ne 0) {
    Log "FALLO al consultar pg_database (exitcode=$checkDbExit). Ver logs/*.checkdb.*"
    exit $checkDbExit
}
$checkDbContent = Get-Content -LiteralPath $checkDbOutFile -Raw
if ($null -eq $checkDbContent) {
    $checkDbContent = ""
} else {
    $checkDbContent = $checkDbContent.Trim()
}
if ($checkDbContent -eq "1") {
    Log "ERROR: $TargetDb YA EXISTE. Deteniendose SIN borrar ni sobrescribir. Conservar para inspeccion."
    exit 1
}
if ($checkDbContent -ne "") {
    Log "ERROR: salida inesperada al comprobar existencia de ${TargetDb}: '$checkDbContent'. Deteniendose sin crear la base."
    exit 1
}
Log "OK: $TargetDb no existe (salida vacia). Se creara una base NUEVA."

# Medir RTO desde inmediatamente antes de crear la base
$RtoStart = Get-Date

# Crear base nueva
$createArgs = @("-h", $PgHost, "-p", "$PgPort", "-U", $PgUser, $TargetDb)
Log "Creando base nueva: createdb $TargetDb"
& $Createdb @createArgs 2> (Join-Path $LogDir "restore_test_${TargetDb}_$Timestamp.createdb.stderr.log")
$createExit = $LASTEXITCODE
if ($createExit -ne 0) {
    Log "FALLO al crear $TargetDb (exitcode=$createExit). Ver createdb.stderr.log. NO se borra automaticamente."
    exit $createExit
}
Log "Base creada OK."

# Restaurar con pg_restore: --no-owner --no-privileges --exit-on-error
$restoreArgs = @(
    "-h", $PgHost,
    "-p", "$PgPort",
    "-U", $PgUser,
    "-d", $TargetDb,
    "--no-owner",
    "--no-privileges",
    "--exit-on-error",
    $DumpFull.Path
)
Log "Restaurando con pg_restore (--no-owner --no-privileges --exit-on-error)"
& $PgRestore @restoreArgs 2> (Join-Path $LogDir "restore_test_${TargetDb}_$Timestamp.pg_restore.stderr.log")
$restoreExit = $LASTEXITCODE
if ($restoreExit -ne 0) {
    Log "FALLO en pg_restore (exitcode=$restoreExit). La base $TargetDb se CONSERVA para inspeccion (no se elimina). Ver pg_restore.stderr.log"
    exit $restoreExit
}
Log "Restauracion completada por pg_restore."

# Validaciones contra conteos registrados antes del respaldo
$PsqlBase = @("-h", $PgHost, "-p", "$PgPort", "-U", $PgUser, "-d", $TargetDb)
$Expected = @{
    "categoria"       = 8
    "usuario"         = 9
    "producto"        = 25
    "pedido"          = 21
    "detalle_pedido"  = 37
}

$AllOk = $true
foreach ($t in @("categoria","usuario","producto","pedido","detalle_pedido")) {
    try {
        $c = Get-IntFromPsql -PsqlPath $Psql -BaseArgs $PsqlBase -Query "SELECT count(*) FROM $t;"
        $exp = $Expected[$t]
        if ($c -ne $exp) {
            Log "VALIDACION FALLO: $t = $c (esperado $exp)"
            $AllOk = $false
        } else {
            Log "VALIDACION OK: $t = $c"
        }
    }
    catch {
        Log "VALIDACION FALLO: no se pudo obtener conteo de $t. $_"
        $AllOk = $false
    }
}

# Chequeos de integridad
try {
    $badProd = Get-IntFromPsql -PsqlPath $Psql -BaseArgs $PsqlBase -Query "SELECT count(*) FROM producto WHERE precio < 0 OR stock < 0;"
    if ($badProd -ne 0) {
        Log "VALIDACION FALLO: productos con precio < 0 o stock < 0 = $badProd (esperado 0)"
        $AllOk = $false
    } else {
        Log "VALIDACION OK: productos con precio < 0 o stock < 0 = 0"
    }
}
catch {
    Log "VALIDACION FALLO: no se pudo ejecutar chequeo de producto. $_"
    $AllOk = $false
}

try {
    $badDet = Get-IntFromPsql -PsqlPath $Psql -BaseArgs $PsqlBase -Query "SELECT count(*) FROM detalle_pedido WHERE cantidad <= 0 OR precio_unitario < 0;"
    if ($badDet -ne 0) {
        Log "VALIDACION FALLO: detalle_pedido con cantidad <= 0 o precio_unitario < 0 = $badDet (esperado 0)"
        $AllOk = $false
    } else {
        Log "VALIDACION OK: detalle_pedido con cantidad <= 0 o precio_unitario < 0 = 0"
    }
}
catch {
    Log "VALIDACION FALLO: no se pudo ejecutar chequeo de detalle_pedido. $_"
    $AllOk = $false
}

$RtoEnd = Get-Date
$Rto = $RtoEnd - $RtoStart
Log "RTO (desde antes de crear base hasta fin de validaciones): $($Rto.ToString())"
Log "RPO observado (estimacion de antiguedad al iniciar): $($RpoAge.ToString()) - fuente: $DumpTimeSource"

if (-not $AllOk) {
    Log "VALIDACION GENERAL: FALLIDA. Base $TargetDb CONSERVADA para inspeccion (sin borrado automatico)."
    exit 1
}

Log "VALIDACION GENERAL: TODAS LAS COMPROBACIONES CORRECTAS"
Log "FIN OK"
exit 0

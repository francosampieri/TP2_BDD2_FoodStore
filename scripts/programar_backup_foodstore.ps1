#requires -Version 5.1
<#
.SYNOPSIS
    Programa (o consulta) la tarea diaria de respaldo de FoodStore.

.DESCRIPTION
    Registra una tarea programada diaria de Windows que ejecuta el script
    existente scripts\backup_foodstore.ps1 con Windows PowerShell 5.1
    (powershell.exe -NoProfile -NonInteractive).

    El registro solo se realiza con el parámetro explícito -Install.
    Sin -Install ni -Status, el script muestra la ayuda.

    Antes de registrar comprueba:
      * que existe %APPDATA%\postgresql\pgpass.conf (solo Test-Path; NO lee
        ni muestra su contenido);
      * que no exista ya una tarea con el mismo nombre (no la reemplaza).

    La tarea se registra con la cuenta actual y LogonType Interactive:
    solo se ejecutará cuando esa cuenta esté conectada a Windows. No se
    usan contraseñas, PGPASSWORD ni credenciales embebidas.

.PARAMETER Install
    Registra la tarea diaria. Requiere que las precondiciones se cumplan.

.PARAMETER Status
    Muestra el estado de la tarea y el resultado de la última ejecución.

.PARAMETER Time
    Hora diaria en formato HH:mm (24 h). Por defecto 19:00.

.PARAMETER TaskName
    Nombre de la tarea programada. Por defecto FoodStore-Backup-Diario.

.EXAMPLE
    .\programar_backup_foodstore.ps1 -Install

.EXAMPLE
    .\programar_backup_foodstore.ps1 -Install -Time "21:30"

.EXAMPLE
    .\programar_backup_foodstore.ps1 -Status

.NOTES
    Windows / Windows PowerShell 5.1. No incluye contraseñas ni PGPASSWORD.
    Si Register-ScheduledTask devuelve acceso denegado, ejecutar la consola
    como administrador; la tarea seguirá usando la cuenta actual con
    LogonType Interactive.
#>

[CmdletBinding()]
param(
    [switch]$Install,
    [switch]$Status,

    [ValidatePattern('^(?:[01]\d|2[0-3]):[0-5]\d$')]
    [string]$Time = "19:00",

    [string]$TaskName = "FoodStore-Backup-Diario"
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Rutas absolutas resueltas desde la ubicación de este script
# ---------------------------------------------------------------------------
$ScriptDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ScriptDir)) {
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}

$BackupScript = Join-Path $ScriptDir "backup_foodstore.ps1"

# Windows PowerShell 5.1 (powershell.exe, no pwsh.exe)
$systemRoot = if ($env:SystemRoot) { $env:SystemRoot } else { $env:WINDIR }
$PowerShell51 = Join-Path $systemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"

# pgpass.conf: solo se comprueba existencia, nunca se lee su contenido
$PgPassPath = Join-Path $env:APPDATA "postgresql\pgpass.conf"

function Show-Usage {
    Write-Host @"
Uso:
  # Registrar la tarea diaria (requiere -Install)
  .\programar_backup_foodstore.ps1 -Install [-Time "19:00"] [-TaskName "FoodStore-Backup-Diario"]

  # Consultar estado y último resultado
  .\programar_backup_foodstore.ps1 -Status

Notas:
  - La tarea ejecuta scripts\backup_foodstore.ps1 con Windows PowerShell 5.1
    (powershell.exe -NoProfile -NonInteractive).
  - Requiere que exista %APPDATA%\postgresql\pgpass.conf (no se lee su contenido).
  - No reemplaza una tarea existente con el mismo nombre.
  - Usa la cuenta actual con inicio de sesión interactivo: la tarea solo
    corre cuando esa cuenta está conectada a Windows.
  - No se incluyen contraseñas ni PGPASSWORD.
"@
}

function Show-TaskStatus {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $task) {
        Write-Host "No existe la tarea '$TaskName'."
        Write-Host "Para registrarla: .\programar_backup_foodstore.ps1 -Install"
        return
    }

    $info = Get-ScheduledTaskInfo -TaskName $TaskName
    $code = $info.LastTaskResult
    $codeHex = '0x{0:X8}' -f $code
    $codeText = switch ([int64]$code) {
        0      { 'éxito' }
        267009 { 'en ejecución' }
        267011 { 'nunca ejecutada' }
        default { 'ver código' }
    }

    $action = @($task.Actions)[0]
    $trigger = @($task.Triggers)[0]

    Write-Host "Tarea            : $($task.TaskName)"
    Write-Host "Estado           : $($task.State)"
    Write-Host "Cuenta           : $($task.Principal.UserId) (LogonType: $($task.Principal.LogonType))"
    Write-Host "Última ejecución : $($info.LastRunTime)"
    Write-Host "Último resultado : $codeHex ($code) - $codeText"
    Write-Host "Próxima ejecución: $($info.NextRunTime)"
    Write-Host "Perdidas         : $($info.NumberOfMissedRuns)"
    Write-Host "Acción           : $($action.Execute) $($action.Arguments)"
    Write-Host "Disparador       : $($trigger.StartBoundary) (diario)"
    Write-Host "pgpass.conf      : $(if (Test-Path -LiteralPath $PgPassPath -PathType Leaf) { 'existe (contenido no leído)' } else { 'NO existe' })"
    Write-Host "backup_foodstore : $(if (Test-Path -LiteralPath $BackupScript -PathType Leaf) { 'existe' } else { 'NO existe' })"
}

function Test-InstallPreconditions {
    if ([string]::IsNullOrWhiteSpace($env:APPDATA)) {
        throw "No se pudo resolver %APPDATA%; ejecutar desde una sesión de usuario normal."
    }

    if (-not (Test-Path -LiteralPath $BackupScript -PathType Leaf)) {
        throw "No se encontró el script de respaldo: $BackupScript"
    }

    if (-not (Test-Path -LiteralPath $PowerShell51 -PathType Leaf)) {
        throw "No se encontró Windows PowerShell 5.1 en: $PowerShell51"
    }

    if (-not (Test-Path -LiteralPath $PgPassPath -PathType Leaf)) {
        throw "No existe $PgPassPath. Creá el archivo pgpass.conf antes de programar la tarea. No se lee su contenido."
    }

    $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existing) {
        throw "Ya existe una tarea programada llamada '$TaskName'. No se reemplaza automáticamente. Para eliminarla manualmente: Unregister-ScheduledTask -TaskName '$TaskName' -Confirm"
    }
}

# ---------------------------------------------------------------------------
# Flujo principal
# ---------------------------------------------------------------------------
if ($Install) {
    Test-InstallPreconditions

    # StartBoundary en el futuro: si la hora ya pasó hoy, programar para mañana
    $at = [datetime]::ParseExact($Time, 'HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
    if ($at -lt (Get-Date)) {
        $at = $at.AddDays(1)
    }

    # -ExecutionPolicy Bypass evita que una política restrictiva bloquee el
    # script de respaldo. No se pasan credenciales ni PGPASSWORD.
    $arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}"' -f $BackupScript
    $action = New-ScheduledTaskAction -Execute $PowerShell51 -Argument $arguments -WorkingDirectory $ScriptDir
    $trigger = New-ScheduledTaskTrigger -Daily -At $at

    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Limited

    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -ExecutionTimeLimit (New-TimeSpan -Hours 2) `
        -MultipleInstances IgnoreNew

    $description = "Respaldo diario de FoodStore. Ejecuta scripts\backup_foodstore.ps1 con Windows PowerShell 5.1 (-NoProfile -NonInteractive). Usa la cuenta actual con inicio de sesión interactivo: solo corre cuando esa cuenta está conectada. No contiene contraseñas; usa %APPDATA%\postgresql\pgpass.conf."

    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $action `
        -Trigger $trigger `
        -Principal $principal `
        -Settings $settings `
        -Description $description | Out-Null

    Write-Host "Tarea registrada: $TaskName"
    Write-Host "Hora diaria     : $Time"
    Write-Host "Cuenta          : $currentUser (LogonType: Interactive)"
    Write-Host "Script          : $BackupScript"
    Write-Host "PowerShell      : $PowerShell51"
    Write-Host "pgpass.conf     : existe (contenido no leído)"
    Write-Host ""
    Write-Host "IMPORTANTE: la tarea usa inicio de sesión interactivo; solo se ejecutará cuando la cuenta '$currentUser' esté conectada a Windows."
    Write-Host ""
    Show-TaskStatus
}
elseif ($Status) {
    Show-TaskStatus
}
else {
    Show-Usage
}

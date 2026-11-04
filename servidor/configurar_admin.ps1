# ===========================================================================
#  La CLAVE DEL PANEL DE ADMINISTRACION (la app "Breach Admin").
#
#  La clave se ESCRIBE AQUI, en tu terminal, y NO se guarda en ningun sitio:
#  al servidor solo va su huella (scrypt con sal), en la variable BREACH_ADMIN_HASH.
#  Ni el codigo, ni el APK, ni la consola de Google la llevan.
#  Se puede volver a ejecutar para cambiarla: las sesiones abiertas del panel caducan.
# ===========================================================================
$ErrorActionPreference = "Stop"
$Proyecto = "gen-lang-client-0444936010"
$Region = "us-central1"
$Servicio = "breach-cuentas"

function Leer-Secreto([string]$pregunta) {
    $seguro = Read-Host -Prompt $pregunta -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($seguro)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

Write-Host ""
Write-Host "=== Clave del panel de administracion de Breach ===" -ForegroundColor Yellow
Write-Host "Minimo 12 caracteres. Mejor una frase larga que nadie adivine."
Write-Host "Lo que escribas no se ve en pantalla."
Write-Host ""
$clave = Leer-Secreto "Clave nueva del panel"
if ($clave.Length -lt 12) { Write-Host "Demasiado corta: al menos 12 caracteres." -ForegroundColor Red; exit 1 }
if ($clave.Length -gt 128) { Write-Host "Demasiado larga: como mucho 128." -ForegroundColor Red; exit 1 }
$otra = Leer-Secreto "Repitela"
if ($clave -cne $otra) { Write-Host "No coinciden." -ForegroundColor Red; exit 1 }

# PowerShell 5.1 manda a los programas en ASCII: una "ñ" o una tilde llegarian como "?" y la clave del movil (UTF-8)
# no coincidiria nunca. En UTF-8, sin BOM.
$OutputEncoding = New-Object System.Text.UTF8Encoding $false
# la huella, con los MISMOS parametros que el servidor (index.js: SCRYPT). La clave va por la entrada
# estandar, no en la linea de comandos (ahi la veria cualquiera que liste los procesos).
$huella = ($clave | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{const c=require('crypto');const k=d.replace(/\r?\n$/,'');const s=c.randomBytes(16).toString('hex');process.stdout.write('scrypt:'+s+':'+c.scryptSync(k,s,32,{N:16384,r:8,p:1}).toString('hex'))})").Trim()
$clave = $null; $otra = $null
if (-not $huella.StartsWith("scrypt:")) { Write-Host "No se pudo calcular la huella (¿esta instalado Node?)." -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "Cargando en $Servicio ..." -ForegroundColor Yellow
gcloud config set project $Proyecto | Out-Null
gcloud run services update $Servicio --region $Region --update-env-vars "BREACH_ADMIN_HASH=$huella" | Out-Null
$huella = $null
$url = (gcloud run services describe $Servicio --region $Region --format "value(status.url)").Trim()
Write-Host ""
Write-Host "Hecho. Abre Breach Admin en el movil y entra con esa clave." -ForegroundColor Green
Write-Host "Servidor: $url"
try {
    $r = Invoke-WebRequest "$url/admin/resumen" -UseBasicParsing -ErrorAction Stop
} catch {
    $cod = $_.Exception.Response.StatusCode.value__
    if ($cod -eq 401) { Write-Host "Comprobacion: el panel responde (pide sesion). Todo bien." -ForegroundColor Green }
    elseif ($cod -eq 503) { Write-Host "Comprobacion: el servidor dice que el panel no esta configurado. Espera un minuto y vuelve a probar." -ForegroundColor Red }
    elseif ($cod -eq 404) { Write-Host "Comprobacion: el servidor aun no tiene el panel: hay que desplegar la version nueva." -ForegroundColor Red }
    else { Write-Host "Comprobacion: respuesta $cod" }
}

$ErrorActionPreference = 'Stop'
$Root = Join-Path $env:RUNNER_TEMP 'Xinyi Native Windows Probe With Spaces'
if (Test-Path $Root) { Remove-Item $Root -Recurse -Force }
New-Item -ItemType Directory -Path $Root -Force | Out-Null
$Checks = [ordered]@{}
$Checks.windows_kernel = ($env:OS -eq 'Windows_NT')
$Checks.powershell = ($PSVersionTable.PSVersion.Major -ge 5)
$Python = (Get-Command python.exe -ErrorAction Stop).Source
$Version = & $Python -c "import sys; print('.'.join(map(str,sys.version_info[:3])))"
$Checks.python = ($LASTEXITCODE -eq 0)
$App = Join-Path $Root 'probe_server.py'
@'
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
import json, sys
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        body=json.dumps({'ok': True, 'platform': sys.platform}).encode()
        self.send_response(200); self.send_header('Content-Type','application/json'); self.send_header('Content-Length',str(len(body))); self.end_headers(); self.wfile.write(body)
    def log_message(self,*args): pass
ThreadingHTTPServer(('127.0.0.1', 18765), H).serve_forever()
'@ | Set-Content -Path $App -Encoding UTF8
$Cmd = Join-Path $Root 'START PROBE.cmd'
@"
@echo off
setlocal
cd /d "%~dp0"
start "" /b "$Python" "%~dp0probe_server.py"
"@ | Set-Content -Path $Cmd -Encoding ASCII
$Process = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/d','/c',('"' + $Cmd + '"')) -WorkingDirectory $Root -PassThru
$Checks.quoted_cmd_path = $true
$Ready = $false
for ($i=0; $i -lt 40; $i++) {
  try {
    $Response = Invoke-RestMethod -Uri 'http://127.0.0.1:18765/' -TimeoutSec 2
    if ($Response.ok -eq $true -and $Response.platform -eq 'win32') { $Ready = $true; break }
  } catch { Start-Sleep -Milliseconds 250 }
}
$Checks.localhost_http = $Ready
$ServerProcesses = Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like '*probe_server.py*' }
foreach ($Item in $ServerProcesses) { Stop-Process -Id $Item.ProcessId -Force -ErrorAction SilentlyContinue }
$Checks.clean_shutdown = -not (Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like '*probe_server.py*' })
$AllPassed = -not ($Checks.Values -contains $false)
$Receipt = [ordered]@{
  schema = 'xinyi.windows-hosted-probe.v1'
  generated_utc = (Get-Date).ToUniversalTime().ToString('o')
  environment = 'GitHub-hosted Windows runner'
  os = [System.Environment]::OSVersion.VersionString
  powershell = $PSVersionTable.PSVersion.ToString()
  python = $Version
  checks = $Checks
  all_passed = $AllPassed
  truth_boundary = 'This receipt proves Windows kernel launcher primitives and localhost lifecycle only. It does not prove the exact full Xinyi release archive executed on Windows.'
}
$ReceiptPath = Join-Path $PWD 'WINDOWS_HOSTED_PROBE_RECEIPT.json'
$Receipt | ConvertTo-Json -Depth 8 | Set-Content -Path $ReceiptPath -Encoding UTF8
(Get-FileHash -Path $ReceiptPath -Algorithm SHA256).Hash.ToLowerInvariant() | Set-Content -Path ($ReceiptPath + '.sha256') -Encoding ASCII
if (-not $AllPassed) { throw 'One or more native Windows probe checks failed.' }
Write-Host ($Receipt | ConvertTo-Json -Depth 8)

# =====================================================================================
#  PC-Addicts PowerShell Library  —  Get-DiskSpace
#  ------------------------------------------------------------------------------------
#  FINE PRINT / USE AT YOUR OWN RISK
#  Provided as-is, as a teaching example, with NO WARRANTY of any kind, express or
#  implied. Read it, understand exactly what it does, and TEST IT IN A LAB before you
#  run it anywhere that matters. This script DELETES old report files in -ReportPath
#  (scoped to DiskSpaceRpt_*.html) and SENDS EMAIL — point those parameters somewhere
#  safe first. You are solely responsible for what it does on your systems. Not
#  affiliated with or representative of any employer.
#  ------------------------------------------------------------------------------------
#  Original by Chris Davis. Sanitized from a hardcoded farm/mail-server version into a
#  parameterized script with lab-safe defaults. Modernized Get-WmiObject -> Get-CimInstance.
# =====================================================================================
<#
.SYNOPSIS
    Build an HTML disk-space report for a list of servers and email it when something is low.
.DESCRIPTION
    For each computer in a list, collects free disk space (plus RAM %, CPU %, and OS build
    date), colors each row green/orange/red against your thresholds, writes an HTML report,
    and emails it if any drive is at/below the critical threshold. Great as a scheduled task.

    The Remote Desktop "drain mode" column is optional and shows N/A on boxes that aren't
    RD Session Hosts. Read-only against the targets; the only things it writes/deletes are
    its own report files in -ReportPath.
.PARAMETER ComputerListPath
    Path to a text file with one server name per line.
.PARAMETER ReportPath
    Folder to write the HTML report into (and prune DiskSpaceRpt_*.html older than 7 days).
.PARAMETER MailTo
    Recipient(s) for the alert email.
.PARAMETER MailFrom
    From address for the alert email.
.PARAMETER SmtpServer
    SMTP server to send through.
.PARAMETER WarningPercent
    Free-space % at or below which a row turns orange. Default 10.
.PARAMETER CriticalPercent
    Free-space % at or below which a row turns red and triggers the email. Default 5.
.EXAMPLE
    .\Get-DiskSpace.ps1 -ComputerListPath .\servers.txt -MailTo alerts@corp.example.lab
.NOTES
    Lab-first. Send-MailMessage is legacy but still works; swap in your team's mail method.
#>
[CmdletBinding()]
param(
    [string]$ComputerListPath = 'C:\Scripts\servers.txt',
    [string]$ReportPath       = 'C:\Scripts\Reports\DiskSpace\',
    [string[]]$MailTo         = 'alerts@corp.example.lab',
    [string]$MailFrom         = 'diskreport@corp.example.lab',
    [string]$SmtpServer       = 'smtp.corp.example.lab',
    [int]$WarningPercent      = 10,
    [int]$CriticalPercent     = 5
)

$ErrorActionPreference = 'Continue'

if (-not (Test-Path $ComputerListPath)) {
    throw "Computer list not found: $ComputerListPath"
}

# Colors for the table cells
$redColor    = '#FF0000'
$orangeColor = '#FBB917'
$whiteColor  = '#FFFFFF'
$pinkColor   = '#FFD8EF'

$lowDiskCount = 0
$computers = Get-Content $ComputerListPath

if (-not (Test-Path $ReportPath)) { New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null }
$titleDate  = Get-Date -UFormat '%A, %m-%d-%Y'
$diskReport = Join-Path $ReportPath ("DiskSpaceRpt_{0}.html" -f (Get-Date -Format 'yyyyMMdd'))

# Fresh report each run, and prune only OUR old reports (never unrelated files)
if (Test-Path $diskReport) { Remove-Item $diskReport }
Get-ChildItem $ReportPath -Filter 'DiskSpaceRpt_*.html' |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } | Remove-Item

# Report + table header
$header = @"
<html><head><meta http-equiv='Content-Type' content='text/html; charset=iso-8859-1'>
<title>Disk Space Report</title>
<style type='text/css'>
  td { font-family: Calibri; font-size: 12px; border: 1px solid #999999; padding: 2px; }
  body { margin: 5px; }
  table { border: thin solid #000000; }
</style></head><body>
<table width='100%'><tr bgcolor='#548DD4'><td colspan='7' height='30' align='center'>
<font face='calibri' color='#003399' size='4'><strong>Daily Disk Space Report for $titleDate</strong></font>
</td></tr></table>
<table width='100%'><tbody>
<tr bgcolor='#548DD4'>
  <td align='center'>Server</td><td align='center'>Drive</td><td align='center'>Label</td>
  <td align='center'>Total (GB)</td><td align='center'>Used (GB)</td><td align='center'>Free (GB)</td>
  <td align='center'>Free %</td><td align='center'>Drain Status</td>
  <td align='center'>RAM %</td><td align='center'>CPU %</td><td align='center'>Build Date</td>
</tr>
"@
Add-Content $diskReport $header

foreach ($computer in $computers) {
    $computer = $computer.Trim()
    if (-not $computer) { continue }

    try {
        $disks = Get-CimInstance -ComputerName $computer -ClassName Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction Stop
    } catch {
        Write-Warning "$computer : could not connect"
        continue
    }

    # RDS drain mode is only present on Session Hosts — treat as N/A otherwise
    try {
        $drain = Get-CimInstance -Namespace 'root\cimv2\TerminalServices' -ClassName Win32_TerminalServiceSetting -ComputerName $computer -ErrorAction Stop
        $drainStatus = switch ($drain.SessionBrokerDrainMode) { 0 {'Enabled'} 1 {'Disabled'} 2 {'Drain'} default {'Undetermined'} }
    } catch { $drainStatus = 'N/A' }

    $os  = Get-CimInstance -ComputerName $computer -ClassName Win32_OperatingSystem
    $ramPercent = [Math]::Round(($os.FreePhysicalMemory / $os.TotalVisibleMemorySize) * 100)
    $cpuPercent = Get-CimInstance -ComputerName $computer -ClassName Win32_Processor |
        Measure-Object -Property LoadPercentage -Average | Select-Object -ExpandProperty Average
    $buildDate  = $os.InstallDate

    $computerUpper = $computer.ToUpper()
    foreach ($disk in $disks) {
        [float]$size = $disk.Size
        [float]$free = $disk.FreeSpace
        if ($size -eq 0) { continue }
        $percentFree = [Math]::Round(($free / $size) * 100)
        $sizeGB = [Math]::Round($size / 1GB, 2)
        $freeGB = [Math]::Round($free / 1GB, 2)
        $usedGB = [Math]::Round($sizeGB - $freeGB, 2)

        $color = $whiteColor
        if ($percentFree -le $WarningPercent)  { $color = $orangeColor }
        if ($percentFree -le $CriticalPercent) { $color = $redColor; $lowDiskCount++ }

        $drainColor = switch ($drainStatus) { 'Drain' {$pinkColor} 'Disabled' {$redColor} default {$whiteColor} }

        $row = @"
<tr>
  <td>$computerUpper</td><td align='center'>$($disk.DeviceID)</td><td>$($disk.VolumeName)</td>
  <td align='center'>$sizeGB</td><td align='center'>$usedGB</td><td align='center'>$freeGB</td>
  <td bgcolor='$color' align='center'>$percentFree</td>
  <td bgcolor='$drainColor' align='center'>$drainStatus</td>
  <td align='center'>$ramPercent</td><td align='center'>$cpuPercent</td><td align='center'>$buildDate</td>
</tr>
"@
        Add-Content $diskReport $row
        Write-Host -ForegroundColor DarkYellow "$computerUpper $($disk.DeviceID) free = $percentFree%"
    }
}

# Legend + close
$legend = @"
</tbody></table><br>
<table width='30%'><tr bgcolor='White'>
  <td align='center' bgcolor='$orangeColor'>Warning (&le; $WarningPercent% free)</td>
  <td align='center' bgcolor='$redColor'>Critical (&le; $CriticalPercent% free)</td>
</tr></table></body></html>
"@
Add-Content $diskReport $legend

# Only email if at least one drive hit critical
if ($lowDiskCount -gt 0) {
    $body = Get-Content $diskReport -Raw
    Send-MailMessage -To $MailTo -From $MailFrom -SmtpServer $SmtpServer `
        -Subject "Disk Space Report — low space detected as of $titleDate" `
        -Body $body -BodyAsHtml -Priority High
    Write-Host "Alert email sent to $($MailTo -join ', ')"
}

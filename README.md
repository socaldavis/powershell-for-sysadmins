# PC-Addicts PowerShell Library — "steal these"

Real sysadmin PowerShell from 13 years on the job, rewritten from the ground up to be generic,
parameterized, and safe to run in *your* environment. These are the cleaned-up versions of the
scripts shown on the [PC-Addicts YouTube channel](https://www.youtube.com/@PC-Addicts) — the
originals were written to get the job done; these are what they should have looked like.

**Written walkthroughs for every script:**
[pc-addicts.com — the PowerShell Script Library](https://pc-addicts.com/tutorials/sysadmin-powershell-script-library)

## Ground rules

- **Sanitized by construction.** Everything here was rewritten from scratch for teaching — no real
  host names, domains, IPs, emails, or employer anything. Examples use the lab domain
  `corp.example.lab` and generic names like `DC01`, `FS01`. Swap in your own values.
- **Lab-first.** Test in a lab before pointing anything at production. Destructive scripts support
  `-WhatIf` / `-Confirm` — **use them first.**
- **Original work only.** Genuinely useful scripts written by others (e.g. Brian Wilhite's
  `PendingReboot` module) are not republished here; where a script covers the same ground as a
  community classic, it's an independent implementation and the file says so. The blog posts link
  to and credit the original authors.
- **Reviewed, but no warranty.** Teaching examples, provided as-is. Read them, understand them,
  test them.

## The series library (Sr. SysAdmin PowerShell, eps 1–6 + profile)

| Folder | Scripts |
|---|---|
| `ad/` | `Get-InactiveADComputer` · `Disable-InactiveADUser` · `Copy-ADUser` · `Test-ADCredential` · `Sync-HRUserToAD` (nightly HR-export → AD sync skeleton) |
| `gpo/` | `Find-GPOBySetting` — search every GPO in the domain for a string |
| `monitoring/` | `Get-LoggedOnUser` · `Get-Uptime` · `Get-PendingReboot` · `Get-DiskFreeSpace` |
| `network/` | `Start-PingLogger` (log dropped connections) · `Test-Subnet` (fast /24 sweep) |
| `files/` | `Remove-OldFile` — retention cleanup for backup folders |
| `reporting/` | `Export-FolderAcl` — NTFS permissions audit to CSV |
| `profile/` | `profile.ps1` + `PCAddicts.Tools.psm1` — profile and personal-module templates |

## The classics (root of the repo)

The original "steal these" set from the
[My Favorite PowerShell Scripts](https://pc-addicts.com/tutorials/my-favorite-powershell-scripts)
video — kept with the exact names the post uses:

| Script | What it does |
|---|---|
| `Get-LoggedIn.psm1` | Who is currently logged into a computer (pipeline-friendly). |
| `Get-Uptime.psm1` | Uptime + last boot time for one or many computers. |
| `Disable-UnusedADAccounts.ps1` | Find and disable AD users inactive for N days, with an audit stamp and `-WhatIf`. |
| `Get-DiskSpace.ps1` | Emailed HTML disk-space report (with RAM/CPU/build date) across a server list. |
| `New-ADUsersFromCsv.ps1` | Bulk-create AD users from a CSV, temp password + change-at-logon, `-WhatIf`. |

## Conventions

- Windows PowerShell 5.1 compatible (PS 7 differences noted in comments).
- `[CmdletBinding()]`, comment-based help, approved verbs on everything —
  `Get-Help .\Get-Uptime.ps1 -Full` works on every file.
- Objects out, not text — pipe to `Export-Csv`, `Where-Object`, whatever you need.
- Every file ends with a commented-out example, so pasting a whole file changes nothing.

## Using them

```powershell
# Dot-source a .ps1 to load its function, then run it:
. .\ad\Disable-InactiveADUser.ps1
Disable-InactiveADUser -DaysInactive 180 -WhatIf

# Or import a module:
Import-Module .\profile\PCAddicts.Tools.psm1
Get-CDUptime -ComputerName DC01
```

## License

MIT — see [LICENSE](LICENSE). Use them, ship them, teach with them. Credit appreciated, not
required.

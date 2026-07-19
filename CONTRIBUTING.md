# Contributing

Thanks for wanting to make these scripts better. This library is the "steal these" companion to the
[PC-Addicts YouTube channel](https://www.youtube.com/@PC-Addicts) — the scripts here get demonstrated
on camera and linked from written walkthroughs, so the bar is "clear enough to teach from," not just
"works on my machine." A few ground rules keep it that way.

## Two ways to help

- **Open an Issue** — found a bug, a script that breaks on a certain PowerShell version, or have an
  idea? Open an Issue. No code required. This is the best first step for anything you're unsure about.
- **Open a Pull Request** — got a fix or an improvement ready? Fork the repo, make your change on a
  branch, and open a PR. A short checklist appears when you do — please fill it in. I review every PR
  personally; nothing merges without that review.

If a change is large or reshapes how a script works, please open an Issue first so we can talk it
through before you spend time on it.

## The house style

Everything here is Windows PowerShell **5.1 compatible** (note any PS 7 differences in a comment) and
follows the same shape as the existing scripts:

- **Approved verbs.** `Get-`, `Set-`, `New-`, `Remove-`, etc. Run `Get-Verb` if unsure.
- **`[CmdletBinding()]`** on every script, and **comment-based help** (`.SYNOPSIS`, `.DESCRIPTION`,
  `.PARAMETER`, `.EXAMPLE`) so `Get-Help .\Your-Script.ps1 -Full` works.
- **Objects out, not text.** Return objects the caller can pipe to `Export-Csv` / `Where-Object`.
  Avoid `Write-Host` for data (fine for status lines).
- **End with a commented-out example**, so dot-sourcing or pasting a whole file changes nothing.
- Match the surrounding formatting — 4-space indent, splatting for long parameter sets, the same
  comment density you see in the neighboring scripts.

## The safety rules (these are non-negotiable)

Because a viewer will copy-paste these into a real environment, and because they appear in videos:

1. **No real data. Ever.** No real host names, domains, IPs, emails, usernames, or employer anything —
   not in code, not in comments, not in example output. Use the lab domain `corp.example.lab` and
   generic names like `DC01`, `FS01`, `alovelace`. This is the fastest way to get a PR closed.
2. **Nothing destructive without a confirm flag.** Anything that deletes, disables, or overwrites must
   support `-WhatIf` / `-Confirm` (`[CmdletBinding(SupportsShouldProcess = $true)]`) and default to the
   safe path. Show `-WhatIf` in the `.EXAMPLE`.
3. **Lab-first.** Test your change in a lab before submitting. Say so in the PR.
4. **No hardcoded secrets.** Passwords are `SecureString` and prompted for, never baked in.
5. **Original work only.** Don't paste in code you don't have the right to share. If your script covers
   the same ground as a well-known community module, that's fine — write your own implementation and
   credit the original in a comment.

## Licensing

This repo is MIT (see [LICENSE](LICENSE)). By opening a pull request, you agree your contribution is
your own work and can be published under the same MIT license.

## Not sure?

Open an Issue and ask. A question is always welcome — better a quick thread than a closed PR.

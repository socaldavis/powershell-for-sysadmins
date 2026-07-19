<!--
  Thanks for the contribution! This checklist appears automatically when you open a PR.
  Fill it in — it helps me review quickly, and it keeps content that ends up on camera safe.
  See CONTRIBUTING.md for the full house style.
-->

## What does this change?

<!-- One or two sentences. Which script, and what's different? -->

## Why?

<!-- Bug fix? New script? Cleanup? Link an Issue with "Fixes #123" if there is one. -->

## Checklist

- [ ] **No real data** — no real host names, domains, IPs, emails, usernames, or employer info. Uses
      the lab domain `corp.example.lab` and generic names (`DC01`, `FS01`, `alovelace`).
- [ ] **Not destructive without a flag** — anything that deletes/disables/overwrites supports
      `-WhatIf` / `-Confirm` and defaults to the safe path (or this PR changes nothing destructive).
- [ ] **Tested in a lab** — I ran this and it does what the description says.
- [ ] **House style** — approved verb, `[CmdletBinding()]`, comment-based help, objects out, ends with
      a commented-out example. (See CONTRIBUTING.md.)
- [ ] **PowerShell 5.1 compatible** — or PS 7-only differences are noted in a comment.
- [ ] **No hardcoded secrets** — passwords are `SecureString`, prompted for, never baked in.
- [ ] **My own work** — I have the right to share this under the repo's MIT license.

## How I tested it

<!-- e.g. "Ran against a Server 2025 lab DC with a 5-row CSV, confirmed -WhatIf listed all 5 and made no changes." -->

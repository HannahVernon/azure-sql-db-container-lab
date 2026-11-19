## What does this PR do?
<!-- Describe the change and why it's needed. Link to the related issue if one exists. -->

Fixes #

## How was this tested?
<!-- Say which runtime, platform and image digest you used. -->

- [ ] PowerShell files parse in Windows PowerShell 5.1 and PowerShell 7
- [ ] `shellcheck scripts/*.sh compose/*.sh` is clean
- [ ] Started the lab, ran `sql/build-check.sql` and `tests/change-tracking/Test-ChangeTracking.ps1`, and stopped it
- [ ] Runtime and platform: ___
- [ ] Image digest: ___

## Checklist

- [ ] I have read the [Contributing Guide](../CONTRIBUTING.md)
- [ ] Changes are focused - one logical change per PR
- [ ] Documentation updated (if user-visible behaviour changed)
- [ ] The password never reaches a command line, an environment variable of a host process, a log, `docker inspect` or the console
- [ ] No real host names, databases, passwords or customer data
- [ ] No commented-out code or debug leftovers

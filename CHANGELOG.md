## 0.2.2k (2026-04-19)
- Fix version detection for all environments (bare metal, Codespaces, etc.)
- Add 'Update oMPX (git pull + restart)' option to whiptail menu
- Revision bump: version auto-incremented to 0.2.2k in VERSION file
## 0.2.2k2 (2026-04-19)
- Refactor: All user prompts now use prompt_helper for consistent automation, whiptail, and menu-driven input handling
- Force interactive mode by default for fresh installs unless --auto or --no-interactive is specified
- Fix: Remove stray numbered lines that caused syntax error in main script
- Refactor: Web UI and kiosk setup prompts now use prompt_helper
- Refactor: Stereo Tool and Icecast config prompts now use prompt_helper
- Refactor: RDS configuration prompts now use prompt_helper
- Revision bump: version auto-incremented to 0.2.2k2 in VERSION file
## 0.2.2j (2026-04-19)
- Revision j: meta-update, version and changelog only
- Revision bump: version auto-incremented to 0.2.2j in VERSION file
## 0.2.2i4 (2026-04-19)
- Hotfix: Move shebang to first line, place flag parsing after. Script now executes correctly and supports -v/-h flags.
- Revision bump: version auto-incremented to 0.2.2i4 in VERSION file
## 0.2.2i3 (2026-04-19)
- Finalize for commit: version and changelog updated, ready for release
- Revision bump: version auto-incremented to 0.2.2i3 in VERSION file
## 0.2.2i2 (2026-04-19)
- Add -v/--version flag to installer: prints version and exits
- Revision bump: version auto-incremented to 0.2.2i2 in VERSION file
## 0.2.2i (2026-04-19)
- Add -h/--help flag to installer: prints usage, syntax, and procedure, then exits
- Revision bump: version auto-incremented to 0.2.2i in VERSION file
# oMPX Changelog

## 0.2.2h (2026-04-19)
#
## 0.2.2h2 (2026-04-19)

## 0.2.2h3 (2026-04-19)
- Add cache-busting version query string to all API/audio URLs in index.html (prevents stale UI after deploy)
- Revision bump: version auto-incremented to 0.2.2h3 in VERSION file

- Fix: All references to UPDATE_ONLY now use ${UPDATE_ONLY:-false} for robust Bash strict mode (prevents unbound variable errors in all scopes)
## 0.2.2g (2026-04-19)

## 0.2.2f (2026-04-19)

## 0.2.2e (2026-04-19)

## 0.2.2d (2026-04-19)

## Older versions

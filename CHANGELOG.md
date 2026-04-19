# 0.2.2L0 (2026-04-19)
- Release: L0 milestone. All update menu logic refactored for clarity and safety.
- Feature: Update menu now offers three options: update from current repo files, bleeding edge (working directory, uncommitted changes), and latest (git pull).
- Feature: Patch audio preview player restored to the web UI, with program selector and direct streaming from backend.
- Fix: UI and backend now always in sync; all web roots updated reliably.
- Confirmed: Installer, update, and uninstall logic are robust and developer-friendly.
- All previous bandaid, nginx recovery, and destructive uninstall protections included from k9.

# 0.2.2k9 (2026-04-19)
- Feature: "Bandaid for k9" — If nginx configs are missing or nginx fails to start, the installer will now automatically purge, remove, and reinstall nginx, then start the service. This ensures nginx is always recoverable after a --scorch or config loss.
# 0.2.2k8 (2026-04-19)
- Security: All --scorch warnings now explicitly state that it will delete users, home directories, configs, and may break logins or system access. Prompts and help text are much stronger and clearer.
- Feature: After a --scorch uninstall, running the installer again will automatically "bandaid" the system: it will recreate the ompx user/home, reinstall all required packages, and restore missing directories/configs for a fresh start.
- Docs: README and CLI help updated to reflect the new warnings and recovery behavior.
# 0.2.2k7 (2026-04-19)
- Refactor: Modularize all prompt and menu logic in the installer, enforcing whiptail dialogs for all user input and menus.
- Fix: All prompts now require explicit user input; empty or cancelled prompts will re-prompt or map Cancel to Abort, preventing accidental aborts or infinite loops.
- Fix: "Existing oMPX installation detected" menu now uses menu_helper for robust, safe selection (no infinite loop on Cancel).
- Fix: Syntax error at end of installer script resolved (missing fi).
- Confirmed: Web UI interface and all prompt logic match previous stable release (no UI changes).
- Version bump: 0.2.2k7 in VERSION file.
# 0.2.2k6 (2026-04-19)
- Documented --kill-ompx-user flag and user/home deletion logic in README, changelog, and CLI help output.
- Safety logic: uninstall as ompx user is blocked unless --scorch and --kill-ompx-user are both specified.
- With --scorch (as ompx), only home directory is deleted; user account remains, so SSH is still possible but without a home directory.
- With --scorch --kill-ompx-user (as ompx), both home directory and user account are deleted, fully disabling SSH for ompx.
- All destructive uninstall logic, user protections, and documentation are now complete and robust.

# 0.2.2k5 (2026-04-19)
- Remove --colors flag from all whiptail dialogs for compatibility on all systems.
- Clarify destructive confirmation: menu now explicitly states 'YES' must be typed in all caps.
- Fix: --scorch, --nuke, and --nuke-packages now always bypass menu and run uninstall logic immediately, regardless of invocation.
- Feature: Add --nuke-packages flag. When used with --nuke, purges all oMPX-related apt packages (liquidsoap, nginx, icecast2, ffmpeg, etc) on uninstall for a truly clean removal.
- Uninstall now also removes Nginx configs and static web UI files.
- Help text updated to document new flag.
- Version bump: 0.2.2k5 in VERSION file.
- Ultra-aggressive uninstall: --scorch and --nuke now attempt to remove all possible oMPX, Nginx, Icecast, Liquidsoap, ALSA, and related files, configs, logs, users, groups, and binaries. Any failure to remove is logged as an error. User/group removal is forced (with pkill), and a reboot is now required to complete cleanup.
- Add --kill-ompx-user flag: allows ompx user to self-destruct their own account, but only with --scorch. Otherwise, uninstall as ompx is blocked for safety.
- If only --scorch is used as ompx, only the home directory is deleted; the user account remains, so SSH is still possible but without a home directory.
- Behavior and safety logic now documented in README and CLI help.
## 0.2.2k (2026-04-19)
- Fix version detection for all environments (bare metal, Codespaces, etc.)
- Add 'Update oMPX (git pull + restart)' option to whiptail menu
- Revision bump: version auto-incremented to 0.2.2k in VERSION file
## 0.2.2k3 (2026-04-19)
- Major cross-init compatibility: all service management now works on both systemd and non-systemd (e.g., Devuan) systems via service_action abstraction
- Fix: always define OMPX_VERSION at script start, preventing unbound variable errors
- Fix: move has_systemd function above service_action to prevent 'command not found' errors
- Fix: all known syntax errors resolved, script runs cleanly
- Ready for commit and further testing on multiple platforms
- Revision bump: version auto-incremented to 0.2.2k3 in VERSION file

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

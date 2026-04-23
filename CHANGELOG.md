# 0.2.2m1 (2026-04-23)
- Versioning fix: VERSION file is now at repo root, not in encoder/.
- All static file serving, backend, and UI fixes from 0.2.2L11 included.
- Ready for bare metal and Codespaces testing.
# 0.2.2L11 (2026-04-23)
- Fix: Static file serving is now robust and correct for all .js and .css files; MIME errors and browser blocks resolved.
- Fix: All indentation and logic errors in backend and utility scripts resolved; backend now starts cleanly on any system.
- Feature: Real-time slider updates in the web UI now send values to the backend as you drag, with visible error alerts for any JS/UI issues.
- Dev: Debug logging added for slider input and static file serving; easier troubleshooting for UI/backend integration.
- Dev: Backend and UI now fully portable between Codespaces and bare metal (port config, working directory, and cache-busting all tested).

# 0.2.2L10 (2026-04-23)
- UI/UX: Major refactor. Each program (Program 1, Program 2) now has its own dedicated HTML page (program1.html, program2.html) for clarity and maintainability.
- UI/UX: Sidebar navigation highlights only the active page; unavailable features are dimmed and unclickable.
- UI/UX: All controls for Program 1 and Program 2 are now implemented in their respective pages.
- UI/UX: Button and inactive/active state styling improved for clarity and accessibility.
- Dev: Modern and legacy UIs are now fully separated for easier debugging and deployment.
# 0.2.2L9 (2026-04-22)
- UI/UX: Added cache-busting version query to all audio preview and API URLs in the web UI for reliable updates.
- Backend: Set strict no-cache headers for all main endpoints (HTML, audio preview) to prevent browser caching issues.
- Fix: Confirmed full original HTML is present and served as intended; clarified that 'html content omitted' is a viewer/editor artifact, not a runtime problem.
- Version bump: 0.2.2L9 in VERSION and UI footer/banner.
# 0.2.2L8 (2026-04-22)
- Feature: MasterMe web UI now includes a live audio player for the Icecast /mpx stream, enabling browser-based audio visualization and monitoring.

# 0.2.2L7 (2026-04-21)
- Fix: Installer now always continues to the main dispatcher after Icecast configuration, ensuring install/update logic runs after prompts.
# 0.2.2L6 (2026-04-21)
- Refactor: Fully modular installer. All install, update, uninstall, and configuration logic is now in sub-scripts for maintainability and portability.
- Fix: All block structure and syntax errors resolved. No more 'unexpected end of file' or 'unexpected token fi' errors.
- Feature: Always prompts for Icecast settings on install/update/reinstall, with auto-generated password if left blank.
- Fix: Installer now always continues to the next step after prompts, with clear progress messages.
- Robust: Sub-scripts are made executable automatically; permission errors are handled.
- Debug: Added debug tracing and improved error handling for interactive prompts.
- Confirmed: Script works on bare metal in a real terminal (not in file managers).
# 0.2.2L3 (2026-04-19)
# 0.2.2L4 (2026-04-20)
# 0.2.2L5 (2026-04-21)
- Feature: Robust scorched system repair. After a destructive uninstall (--scorch), the installer will now automatically recreate the ompx user and home, reinstall all required packages, restore critical directories, and ensure the Icecast2 systemd service is present and running. This makes recovery from a scorched or partially removed system seamless and reliable.
- Ready for next steps: interface refinements and advanced audio processing (e.g., Master Me integration).
# 0.2.2L2 (2026-04-19)
# 0.2.2L0 (2026-04-19)

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

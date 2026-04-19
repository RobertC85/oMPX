# oMPX Changelog

## 0.2.2d (2026-04-19)
- Revision bump: version auto-incremented to 0.2.2d in VERSION file

## 0.2.2b (2026-04-19)
- Fix: Nginx config heredoc now uses unquoted delimiter for variable expansion, and escapes $uri as \$uri
- This resolves the bug where the config contained a literal ${OMPX_WEB_PORT} instead of the actual port number, causing Nginx to fail to start
- Patch installer to automatically disable conflicting ompx-8082.conf for Nginx
- Ensure only ompx-web-ui serves port 8082 with correct root
- Improved deployment reliability for web UI updates
- The installer now always quotes the heredoc for Nginx config blocks, preventing future $uri expansion issues

## Older versions
- See previous commit history for details prior to 0.2.2b

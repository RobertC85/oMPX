# oMPX Changelog

## 0.2.2b (2026-04-19)
- Patch installer to automatically disable conflicting ompx-8082.conf for Nginx
- Ensure only ompx-web-ui serves port 8082 with correct root
- Improved deployment reliability for web UI updates
- Fix: Quote Nginx config heredoc in installer to prevent Bash unbound variable error with $uri
- The installer now always quotes the heredoc for Nginx config blocks, preventing future $uri expansion issues

## Older versions
- See previous commit history for details prior to 0.2.2b

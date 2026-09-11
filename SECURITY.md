# Security policy

| Issue is in… | Report to |
|---|---|
| the wrapper: `Dockerfile`, `scripts/entrypoint.sh`, `scripts/bootstrap-admin.mjs`, template variable wiring, exposure, secrets in logs, CI/publishing | this repository — GitHub "Report a vulnerability" on https://github.com/youssefsiam38/storyteller-railway/security, or an issue without exploit details |
| Storyteller itself (authentication, uploads, alignment pipeline, dependencies) | upstream at https://gitlab.com/storyteller-platform/storyteller (issues; no published security policy as of 2026-09-11) |

## What this wrapper does and does not protect

- Creates the administrator **before** the service is reachable, from per-deployment generated
  variables, so the unauthenticated setup page is never exposed.
- Runs the application as the unprivileged `storyteller` user (upstream behaviour); only the
  entrypoints run as root to fix volume ownership.
- Never prints variable values.
- Does not add rate limiting, WAF, or SSO. Storyteller's own login, invites, and OAuth are used
  as shipped upstream. Change the generated admin password after first login if you prefer one
  you chose.

Only the newest published tag receives fixes; tags are never moved.

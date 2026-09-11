# Maintenance

## Watch upstream

- Tags: `curl -s "https://gitlab.com/api/v4/projects/storyteller-platform%2Fstoryteller/repository/tags?search=web-v&per_page=20" | jq -r '.[].name'`
  Use `web-vX.Y.Z` stable tags only; skip `beta`/`experimental`.
- Image tag: `docker buildx imagetools inspect registry.gitlab.com/storyteller-platform/storyteller:web-vX.Y.Z`
- Release notes: https://gitlab.com/storyteller-platform/storyteller/-/releases (filter `web-v`) and
  https://storyteller-platform.dev/blog.
- Security: no advisory feed upstream; review releases and Node dependency bumps monthly and within
  48 h of any release mentioning auth, uploads, or the alignment pipeline.

## Upgrade procedure

1. Update `ARG STORYTELLER_IMAGE=` (tag **and** digest) and `ARG STORYTELLER_VERSION=` in
   `Dockerfile`.
2. Check that `scripts/bootstrap-admin.mjs` still matches upstream's `createAdminUser()`
   (`applications/web/src/database/users.ts`) and the `user` / `user_permission` / `settings`
   schema; adjust the INSERT column lists if a migration added permissions.
3. Confirm the argon2 module path in the image (`/app/.next/standalone/node_modules/argon2`); the
   build step `gosu storyteller node -e "require(...)"` fails loudly otherwise.
4. `docker compose build && tests/static.sh && tests/smoke.sh && tests/persistence.sh`
   (add `RUN_ALIGNMENT=1` for the full alignment path).
5. Upgrade test against existing data: run the previous release against a volume with a book,
   then start the new image on the same volume; confirm migrations succeed, login works, the book
   is still listed.
6. Update README versions table, UPSTREAM.md, THIRD_PARTY_NOTICES.md; commit; wait for CI.
7. Tag `vA.B.C`, push, `gh run watch --exit-status` on `publish-image`, record the digest.
8. Anonymous pull check: `DOCKER_CONFIG=$(mktemp -d) docker pull ghcr.io/youssefsiam38/storyteller-railway:A.B.C`.
9. `gh release create vA.B.C --notes-file …` (upstream version, digests, architectures, migration
   notes, test evidence; no AI attribution).
10. In the Railway template composer set the `storyteller` service image to the new tag (Railway
    rejects `@sha256` references), save, run a clean-room deploy, then consider the template updated.

## Railway template operations

- Metadata: `npx -y @railway/cli@latest templates update <TEMPLATE_ID> --category Other --description "…" --readme-file RAILWAY_TEMPLATE.md --json`
- Service config lives in the dashboard composer; verify with the public API
  `template(id) { serializedConfig }` (readable with the CLI token) after saving.
- Clean-room deploy: new project, `railway deploy -t <CODE> -v "storyteller.STORYTELLER_ADMIN_EMAIL=…"`,
  wait for SUCCESS, run `tests/railway-smoke.sh https://<domain>` with the generated password read
  from `railway variable list --json` (never printed), then delete the project by ID.
- Rollback: point the template's service image back to the last known-good tag.
- Unpublish (keeps user deployments): `npx -y @railway/cli@latest templates unpublish <ID> --yes --json`.
- Support: Railway template queue and GitHub issues; fold recurring answers into README.

## Cadence

Weekly glance at upstream tags and the template queue; monthly full review; act on stable upstream
releases within a week.

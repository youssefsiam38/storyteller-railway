// Creates the first administrator from environment variables, replicating what Storyteller's
// /init page does (applications/web/src/database/users.ts createAdminUser), and seeds
// libraryName / webUrl when they are still empty. Runs as the storyteller user against the SQLite
// database (first boot: while the app listens on loopback; later boots with --settings-only:
// before the app starts). Idempotent: never overwrites a value a user has set.
// Never prints variable values.
import { DatabaseSync } from "node:sqlite"
import { randomUUID } from "node:crypto"
import { createRequire } from "node:module"
import path from "node:path"

const log = (m) => process.stderr.write(`[storyteller-railway] ${m}\n`)
const fail = (m) => { log(`FATAL: ${m}`); process.exit(1) }

const dataDir = process.env.STORYTELLER_DB_DIR || process.env.STORYTELLER_DATA_DIR || "/data"
const dbFile = path.join(dataDir, process.env.STORYTELLER_DB_FILENAME || "storyteller.db")
const username = (process.env.STORYTELLER_ADMIN_USERNAME || "").trim().toLowerCase()
const password = process.env.STORYTELLER_ADMIN_PASSWORD || ""
const email = (process.env.STORYTELLER_ADMIN_EMAIL || "").trim()
const name = (process.env.STORYTELLER_ADMIN_NAME || "Administrator").trim()
const webUrl = (process.env.STORYTELLER_WEB_URL || "").trim()
const libraryName = (process.env.STORYTELLER_LIBRARY_NAME || "").trim()

const settingsOnly = process.argv.includes("--settings-only")

const db = new DatabaseSync(dbFile)
db.exec("PRAGMA busy_timeout = 10000")

if (settingsOnly) {
  seedSettings()
  db.close()
  process.exit(0)
}

if (!username || !password || !email) fail("STORYTELLER_ADMIN_USERNAME, STORYTELLER_ADMIN_PASSWORD and STORYTELLER_ADMIN_EMAIL are required for admin bootstrap")
if (password.length < 12) fail("STORYTELLER_ADMIN_PASSWORD must be at least 12 characters")
if (!/^[^@\s]+@[^@\s]+$/.test(email)) fail("STORYTELLER_ADMIN_EMAIL is not a valid email address")

// Use the exact argon2 build the application uses so hashes verify identically.
const require = createRequire(import.meta.url)
const argon2 = require(process.env.STORYTELLER_ARGON2_PATH || "/app/.next/standalone/node_modules/argon2")

const userCount = db.prepare("SELECT count(*) AS n FROM user").get().n
const permCount = db.prepare("SELECT count(*) AS n FROM user_permission").get().n

if (userCount > 0) {
  log(`admin bootstrap skipped: ${userCount} user(s) already exist`)
} else {
  if (permCount > 0) fail("user_permission rows exist without users; refusing to bootstrap (inspect the database)")
  const hashed = await argon2.hash(password)
  const permUuid = randomUUID()
  const userId = randomUUID()
  db.exec("BEGIN IMMEDIATE")
  try {
    db.prepare(`INSERT INTO user_permission (uuid, book_create, book_delete, book_read, book_process, book_download,
      book_update, book_list, collection_create, invite_list, invite_delete, user_create, user_list, user_read,
      user_delete, user_update, user_password_reset, settings_update)
      VALUES (?,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1)`).run(permUuid)
    db.prepare(`INSERT INTO user (id, username, name, email, hashed_password, user_permission_uuid)
      VALUES (?,?,?,?,?,?)`).run(userId, username, name, email, hashed, permUuid)
    db.exec("COMMIT")
  } catch (e) {
    db.exec("ROLLBACK")
    fail(`could not create the administrator: ${e.message}`)
  }
  log(`admin bootstrap complete: created administrator "${username}" (password length ${password.length})`)
}

seedSettings()
db.close()

// Seed settings only while they are still empty (or a host-less URL left by an earlier boot before
// the public domain existed), so values people set in the UI are never overwritten.
function hasHost(u) { try { return Boolean(new URL(u).hostname) } catch { return false } }
function isEmptySetting(v) {
  if (v === undefined || v === null || v === "" || v === '""' || v === "null") return true
  try { const parsed = JSON.parse(v); return parsed === "" || parsed === null } catch { return false }
}
function seedSettings() {
  const seed = (key, value, ok = () => true) => {
    let row
    try { row = db.prepare("SELECT value FROM settings WHERE name = ?").get(key) } catch { row = undefined }
    if (!row) { log(`setting ${key}: row missing (schema not ready or older version), not seeded`); return }
    const current = (() => { try { return JSON.parse(row.value) } catch { return row.value } })()
    const currentIsHostless = key === "webUrl" && typeof current === "string" && current !== "" && !hasHost(current)
    if (!isEmptySetting(row.value) && !currentIsHostless) { log(`setting ${key}: already set, left unchanged`); return }
    if (!ok(value)) { log(`setting ${key}: skipped (value has no host yet)`); return }
    db.prepare("UPDATE settings SET value = ?, updated_at = CURRENT_TIMESTAMP WHERE name = ?").run(JSON.stringify(value), key)
    log(`setting ${key}: seeded`)
  }
  if (webUrl) seed("webUrl", webUrl, hasHost)
  if (libraryName) seed("libraryName", libraryName)
}

#!/usr/bin/env node
/**
 * Dependency hygiene gates for the monorepo root (bun-only app).
 *
 * Enforces:
 *  - root package manager is bun (when invoked as preinstall / install hook)
 *  - root package-lock.json must not exist (stale npm lock regresses CVE pins)
 *  - bun.lockb or bun.lock must exist
 *
 * remote-bridge/ may keep its own package-lock.json (independent npm package).
 *
 * Usage:
 *   bun scripts/check-deps-hygiene.mjs           # lockfile checks only
 *   bun scripts/check-deps-hygiene.mjs --preinstall  # also reject npm/yarn installs
 */
import { existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const preinstall = process.argv.includes("--preinstall");
let failed = false;

function fail(msg) {
  console.error(`deps-hygiene: ${msg}`);
  failed = true;
}

if (preinstall) {
  const ua = process.env.npm_config_user_agent || "";
  // Allow bun; reject npm / yarn / pnpm install of the root tree.
  if (!/\bbun\//.test(ua)) {
    fail(
      "Root package manager is bun only. Use `bun install` (do not use npm/yarn/pnpm at repo root).",
    );
    fail(`Detected user-agent: ${ua || "(empty)"}`);
  }
}

const rootNpmLock = join(root, "package-lock.json");
const bunLock = join(root, "bun.lockb");
const bunLockText = join(root, "bun.lock");

if (existsSync(rootNpmLock)) {
  fail(
    "Root package-lock.json must not exist. Delete it and rely on bun.lockb/bun.lock. (remote-bridge/ may keep its own lockfile.)",
  );
}

if (!existsSync(bunLock) && !existsSync(bunLockText)) {
  fail("bun.lockb or bun.lock is required at the repository root.");
}

if (failed) {
  process.exit(1);
}

if (!preinstall) {
  console.log("deps-hygiene: ok (bun-only root, no stale package-lock.json)");
}

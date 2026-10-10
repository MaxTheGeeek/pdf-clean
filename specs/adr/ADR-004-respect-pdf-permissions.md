# ADR-004 · Respect encryption and copy permissions

**Status:** Accepted · **Date:** 2026-10-10

## Context
Some PDFs are encrypted or disallow copying. Removing tracking content is legitimate for
documents a user owns or is authorised to process; circumventing access controls is not.

## Decision
Open encrypted PDFs only with the user's password. If copying is disallowed, refuse
unless the user supplies the owner password (`permissionsStatus == .owner`).

## Consequences
+ Clear, defensible behaviour; no DRM circumvention.
− Users without the owner password cannot process copy-restricted files (by design).

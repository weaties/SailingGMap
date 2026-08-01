#!/usr/bin/env bash
#
# bootstrap-dependency.sh — work around GeneralizedMap's unbuildable manifest.
#
# GeneralizedMap 0.1.0 declares `swift-tools-version: 6.4`, which no released
# Swift toolchain can parse (newest release: 6.3.3). Nothing in either project
# actually requires 6.4 — the declaration is purely a gate.
#
# This script clones the package as a sibling, rewrites the manifest to a
# version the local toolchain understands, and writes an .xcworkspace in which
# the local checkout shadows the remote package reference. project.pbxproj is
# never modified.
#
# Delete this script (and docs/toolchain.md §1) once GeneralizedMap is retagged.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEP_NAME="GeneralizedMap"
DEP_TAG="0.1.0"
DEP_URL="https://github.com/SinanKarasu/${DEP_NAME}.git"
TARGET_TOOLS_VERSION="6.3"
# Must satisfy the `from: "0.1.0"` requirement in Packages/SailingCore/Package.swift
# and sort above the real 0.1.0 so SwiftPM prefers it.
PATCHED_TAG="0.1.1"

# The checkout directory MUST be named exactly `GeneralizedMap`: Xcode matches a
# workspace-local package to the remote reference it shadows by *package name*,
# which it derives from the directory. A differently-named directory resolves as
# an unrelated package and the remote reference is fetched anyway — which then
# fails on the 6.4 manifest. Hence a parent override, not a path override.
DEP_PARENT="${GENERALIZEDMAP_PARENT:-$(dirname "$REPO_ROOT")}"
DEP_DIR="${DEP_PARENT}/${DEP_NAME}"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }

# --- 1. checkout -------------------------------------------------------------

if [ -d "$DEP_DIR/.git" ]; then
  log "Found existing checkout at $DEP_DIR"
  git -C "$DEP_DIR" fetch --tags --quiet origin || warn "fetch failed; using local state"
else
  log "Cloning $DEP_URL -> $DEP_DIR"
  git clone --quiet "$DEP_URL" "$DEP_DIR"
fi

if ! git -C "$DEP_DIR" rev-parse -q --verify "refs/tags/${DEP_TAG}" >/dev/null; then
  warn "tag ${DEP_TAG} not found in $DEP_DIR"
  exit 1
fi

# Detached checkout of the tag keeps this reproducible and avoids clobbering a
# branch the user may be working on.
git -C "$DEP_DIR" checkout --quiet --detach "refs/tags/${DEP_TAG}"

# --- 2. patch the manifest ---------------------------------------------------

MANIFEST="$DEP_DIR/Package.swift"

log "Rewriting manifest tools-version -> ${TARGET_TOOLS_VERSION}"
# Only the first line; the rest of the manifest is untouched.
sed -i.bak -E "1s|// *swift-tools-version: *.*|// swift-tools-version: ${TARGET_TOOLS_VERSION}|" "$MANIFEST"
rm -f "${MANIFEST}.bak"

# --- 2b. commit and tag ------------------------------------------------------
#
# SwiftPM resolves a versioned dependency by checking out a *tag*, so patching
# the working tree alone is not enough — the tag still carries the 6.4 manifest
# and resolution fails exactly as before. We therefore commit the patch and tag
# it ${PATCHED_TAG}, which satisfies the `from: "0.1.0"` requirement while
# carrying a manifest the installed toolchain can parse.
#
# This tag is local-only and never pushed. It disappears when the upstream
# package is retagged and this script is deleted.

if ! git -C "$DEP_DIR" diff --quiet -- Package.swift; then
  git -C "$DEP_DIR" -c user.name="bootstrap" -c user.email="bootstrap@local" \
    commit --quiet -m "local: swift-tools-version ${TARGET_TOOLS_VERSION} (see SailingGMap docs/toolchain.md)" \
    -- Package.swift
fi
git -C "$DEP_DIR" tag -f "$PATCHED_TAG" >/dev/null
log "Tagged patched manifest as ${PATCHED_TAG} (local only, never pushed)"

# --- 3. workspace ------------------------------------------------------------
#
# A local package in the workspace shadows the remote reference of the same
# name, so SwiftPM resolves against the patched checkout and never fetches.

WORKSPACE="$REPO_ROOT/SailingGMap.xcworkspace"
mkdir -p "$WORKSPACE"

# Relative path so the workspace is not machine-specific.
REL_DEP="$(python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$DEP_DIR" "$REPO_ROOT")"

cat > "$WORKSPACE/contents.xcworkspacedata" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<Workspace
   version = "1.0">
   <FileRef
      location = "group:SailingGMap.xcodeproj">
   </FileRef>
   <FileRef
      location = "group:${REL_DEP}">
   </FileRef>
</Workspace>
EOF

log "Wrote $WORKSPACE (dependency at ${REL_DEP})"

# --- 4. SwiftPM mirror for the standalone package ----------------------------
#
# `swift test --package-path Packages/SailingCore` resolves independently of
# Xcode, so it needs its own redirect from the remote URL to the local checkout.

CORE_PKG="$REPO_ROOT/Packages/SailingCore"
if [ -d "$CORE_PKG" ]; then
  MIRROR_DIR="$CORE_PKG/.swiftpm/configuration"
  mkdir -p "$MIRROR_DIR"
  cat > "$MIRROR_DIR/mirrors.json" <<EOF
{
  "object": [
    {
      "original": "${DEP_URL}",
      "mirror": "${DEP_DIR}"
    }
  ],
  "version": 1
}
EOF
  log "Wrote SwiftPM mirror for Packages/SailingCore"
fi

log "Done. Open SailingGMap.xcworkspace (not the .xcodeproj)."

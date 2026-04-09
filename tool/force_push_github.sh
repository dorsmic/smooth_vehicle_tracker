#!/usr/bin/env bash
# Force-push ce package vers GitHub (branche main), remote en HTTPS.
# Prérequis : dépôt créé sur GitHub + authentification (navigateur, PAT ou gh auth login).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ORIGIN_HTTPS="https://github.com/dorsmic/smooth_vehicle_tracker.git"

rsync -a \
  --exclude='.dart_tool' \
  --exclude='build' \
  --exclude='pubspec.lock' \
  --exclude='.flutter-plugins-dependencies' \
  --exclude='.git' \
  "$ROOT/" "$TMP/"

cd "$TMP"
git init -b main
git add -A
VER="$(grep '^version:' pubspec.yaml | awk '{print $2}')"
git commit -m "Release smooth_vehicle_tracker $VER"
git remote add origin "$ORIGIN_HTTPS"
git push -u origin main --force

echo "OK: force-push vers $ORIGIN_HTTPS (main, $VER)"

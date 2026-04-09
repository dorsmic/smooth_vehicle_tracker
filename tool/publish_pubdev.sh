#!/usr/bin/env bash
# Publier sur https://pub.dev (après dart pub login).
# Voir : https://dart.dev/tools/pub/publishing
set -euo pipefail
cd "$(dirname "$0")/.."
dart pub publish

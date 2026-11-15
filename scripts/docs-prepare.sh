#!/usr/bin/env bash
# Assemble the website source in ./site-src from the repo-root Markdown files.
# The runbooks stay at the repo root (readable on GitHub); this copies them for MkDocs.
set -euo pipefail
cd "$(dirname "$0")/.."
rm -rf site-src && mkdir -p site-src
cp README.md site-src/index.md                      # README becomes the home page
cp RUNBOOK.md CERT-ONBOARDING-RUNBOOK.md site-src/
cp -R manifests scripts site-src/                   # so links like scripts/make-user.sh work on the site

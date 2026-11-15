#!/usr/bin/env bash
# Replace one folder of the gh-pages branch and push, keeping everything else.
#   publish-pages.sh <source dir or ""> <dest: a game's folder (e.g. tether-rally), or <game>/pr/N> <message>
# An empty source deletes dest. Publishing a game's main build keeps its pr/ previews, and
# never touches the other games. The branch is kept to one commit (builds are large).
# The site's root pages (index.html, 404.html) are not on gh-pages: pages.yml adds them from
# .github/pages/ on main when it deploys.
set -euo pipefail
SRC="$1"; DEST="$2"; MSG="$3"
REPO="${PAGES_REPO:-https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git}"
for attempt in $(seq 1 10); do
  WORK="$(mktemp -d)"
  if git clone -q --depth 1 --branch gh-pages "$REPO" "$WORK" 2>/dev/null; then :; else
    git -C "$WORK" init -q -b gh-pages && git -C "$WORK" remote add origin "$REPO"
  fi
  cd "$WORK"
  OLD="$(git rev-parse -q --verify HEAD || true)"
  git config user.name "github-actions[bot]"
  git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
  case "$DEST" in
    ""|.|/*|*..*) echo "refusing to publish to '$DEST'"; exit 1 ;;
    pr/*|*/pr/*) rm -rf "$DEST" ;;
    # a game's main build: replace it, keeping that game's PR previews
    *) mkdir -p "$DEST"; find "$DEST" -mindepth 1 -maxdepth 1 ! -name pr -exec rm -rf {} + ;;
  esac
  if [ -n "$SRC" ]; then
    mkdir -p "$DEST"
    cp -r "$SRC/." "$DEST/"
  fi
  touch .nojekyll
  git add -A
  if [ -n "$OLD" ] && git diff --cached --quiet; then echo "nothing to publish"; exit 0; fi
  # keep a single commit on gh-pages so builds don't pile up in the repo's history;
  # the lease makes a build that raced with another one retry instead of overwriting it
  git checkout -q --orphan site
  git commit -q -m "$MSG"
  if git push -q --force-with-lease="gh-pages:${OLD}" origin site:gh-pages; then exit 0; fi
  echo "push raced with another build, retrying ($attempt)"
  cd / && rm -rf "$WORK"
  sleep $((attempt * 3))
done
exit 1

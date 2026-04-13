#!/usr/bin/env bash
#
# pull-all.sh — Git pull each repo under a parent directory,
#               skipping any with local changes.
#
# Usage: pull-all.sh [directory]
#        Defaults to the current directory if none given.

DIR="${1:-.}"

for repo in "$DIR"/*/; do
  [ -d "$repo/.git" ] || continue

  name=$(basename "$repo")

  if git -C "$repo" diff --quiet && git -C "$repo" diff --cached --quiet; then
    echo "pulling  $name"
    git -C "$repo" pull --quiet
  else
    echo "skipping $name (local changes)"
  fi
done

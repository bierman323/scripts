#!/usr/bin/env zsh

for f in *.m4a; do
  new=$(echo $f | sed -E "s/[0-9]-([A-Za-z].*)/\1/")
  echo "$f"
done

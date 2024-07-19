#!/bin/bash
# This is for Ubuntu WSL. The clock gets out of whack

if ! command -v ntpdate &> /dev/null; then
  echo "ntpdate could not be found"
  exit 1
else
  echo "Updating the time"
  command sudo ntpdate 0.pool.ntp.org
  echo "Time has been updated"
fi


#!/usr/bin/env zsh

# check to see if ntpdate is installed first
# I need to make sure that WSL2 Ubuntu is up to date or else I can't update the OS
if ! command -v clock.sh &> /dev/null; then
  echo "clock.sh could not be found"
  exit 1
else
  command clock.sh
fi

sudo apt-get update && sudo apt-get -y upgrade && sudo apt-get -y dist-upgrade && sudo apt -y autoremove

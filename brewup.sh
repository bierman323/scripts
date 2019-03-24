#!/bin/bash

# Get all the new updates
echo "Update"
brew update

# Upgrade it
echo "Upgrade"
brew upgrade

# Get rid of the old versions
echo "Cleanup"
brew cleanup

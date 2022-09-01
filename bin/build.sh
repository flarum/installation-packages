#!/bin/bash -l

# exit on error.
set -e

style='\e[47;1;31m'
reset='\e[0;10m'

# Setup Git.
echo -e "$style - setting up git $reset"
git config user.name 'flarum-bot'
git config user.email 'bot@flarum.org'

# Setup an isolated workspace.
echo -e "$style - setting up isolated workspace $reset"
mkdir installation_workspace
cd installation_workspace

# Install Flarum.
echo -e "$style - installing Flarum... $reset"
composer create-project flarum/flarum . --prefer-dist --no-interaction

# Install additional Extensions.
COMPOSER_PACKAGES = ''
if [[ "$BUNDLE_VALUE" != "default" ]]; then
  echo -e "$style - installing bundle $BUNDLE_NAME $reset"

  for p in "$BUNDLE_VALUE"; do
    COMPOSER_PACKAGES = "${COMPOSER_PACKAGES} ${p}:*"
  done

  composer require $COMPOSER_PACKAGES --no-interaction
fi

# Set file name and destination path.
FILE_NAME = flarum-$(FLARUM_VERSION)-$(BUNDLE_NAME)-php$(PHP_VERSION).tar.gz
FILE_DESTINATION = packages/flarum-$(FLARUM_VERSION)

# Create installation package.
cd ../
tar -czvf $FILE_NAME installation_workspace/*

# Move package to the flarum version folder.
mkdir -p $FILE_DESTINATION
mv $FILE_NAME $FILE_DESTINATION/

# Delete workspace.
rm -R installation_workspace

# Commit package.
git add $FILE_DESTINATION/*.tar.gz
git commit -m "Create installation packages for Flarum v$FLARUM_VERSION" -a
git push
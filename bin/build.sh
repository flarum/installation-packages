#!/bin/bash -l

# exit on error.
set -e

style='\e[47;1;31m'
reset='\e[0;10m'

# Setup Git.
echo -e "$style - setting up git $reset"
git config user.name 'flarum-bot'
git config user.email 'bot@flarum.org'

# Set installation workspace directory.
TMP_WORKSPACE=installation_workspace

# Set packages to require later based on bundle value.
COMPOSER_PACKAGES=""
if [[ "$BUNDLE_VALUE" != "default" ]]; then
  for p in $BUNDLE_VALUE; do
    COMPOSER_PACKAGES="${COMPOSER_PACKAGES} ${p}:*"
  done
fi

for php in $PHP_VERSIONS; do
  echo -e "$style - building for $php $reset"

  # Emulate PHP version.
  composer --global config platform.php $php

  # Setup an isolated workspace.
  echo -e "$style - setting up isolated workspace $reset"
  mkdir $TMP_WORKSPACE
  cd $TMP_WORKSPACE

  # Install Flarum.
  echo -e "$style - installing Flarum... $reset"
  composer create-project flarum/flarum . --prefer-dist --no-interaction

  # Install additional Extensions.
  if [[ "$COMPOSER_PACKAGES" != "" ]]; then
    echo -e "$style - installing bundle $BUNDLE_NAME $reset"

    composer require $COMPOSER_PACKAGES --no-interaction
  fi

  # Set file name and destination path.
  FILE_NAME=flarum-$FLARUM_VERSION-$BUNDLE_NAME-php$php
  FILE_DESTINATION=packages/v$FLARUM_VERSION

  # Create installation package.
  cd ../
  # tar.gz format.
  tar -czf $FILE_NAME.tar.gz $TMP_WORKSPACE/* > /dev/null
  # zip format.
  zip -r $FILE_NAME.zip $TMP_WORKSPACE/*

  # Move package to the flarum version folder.
  mkdir -p $FILE_DESTINATION
  mv $FILE_NAME.* $FILE_DESTINATION/

  # Track new packages.
  git add $FILE_DESTINATION/*

  # Delete workspace.
  rm -R $TMP_WORKSPACE
done

# Commit package.
git commit -m "Installation packages for Flarum v$FLARUM_VERSION" -a
git push
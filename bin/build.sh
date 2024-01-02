#!/bin/bash -l

# exit on error.
set -e

get_expected_version() {
    local FLARUM_VERSION="$1"

    # Remove the leading 'v' if it exists
    local version=${FLARUM_VERSION#v}

    # Pick the major version number
    IFS='.' read -ra version_parts <<< "$version"
    local major=${version_parts[0]}

    # stability tag
    local stability=$(get_stability_tag $version)

    # Construct the expected version
    local majorSemanticVersion=""
    if [ -n "$stability" ]; then
        majorSemanticVersion="$major.0-$stability"
    else
        majorSemanticVersion="$major.0"
    fi

    # Return the expected version
    echo "$majorSemanticVersion"
}

# get the stability tag from the version number
get_stability_tag() {
    local FLARUM_VERSION="$1"

    # Define stability tags
    local stabilityTags=("alpha" "beta" "rc" "dev")
    local stability=""

    # Check for stability suffix
    for tag in "${stabilityTags[@]}"; do
        if [[ $version == *"-$tag"* ]]; then
            stability=$tag
            break
        fi
    done

    # Return the stability tag
    echo "$stability"
}

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
    if [[ ${p} != *":"* ]]; then
      COMPOSER_PACKAGES="${COMPOSER_PACKAGES} ${p}:*"
    else
      COMPOSER_PACKAGES="${COMPOSER_PACKAGES} ${p}"
    fi;
  done
fi

# From the tag name which is in the format of v1.8.3 or v1.8.3-beta.13 extract a major version number (1.0)
FLARUM_COMPOSER_VERSION=$(get_expected_version $FLARUM_VERSION)
STABILITY_TAG=$(get_stability_tag $FLARUM_VERSION)

# default to stable if empty
if [ -z "$STABILITY_TAG" ]; then
    STABILITY_TAG="stable"
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
  composer create-project flarum/flarum:^$FLARUM_COMPOSER_VERSION . --no-dev --stability=$STABILITY_TAG --no-install

  # Install additional Extensions.
  if [[ "$COMPOSER_PACKAGES" != "" ]]; then
    echo -e "$style - installing bundle $BUNDLE_NAME $reset"

    composer require $COMPOSER_PACKAGES --no-interaction --no-update
  fi

  # Make sure prefer-stable is set to true.
  composer config prefer-stable true
  composer config minimum-stability $STABILITY_TAG

  # Run composer install.
  echo -e "$style - running composer install $reset"
  composer install --no-dev

  # Suffix if the bundle is not empty
  if [[ "$BUNDLE_NAME" != "" ]]; then
    BUNDLE_NAME="-${BUNDLE_NAME}"
  else
    BUNDLE_NAME=""
  fi

  # Set file name and destination path.
  FILE_NAME=flarum-$FLARUM_COMPOSER_VERSION$BUNDLE_NAME-php$php
  FILE_DESTINATION=packages/v$FLARUM_COMPOSER_VERSION

  # Before zipping, set the correct permissions.
  find . -type d -exec chmod 755 {} \;
  find . -type f -exec chmod 644 {} \;

  # and the correct ownership.
  chgrp -R www-data .

  # Create installation packages.
  # tar.gz format.
  tar -czf ../$FILE_NAME.tar.gz * > /dev/null
  # zip format.
  zip -r ../$FILE_NAME.zip *

  # Move package to the flarum version folder.
  cd ../
  mkdir -p $FILE_DESTINATION
  mv $FILE_NAME.* $FILE_DESTINATION/

  # Track new packages.
  git add $FILE_DESTINATION/*

  # Delete workspace.
  rm -R $TMP_WORKSPACE
done

# Commit package.
git commit -m "Installation packages for Flarum v$FLARUM_COMPOSER_VERSION" -a
git push

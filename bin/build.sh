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
TMP_WORKSPACE=installation_workspace
echo -e "$style - setting up isolated workspace $reset"
mkdir $TMP_WORKSPACE
cd $TMP_WORKSPACE

# Install Flarum.
echo -e "$style - installing Flarum... $reset"
composer create-project flarum/flarum . --prefer-dist --no-interaction

# Install additional Extensions.
if [[ "$BUNDLE_VALUE" != "default" ]]; then
  echo -e "$style - installing bundle $BUNDLE_NAME $reset"

  COMPOSER_PACKAGES=""

  for p in "$BUNDLE_VALUE"; do
    COMPOSER_PACKAGES="${COMPOSER_PACKAGES} ${p}:*"
  done

  composer require $COMPOSER_PACKAGES --no-interaction
fi

# Set file name and destination path.
FILE_NAME=flarum-$FLARUM_VERSION-$BUNDLE_NAME-php$PHP_VERSION
FILE_DESTINATION=packages/v$FLARUM_VERSION

# Create installation package.
cd ../$TMP_WORKSPACE
# tar.gz format.
tar -czvf $FILE_NAME.tar.gz *
# zip format.
zip -r $FILE_NAME.zip *

# Move package to the flarum version folder.
mkdir -p ../$FILE_DESTINATION
mv $FILE_NAME ../$FILE_DESTINATION/
cd ../

# Delete workspace.
rm -R $TMP_WORKSPACE

# Commit package.
git add $FILE_DESTINATION/*.tar.gz
git commit -m "Installation packages for Flarum v$FLARUM_VERSION" -a
git push
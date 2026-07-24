#!/bin/bash -l

# exit on error.
set -e

# The major line for a version, e.g. "1.8.3" or "2.0.0-rc.1" -> "2.x".
# Used for grouping packages under packages/v<major>/.
get_major_line() {
    local FLARUM_VERSION="$1"

    # Remove the leading 'v' if it exists
    local version=${FLARUM_VERSION#v}

    # Pick the major version number
    IFS='.' read -ra version_parts <<< "$version"
    local major=${version_parts[0]}

    echo "$major.x"
}

# The full version with a single leading 'v', e.g. "v2.0.0-rc.1".
# Used for naming the package files and their directory so each release is
# retained with its exact version.
get_full_version() {
    local FLARUM_VERSION="$1"
    echo "v${FLARUM_VERSION#v}"
}

# get the stability tag from the version number, e.g. "2.0.0-rc.1" -> "rc".
# Empty for stable releases.
get_stability_tag() {
    local FLARUM_VERSION="$1"

    # Define stability tags
    local stabilityTags=("alpha" "beta" "rc" "dev")
    local stability=""

    # Check for stability suffix
    for tag in "${stabilityTags[@]}"; do
        if [[ $FLARUM_VERSION == *"-$tag"* ]]; then
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

# From the tag name (e.g. v1.8.3 or v2.0.0-rc.1) derive:
#  - the major line (2.x) for grouping and the Composer constraint
#  - the full version (v2.0.0-rc.1) for naming the retained packages
#  - the stability tag (rc), passed to Composer via --stability
FLARUM_MAJOR_LINE=$(get_major_line $FLARUM_VERSION)
FLARUM_FULL_VERSION=$(get_full_version $FLARUM_VERSION)
STABILITY_TAG=$(get_stability_tag $FLARUM_VERSION)

# default to stable if empty
if [ -z "$STABILITY_TAG" ]; then
    STABILITY_TAG="stable"
fi

shopt -s dotglob

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
  # Build the constraint from the major line: 2.x -> ^2.0. Stability (e.g. rc)
  # is expressed via --stability, NOT baked into the constraint — `^2.0-rc` is
  # not a valid constraint and fails on some Composer versions.
  FLARUM_COMPOSER_VERSION=${FLARUM_MAJOR_LINE//.x/.0}
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
  BUNDLE_SUFFIX=""
  if [[ "$BUNDLE_NAME" != "" ]]; then
    BUNDLE_SUFFIX="-${BUNDLE_NAME}"
  fi

  # Set file name and destination path. Packages are named with their exact
  # version and grouped by major line, so every release is retained:
  #   packages/v2.x/v2.0.0-rc.1/flarum-v2.0.0-rc.1-no-public-dir-php8.3.zip
  FILE_NAME=flarum-$FLARUM_FULL_VERSION$BUNDLE_SUFFIX-php$php
  FILE_DESTINATION=packages/v$FLARUM_MAJOR_LINE/$FLARUM_FULL_VERSION

  # If the bundle name is `no-public-dir` we will modify the skeleton to remove the public directory.
  if [[ "$BUNDLE_NAME" == "no-public-dir" ]]; then
    # Move everything from the public directory to the root.
    mv public/* .

    # Remove the public directory from the site.php file (__DIR__.'/public' => __DIR__).
    sed -i "s/__DIR__.'\/public'/__DIR__/g" site.php

    # Point the require in index.php to the correct location of site.php (../site.php => ./site.php).
    sed -i 's/\.\.\/site\.php/\.\/site\.php/g' index.php

    # Remove the public directory.
    rm -R public

    # Uncomment protection rules in .htaccess which begin with the line `  # <!-- BEGIN EXPOSED RESOURCES PROTECTION -->`
    # and end with the line `  # <!-- END EXPOSED RESOURCES PROTECTION -->`
    sed -i '/# <!-- BEGIN EXPOSED RESOURCES PROTECTION -->/,/# <!-- END EXPOSED RESOURCES PROTECTION -->/ s/# //' .htaccess
    # now delete the begin and end comments
    sed -i '/<!-- BEGIN EXPOSED RESOURCES PROTECTION -->/d' .htaccess
    sed -i '/<!-- END EXPOSED RESOURCES PROTECTION -->/d' .htaccess

    # Uncomment protection rules in .nginx.conf which begin with the line `# <!-- BEGIN EXPOSED RESOURCES PROTECTION -->`
    # and end with the line `# <!-- END EXPOSED RESOURCES PROTECTION -->`
    sed -i '/# <!-- BEGIN EXPOSED RESOURCES PROTECTION -->/,/# <!-- END EXPOSED RESOURCES PROTECTION -->/ s/# //' .nginx.conf
    # now delete the begin and end comments
    sed -i '/<!-- BEGIN EXPOSED RESOURCES PROTECTION -->/d' .nginx.conf
    sed -i '/<!-- END EXPOSED RESOURCES PROTECTION -->/d' .nginx.conf

    # Set `Disallow sensitive directories` to true in web.config
    sed -i 's/<rule name="Disallow sensitive directories" enabled="false"/<rule name="Disallow sensitive directories" enabled="true"/g' web.config
  fi

  # Before zipping, set the correct permissions.
  chmod -R 755 .

  # Create installation packages.
  # tar.gz format.
  tar -czf ../$FILE_NAME.tar.gz --owner=www-data --group=www-data * > /dev/null
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

BUNDLE_NAME_OR_DEFAULT=$BUNDLE_NAME

if [[ "$BUNDLE_NAME_OR_DEFAULT" == "" ]]; then
  BUNDLE_NAME_OR_DEFAULT="default"
fi

# Commit package.
git commit -m "Installation packages for Flarum $FLARUM_FULL_VERSION ($BUNDLE_NAME_OR_DEFAULT)" -a

# Push while rebasing to avoid conflicts.
git pull --rebase
git push

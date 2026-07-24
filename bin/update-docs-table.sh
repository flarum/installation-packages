#!/bin/bash -l

# Regenerates the "Installing by unpacking an archive" download table in a
# Flarum docs `install.md` so it points at the freshly-built packages for a
# given version.
#
# The table is rebuilt from the package files that actually exist on disk, so
# it always matches what was produced (PHP versions x bundles x formats). Only
# the markdown table block is rewritten; the rest of the file is untouched.
#
# Usage:
#   FLARUM_VERSION=v2.0.0-rc.5 \
#   PACKAGES_DIR=packages/v2.x/v2.0.0-rc.5 \
#   INSTALL_MD=/path/to/docs/install.md \
#   bin/update-docs-table.sh
#
# The version label shown in the first column is the major line (e.g. 2.x).

set -euo pipefail

: "${FLARUM_VERSION:?FLARUM_VERSION is required (e.g. v2.0.0-rc.5)}"
: "${PACKAGES_DIR:?PACKAGES_DIR is required (dir containing the built packages)}"
: "${INSTALL_MD:?INSTALL_MD is required (path to the docs install.md)}"

# Normalise: ensure a single leading 'v'.
full_version="v${FLARUM_VERSION#v}"

# Major line for the first column and the raw URL path, e.g. "2.x".
version_no_v="${full_version#v}"
IFS='.' read -ra parts <<< "$version_no_v"
major_line="${parts[0]}.x"

repo_raw="https://github.com/flarum/installation-packages/raw/main"

# Build the table rows from the files present in PACKAGES_DIR.
# File format: flarum-<full_version>[-no-public-dir]-php<X>.<zip|tar.gz>
rows=""
# Sort for deterministic output.
for file in $(ls "$PACKAGES_DIR" | sort); do
  # Only consider our package archives.
  case "$file" in
    flarum-*.zip|flarum-*.tar.gz) ;;
    *) continue ;;
  esac

  # PHP version: the digits after "-php" up to the extension.
  php=$(echo "$file" | sed -E 's/.*-php([0-9]+\.[0-9]+)\.(zip|tar\.gz)$/\1/')

  # Public path: "No" when the no-public-dir bundle, "Yes" otherwise.
  if [[ "$file" == *"-no-public-dir-"* ]]; then
    public="No"
  else
    public="Yes"
  fi

  # Type from the extension.
  case "$file" in
    *.zip) type="ZIP" ;;
    *.tar.gz) type="TAR.GZ" ;;
  esac

  url="$repo_raw/$PACKAGES_DIR/$file"
  rows+="| $major_line | $php | $public | $type | [$file]($url) |"$'\n'
done

if [ -z "$rows" ]; then
  echo "No package files found in $PACKAGES_DIR" >&2
  exit 1
fi

header="| Flarum Version | PHP Version | Public Path | Type   | Archive |"
divider="|----------------|-------------|-------------|--------|---------|"

# Replace the existing table (header row + divider + all following table rows)
# with the freshly generated one, using awk so surrounding prose is preserved.
tmp=$(mktemp)
TABLE="$header"$'\n'"$divider"$'\n'"$rows" awk '
  # Detect the start of the archive table by its header row.
  /^\| Flarum Version \| PHP Version \|/ && !done {
    print ENVIRON["TABLE"]
    intable = 1
    done = 1
    next
  }
  # While inside the old table, skip its rows (lines starting with "|").
  intable {
    if ($0 ~ /^\|/) next
    intable = 0
  }
  { print }
' "$INSTALL_MD" > "$tmp"

mv "$tmp" "$INSTALL_MD"

echo "Updated $INSTALL_MD table for $major_line ($full_version)"

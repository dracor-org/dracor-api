#!/bin/sh
#
# Build the dracor-api EXPath package (XAR).
#
# Usage:
#   ./build.sh          build build/dracor-v1-<version>.xar
#   ./build.sh clean    remove build artifacts
#
# The version is derived from `git describe` unless set with the VERSION
# environment variable.

set -e

cd "$(dirname "$0")"

name=dracor-v1
build_dir=build
symlink=$name-latest.xar

if [ "$1" = clean ]; then
  rm -rf $build_dir expath-pkg.xml $symlink
  exit
fi

if [ -z "$VERSION" ]; then
  VERSION=$(git describe --tags --always --dirty 2>/dev/null | sed -e 's/^v//')
fi
version=${VERSION:-unknown}
xar=$build_dir/$name-$version.xar

sed -e "s/@package.version@/$version/" expath-pkg.xml.tmpl > expath-pkg.xml

mkdir -p $build_dir
rm -f "$xar"
# keep in sync with the push paths in .github/workflows/deploy.yml
zip -q -r "$xar" \
  repo.xml \
  expath-pkg.xml \
  pre-install.xq \
  post-install.xq \
  controller.xql \
  collection.xconf \
  data.xconf \
  api.yaml \
  openapi-config.xml \
  index.html \
  icon.png \
  tei-to-txt.xsl \
  speakers.xq \
  modules \
  jobs \
  README.md \
  LICENSE

ln -sf "$xar" $symlink

echo "$xar"

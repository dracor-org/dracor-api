#!/bin/sh
#
# Install a dracor-api XAR package into a running eXist-db using its REST
# interface.
#
# Usage:
#   ./deploy.sh <xar> [<exist-url>]
#
# <exist-url> defaults to http://localhost:8080/exist. For a remote server open
# an SSH tunnel to its eXist port first. The credentials are taken from the
# EXIST_USER (default: admin) and EXIST_PASSWORD environment variables.
#
# An installed dracor-api package is removed before installing the new one, so
# the same or an older version can be installed as well.

set -e

xar=$1
url=${2:-http://localhost:8080/exist}
user=${EXIST_USER:-admin}
pkg=http://dracor.org/ns/exist/v1
col=/db/system/deploy

if [ ! -f "$xar" ]; then
  echo "Usage: $0 <xar> [<exist-url>]" >&2
  exit 1
fi

file=$(basename "$xar")
case $file in
  *[!A-Za-z0-9._-]*)
    echo "Unexpected characters in file name: $file" >&2
    exit 1
    ;;
esac

# the installed package is removed before installing the new one, so make sure
# not to replace it with something else
descriptor=$(unzip -p "$xar" expath-pkg.xml 2>/dev/null || true)
if ! printf '%s\n' "$descriptor" | grep -q "name=\"$pkg\""; then
  echo "$xar is not a dracor-api package ($pkg)" >&2
  exit 1
fi
version=$(printf '%s\n' "$descriptor" \
  | sed -n -e 's/^[[:space:]]*version="\([^"]*\)".*/\1/p')

# pass the credentials in a curl config file to keep them off the command line
curlrc=$(mktemp)
chmod 600 "$curlrc"
password=$(printf '%s' "$EXIST_PASSWORD" | sed -e 's/[\\"]/\\&/g')
printf 'user = "%s:%s"\n' "$user" "$password" > "$curlrc"

cleanup() {
  if [ -n "$uploaded" ]; then
    curl -sS -K "$curlrc" -o /dev/null -X DELETE "$url/rest$col/$file" || true
  fi
  rm -f "$curlrc"
}
trap cleanup EXIT

echo "Uploading $file to $url"
curl -fsS -K "$curlrc" -o /dev/null -X PUT \
  -H 'Content-Type: application/expath+xar' \
  --data-binary "@$xar" \
  "$url/rest$col/$file"
uploaded=yes

echo "Installing $file"
sed -e "s|@pkg@|$pkg|g" -e "s|@xar@|$col/$file|g" -e "s|@version@|$version|g" \
  <<'EOF' |
<query xmlns="http://exist.sourceforge.net/NS/exist" wrap="no">
<text><![CDATA[
xquery version "3.1";

declare function local:check ($status as element()) as element() {
  if ($status/@result = "ok") then $status
  else error(xs:QName("local:deploy-failed"), serialize($status))
};

(: remove all installed versions of the package :)
declare function local:remove ($name as xs:string, $attempts as xs:integer) {
  if ($name = repo:list() and $attempts > 0) then (
    repo:undeploy($name),
    repo:remove($name),
    local:remove($name, $attempts - 1)
  ) else if ($name = repo:list()) then
    error(xs:QName("local:deploy-failed"), "Failed to remove " || $name)
  else ()
};

let $name := "@pkg@"
let $status := (
  local:remove($name, 5),
  local:check(repo:install-and-deploy-from-db("@xar@"))
)[last()]
let $deployed := doc($status/@target || "/expath-pkg.xml")/*/@version/string()
return
  if ($deployed = "@version@") then
    "Installed version " || $deployed || " to " || $status/@target
  else error(
    xs:QName("local:deploy-failed"),
    "Expected version @version@ in " || $status/@target || ", found " || $deployed
  )
]]></text>
</query>
EOF
curl -sS --fail-with-body -K "$curlrc" \
  -H 'Content-Type: application/xml' \
  --data-binary @- \
  "$url/rest/db"
echo

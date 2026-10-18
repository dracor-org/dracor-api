#!/bin/bash
#
# Create or delete the throwaway corpus `scratch` with a minimal play, on
# which the admin operations are tested with schemathesis (see
# test/schemathesis_hooks.py).
#
# Usage:
#   test/scratch-corpus.sh create|delete [API_BASE]
#
# API_BASE defaults to the test stack (http://localhost:8081/exist/restxq/v1).
# The credentials are taken from EXIST_USER (default: admin) and
# EXIST_PASSWORD (default: empty).

API_BASE=${2:-http://localhost:8081/exist/restxq/v1}
AUTH="${EXIST_USER:-admin}:${EXIST_PASSWORD:-}"
TEST_DIR=$(cd "$(dirname "$0")" && pwd)

delete() {
  # 404 if it doesn't exist
  curl --silent --output /dev/null -u "$AUTH" -X DELETE \
    "$API_BASE/corpora/scratch"
}

case $1 in
  create)
    # start afresh if a previous run was interrupted before deleting it
    delete
    curl --silent --show-error --fail --output /dev/null -u "$AUTH" \
      -X POST -H 'Content-Type: application/json' \
      -d '{"name": "scratch", "title": "Scratch Corpus"}' \
      "$API_BASE/corpora" &&
    curl --silent --show-error --fail --output /dev/null -u "$AUTH" \
      -X PUT -H 'Content-Type: application/xml' \
      --data-binary "@$TEST_DIR/admin/minimal-play.xml" \
      "$API_BASE/corpora/scratch/plays/minimal/tei"
    ;;
  delete)
    delete
    ;;
  *)
    echo "Usage: $0 create|delete [API_BASE]" >&2
    exit 1
    ;;
esac

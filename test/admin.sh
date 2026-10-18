#!/bin/bash
#
# Run the tests of the admin endpoints (test/admin) against a running DraCor
# API. They create and delete throwaway corpora, so never run them against a
# production API. This should reproduce the admin tests in the GitHub
# workflow. Requires uv.
#
# Usage:
#   test/admin.sh [API_BASE] [PYTEST_ARGS...]
#
# API_BASE defaults to the test stack (http://localhost:8081/exist/restxq/v1).
# The credentials are taken from EXIST_USER (default: admin) and
# EXIST_PASSWORD (default: empty).

API_BASE=http://localhost:8081/exist/restxq/v1
if [ $# -gt 0 ] && [ "${1#-}" = "$1" ]; then
  API_BASE=$1
  shift
fi

TEST_DIR=$(cd "$(dirname "$0")" && pwd)

uvx --with requests pytest "$TEST_DIR/admin" \
  --api-base="$API_BASE" \
  -p no:cacheprovider \
  "$@"

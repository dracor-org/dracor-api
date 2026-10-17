#!/bin/bash
#
# Run the DTS validator (https://github.com/distributed-text-services/validator)
# and the DraCor DTS contract tests (test/dts) against a running DraCor API.
# This should reproduce the DTS tests in the GitHub workflow.
#
# Usage:
#   test/dts-validator.sh [ENTRY_ENDPOINT] [PYTEST_ARGS...]
#
# ENTRY_ENDPOINT defaults to the entry point of the test stack
# (http://localhost:8081/exist/restxq/v1/dts). Additional arguments are passed
# to the contract tests. These test the `test` corpus by default; use
# `--corpus NAME` (repeatable) to test other corpora, or `--all-corpora`.
#
# Environment variables:
#   DTS_VALIDATOR_DIR  where to keep the validator checkout and virtualenv
#                      (default: test/.dts-validator)
#   DTS_REPORT_DIR     where to write the reports (default: dts-reports)
#   DTS_SKIP_VALIDATOR set to 1 to run only the contract tests
#   DTS_SKIP_CONTRACT  set to 1 to run only the validator

set -u

ENTRY_ENDPOINT=${1:-http://localhost:8081/exist/restxq/v1/dts}
shift || true

# the validator release to test against
VALIDATOR_REPO=https://github.com/distributed-text-services/validator.git
VALIDATOR_REF=v0.2.3

TEST_DIR=$(cd "$(dirname "$0")" && pwd)
WORK_DIR=${DTS_VALIDATOR_DIR:-$TEST_DIR/.dts-validator}
REPORT_DIR=${DTS_REPORT_DIR:-dts-reports}
SRC_DIR=$WORK_DIR/src
VENV_DIR=$WORK_DIR/venv

if ! curl --silent --fail --output /dev/null --max-time 30 "$ENTRY_ENDPOINT"; then
  echo "No DTS API responding at $ENTRY_ENDPOINT" >&2
  echo "Start the test stack with" >&2
  echo "  COMPOSE_FILE=compose.yml:compose.t.yml docker compose up --build --wait" >&2
  echo "or pass the entry endpoint of a running API, e.g." >&2
  echo "  $0 http://localhost:8088/api/v1/dts" >&2
  exit 1
fi

mkdir -p "$WORK_DIR" "$REPORT_DIR"

if [ ! -d "$SRC_DIR/.git" ]; then
  git clone --quiet "$VALIDATOR_REPO" "$SRC_DIR" || exit 1
fi
git -C "$SRC_DIR" fetch --quiet --tags
git -C "$SRC_DIR" checkout --quiet "$VALIDATOR_REF" || exit 1

if [ ! -x "$VENV_DIR/bin/python" ]; then
  python3 -m venv "$VENV_DIR" || exit 1
fi
# The validator loads its JSON schemas relative to the source checkout, so it
# must be installed in editable mode.
"$VENV_DIR/bin/pip" install --quiet --upgrade pip
"$VENV_DIR/bin/pip" install --quiet -e "$SRC_DIR" || exit 1

status=0

if [ "${DTS_SKIP_VALIDATOR:-0}" != 1 ]; then
  echo "Running DTS validator $VALIDATOR_REF against $ENTRY_ENDPOINT"
  "$VENV_DIR/bin/dts-validator" "$SRC_DIR/tests" \
    --entry-endpoint="$ENTRY_ENDPOINT" \
    --html="$REPORT_DIR/dts-validator.html" --self-contained-html \
    --junitxml="$REPORT_DIR/dts-validator.xml" \
    -p no:cacheprovider \
    || status=1
fi

if [ "${DTS_SKIP_CONTRACT:-0}" != 1 ]; then
  echo "Running DraCor DTS contract tests against $ENTRY_ENDPOINT"
  "$VENV_DIR/bin/python" -m pytest "$TEST_DIR/dts" \
    --entry-endpoint="$ENTRY_ENDPOINT" \
    --html="$REPORT_DIR/dts-contract.html" --self-contained-html \
    --junitxml="$REPORT_DIR/dts-contract.xml" \
    -p no:cacheprovider \
    "$@" \
    || status=1
fi

exit $status

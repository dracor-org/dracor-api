# This should reproduce the tests in the GitHub workflow. Settings and test
# data shared by both are in schemathesis.toml. Requires uv.

# keep in sync with the version in .github/workflows/schemathesis.yml
version=4.31.1
schema=http://localhost:8081/exist/restxq/v1/openapi.yaml

# the option the action always passes
st() {
  uvx --from "schemathesis==$version" schemathesis run $schema \
    --generation-database=:memory: "$@"
}

# The admin operations only change the throwaway corpus (see
# test/schemathesis_hooks.py), which is removed before the other runs.
"$(dirname "$0")/scratch-corpus.sh" create || exit 1
SCHEMATHESIS_HOOKS="$(dirname "$0")/schemathesis_hooks.py" st \
  --exclude-tag webhook \
  --auth admin: \
  --report junit \
  --report-junit-path schemathesis-results.xml
status=$?
"$(dirname "$0")/scratch-corpus.sh" delete

# Invalid data, which must be rejected. The links followed by the stateful
# phase only lead to valid requests, which the first run covers.
st --include-method GET \
  --mode negative \
  --phases examples,coverage,fuzzing \
  --auth admin: \
  --report junit \
  --report-junit-path schemathesis-results-negative.xml || status=1

exit $status

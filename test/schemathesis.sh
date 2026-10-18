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

st --include-method GET \
  --auth admin: \
  --report junit \
  --report-junit-path schemathesis-results.xml
status=$?

# Invalid data, which must be rejected. The links followed by the stateful
# phase only lead to valid requests, which the first run covers.
st --include-method GET \
  --mode negative \
  --phases examples,coverage,fuzzing \
  --auth admin: \
  --report junit \
  --report-junit-path schemathesis-results-negative.xml || status=1

# Admin operations with credentials, on a throwaway corpus only (see
# test/schemathesis_hooks.py). There are no links between them.
"$(dirname "$0")/scratch-corpus.sh" create || status=1
SCHEMATHESIS_HOOKS="$(dirname "$0")/schemathesis_hooks.py" st \
  --include-tag admin \
  --phases examples,coverage,fuzzing \
  --auth admin: \
  --report junit \
  --report-junit-path schemathesis-results-admin.xml || status=1
"$(dirname "$0")/scratch-corpus.sh" delete

exit $status

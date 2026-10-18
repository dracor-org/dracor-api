# This should reproduce the tests in the GitHub workflow. Settings and test
# data shared by both are in schemathesis.toml. Requires uv.

# keep in sync with the version in .github/workflows/schemathesis.yml
version=4.31.1
schema=http://localhost:8081/exist/restxq/v1/openapi.yaml

# the options the action always passes
st() {
  uvx --from "schemathesis==$version" schemathesis run $schema \
    --generation-database=:memory: --max-examples=50 --checks=all "$@"
}

st --include-method GET \
  --auth admin: \
  --report junit \
  --report-junit-path schemathesis-results.xml
status=$?

# Admin operations without credentials, they must all be rejected
st --include-tag admin \
  --phases examples,coverage,fuzzing \
  --report junit \
  --report-junit-path schemathesis-results-admin.xml || status=1

# Invalid data, which must be rejected
st --include-method GET \
  --mode negative \
  --exclude-checks unsupported_method \
  --auth admin: \
  --report junit \
  --report-junit-path schemathesis-results-negative.xml || status=1

exit $status

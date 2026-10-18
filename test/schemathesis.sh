# This should reproduce the test in the GitHub workflow. Settings and test
# data shared by both are in schemathesis.toml.

schema=http://localhost:8081/exist/restxq/v1/openapi.yaml

schemathesis run $schema \
  --include-method GET \
  --auth admin: \
  --report junit \
  --report-junit-path schemathesis-results.xml
status=$?

# Admin operations without credentials, they must all be rejected
schemathesis run $schema \
  --include-tag admin \
  --phases examples,coverage,fuzzing \
  --report junit \
  --report-junit-path schemathesis-results-admin.xml || status=1

# Invalid data (not failing the script yet, see schemathesis.toml). The
# excluded operations only have the corpus name, for which no invalid value
# can be generated.
schemathesis run $schema \
  --include-method GET \
  --mode negative \
  --exclude-operation-id list-corpus-content \
  --exclude-operation-id corpus-metadata \
  --exclude-operation-id corpus-metadata-csv-endpoint \
  --suppress-health-check filter_too_much \
  --auth admin: \
  --report junit \
  --report-junit-path schemathesis-results-negative.xml

exit $status

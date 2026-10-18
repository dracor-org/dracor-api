# This should reproduce the test in the GitHub workflow. Settings and test
# data shared by both are in schemathesis.toml.

schemathesis run http://localhost:8081/exist/restxq/v1/openapi.yaml \
  --include-method GET \
  --auth admin: \
  --report junit \
  --report-junit-path schemathesis-results.xml

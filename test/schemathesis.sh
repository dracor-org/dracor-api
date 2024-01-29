# This should reproduce the test in the GitHub workflow.

schemathesis run http://localhost:8081/exist/restxq/v1/openapi.yaml \
  --exclude-checks status_code_conformance \
  --report \
  --hypothesis-max-examples 50 \
  --auth admin: \
  --method GET

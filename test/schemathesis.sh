# This should reproduce the test in the GitHub workflow.

schemathesis run http://localhost:8081/exist/restxq/v1/openapi.yaml \
  --include-method GET \
  --max-examples 50 \
  --auth admin:

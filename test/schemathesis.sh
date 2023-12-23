# This should reproduce the test in the GitHub workflow.

schemathesis run http://localhost:8088/api/v1/openapi.yaml \
  --checks not_a_server_error \
  --report \
  --hypothesis-max-examples 50 \
  --auth admin: \
  --method GET
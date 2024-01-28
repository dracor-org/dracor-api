# This should reproduce the test in the GitHub workflow.

schemathesis run http://localhost:8081/exist/restxq/v1/openapi.yaml \
  --checks not_a_server_error,content_type_conformance,response_headers_conformance,response_schema_conformance \
  --report \
  --hypothesis-max-examples 50 \
  --auth admin: \
  --method GET

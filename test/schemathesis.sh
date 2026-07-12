# This should reproduce the test in the GitHub workflow.

schemathesis run http://localhost:8081/exist/restxq/v1/openapi.yaml \
  --include-method GET \
  --exclude-tag DTS \
  --exclude-operation-id wikidata-author-info \
  --mode positive \
  --max-examples 50 \
  --request-timeout 30 \
  --auth admin: \
  --report junit \
  --report-junit-path schemathesis-results.xml

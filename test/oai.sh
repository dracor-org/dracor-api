#!/bin/bash
#
# Smoke tests for the OAI-PMH endpoint against a running DraCor API. The
# tests are read-only, so they can also be run against staging or production.
# At least one corpus must be loaded. Requires curl and xmllint.
#
# Usage:
#   test/oai.sh [API_BASE]
#
# API_BASE defaults to the dev stack (http://localhost:8088/api/v1).

API_BASE=${1:-http://localhost:8088/api/v1}
OAI="$API_BASE/oai"
failures=0
tests=0

# check DESCRIPTION QUERY EXPECTED_XPATH [METHOD]
#   QUERY is the query string (or form body for POST); the response must be
#   well-formed and EXPECTED_XPATH must select something (evaluated with the
#   default OAI namespace removed).
check() {
  local desc=$1 query=$2 expr=$3 method=${4:-GET}
  local body
  tests=$((tests + 1))
  if [ "$method" = POST ]; then
    body=$(curl -s -X POST -H 'Content-Type: application/x-www-form-urlencoded' \
      --data "$query" "$OAI")
  else
    body=$(curl -s "$OAI?$query")
  fi
  if ! echo "$body" | xmllint --noout - 2>/dev/null; then
    echo "FAIL $desc: response is not well-formed XML"
    failures=$((failures + 1))
    return
  fi
  local result
  result=$(echo "$body" \
    | sed 's/ xmlns="http:\/\/www.openarchives.org\/OAI\/2.0\/"//' \
    | xmllint --xpath "$expr" - 2>/dev/null)
  if [ -n "$result" ]; then
    echo "ok   $desc"
  else
    echo "FAIL $desc: no match for $expr"
    failures=$((failures + 1))
  fi
}

identifier=$(curl -s "$OAI?verb=ListIdentifiers&metadataPrefix=oai_dc" \
  | sed 's/ xmlns="http:\/\/www.openarchives.org\/OAI\/2.0\/"//' \
  | xmllint --xpath 'string(//header[1]/identifier)' - 2>/dev/null)

if [ -z "$identifier" ]; then
  echo "No records found at $OAI (is a corpus loaded?)"
  exit 1
fi
echo "Using identifier $identifier"

check "Identify" "verb=Identify" \
  "/OAI-PMH/Identify[protocolVersion='2.0' and deletedRecord and granularity='YYYY-MM-DDThh:mm:ssZ']"
check "Identify (POST)" "verb=Identify" "/OAI-PMH/Identify" POST
check "ListMetadataFormats" "verb=ListMetadataFormats" \
  "/OAI-PMH/ListMetadataFormats[metadataFormat/metadataPrefix='oai_dc' and metadataFormat/metadataPrefix='cmdi']"
check "ListMetadataFormats for identifier" \
  "verb=ListMetadataFormats&identifier=$identifier" \
  "/OAI-PMH/ListMetadataFormats/metadataFormat"
check "ListSets" "verb=ListSets" "/OAI-PMH/error[@code='noSetHierarchy']"
check "ListIdentifiers" "verb=ListIdentifiers&metadataPrefix=oai_dc" \
  "/OAI-PMH/ListIdentifiers/header/datestamp"
check "ListRecords oai_dc" "verb=ListRecords&metadataPrefix=oai_dc" \
  "/OAI-PMH/ListRecords/record/metadata/*[local-name()='dc']"
check "ListRecords cmdi" "verb=ListRecords&metadataPrefix=cmdi" \
  "/OAI-PMH/ListRecords/record/metadata/*[local-name()='CMD']"
check "GetRecord oai_dc" \
  "verb=GetRecord&metadataPrefix=oai_dc&identifier=$identifier" \
  "/OAI-PMH/GetRecord/record[header/identifier='$identifier']"
check "GetRecord cmdi" \
  "verb=GetRecord&metadataPrefix=cmdi&identifier=$identifier" \
  "/OAI-PMH/GetRecord/record/metadata/*[local-name()='CMD']"
check "GetRecord (POST)" \
  "verb=GetRecord&metadataPrefix=oai_dc&identifier=$identifier" \
  "/OAI-PMH/GetRecord/record" POST
check "from/until including all" \
  "verb=ListIdentifiers&metadataPrefix=oai_dc&from=2000-01-01&until=2999-12-31" \
  "/OAI-PMH/ListIdentifiers/header"
check "from in the future" \
  "verb=ListIdentifiers&metadataPrefix=oai_dc&from=2999-01-01T00:00:00Z" \
  "/OAI-PMH/error[@code='noRecordsMatch']"

# errors
check "missing verb" "" "/OAI-PMH/error[@code='badVerb']"
check "illegal verb" "verb=Foo" "/OAI-PMH/error[@code='badVerb']"
check "repeated verb" "verb=Identify&verb=Identify" \
  "/OAI-PMH/error[@code='badArgument']"
check "illegal argument" "verb=Identify&identifier=x" \
  "/OAI-PMH/error[@code='badArgument']"
check "missing metadataPrefix" "verb=ListRecords" \
  "/OAI-PMH/error[@code='badArgument']"
check "unknown metadataPrefix" "verb=ListRecords&metadataPrefix=foo" \
  "/OAI-PMH/error[@code='cannotDisseminateFormat']"
check "invalid date" "verb=ListRecords&metadataPrefix=oai_dc&from=2020-13-01" \
  "/OAI-PMH/error[@code='badArgument']"
check "mixed granularity" \
  "verb=ListRecords&metadataPrefix=oai_dc&from=2020-01-01&until=2021-01-01T00:00:00Z" \
  "/OAI-PMH/error[@code='badArgument']"
check "set" "verb=ListRecords&metadataPrefix=oai_dc&set=foo" \
  "/OAI-PMH/error[@code='noSetHierarchy']"
check "resumptionToken" "verb=ListRecords&resumptionToken=foo" \
  "/OAI-PMH/error[@code='badResumptionToken']"
check "unknown identifier" \
  "verb=GetRecord&metadataPrefix=oai_dc&identifier=oai:example.org:foo" \
  "/OAI-PMH/error[@code='idDoesNotExist']"
check "GetRecord without identifier" "verb=GetRecord&metadataPrefix=oai_dc" \
  "/OAI-PMH/error[@code='badArgument']"
check "error response has no request attributes" "verb=Foo" \
  "/OAI-PMH/request[not(@*)]"

echo
echo "$((tests - failures))/$tests passed"
[ $failures -eq 0 ]

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

DraCor API is an [eXist-db](http://exist-db.org/) application providing a REST API for the [Drama Corpora Project](https://dracor.org). The backend is written entirely in **XQuery 3.1**, served via **RESTXQ** annotations within eXist-db 6.4.0.

## Commands

### Build

```sh
ant          # Build XAR (EXPath package) for deployment to eXist-db
ant clean    # Clean build artifacts
```

### Development (Docker)

```sh
docker compose up                    # Start full stack (API, frontend, metrics, Fuseki)
EXIST_PASSWORD=mysecret docker compose up   # With explicit admin password
EXIST_PASSWORD= docker compose up    # Empty password for local dev
```

API available at `http://localhost:8088/api/v1/`. eXist-db dashboard at `http://localhost:8080/`.

### Load Data

```sh
# Add a corpus (provide corpus.xml from a DraCor corpus repo)
curl -X POST -u admin: -d@corpus.xml -H 'Content-type: text/xml' http://localhost:8088/api/v1/corpora

# Load TEI files for a corpus
curl -X POST -u admin: -H 'Content-type: application/json' -d '{"load":true}' http://localhost:8088/api/v1/corpora/test
```

### Testing

```sh
./test/schemathesis.sh   # OpenAPI schema-based API tests (requires running stack)
./test/webhook.sh        # Test GitHub webhook integration
```

CI runs schemathesis against a Docker Compose test stack (see [.github/workflows/test_api.yml](.github/workflows/test_api.yml)).

### Formatting

```sh
prettier --write "**/*.xq"   # Format XQuery files (requires node_modules)
yamllint .                   # Lint YAML files
```

### VS Code Integration

```sh
cp .existdb.json.tmpl .existdb.json   # Configure eXist-db VS Code extension
```

The extension syncs the working directory to `/db/apps/dracor-v1` in a running eXist instance.

## Architecture

### Technology Stack

- **XQuery 3.1** — all server-side logic
- **RESTXQ** — REST endpoint declarations via XQuery function annotations (`%rest:GET`, `%rest:path`, etc.)
- **eXist-db 6.4.0** — XML database and application server
- **TEI XML** — data format for dramatic texts
- **OpenAPI 3.0** — API specification in [api.yaml](api.yaml)

### Modules (`modules/`)

| File | Role |
|------|------|
| `api.xqm` | All REST API endpoints (`/v1/...`) |
| `dts.xqm` | Distributed Text Services (DTS) API (`/v1/dts`) |
| `util.xqm` | Shared utilities: text extraction, network metrics, data transformation |
| `config.xqm` | Configuration management (reads from `/db/dracor/config-v1.xml`) |
| `rdf.xqm` | RDF/linked data generation |
| `metrics.xqm` | Character network metrics computation |
| `webhook.xqm` | GitHub webhook handler with HMAC-SHA-1 validation |
| `load.xqm` | Corpus loading logic |
| `github.xqm` | GitHub API calls |
| `wikidata.xqm` | Wikidata API integration |
| `trigger.xqm` | Job scheduling |

### Background Jobs (`jobs/`)

Async jobs scheduled via eXist's job scheduler:
- `load-corpus.xq` — fetches TEI files from GitHub and loads them into the database
- `process-webhook-delivery.xq` — processes queued GitHub webhook deliveries
- `sitelinks.xq` — syncs Wikidata sitelinks

### Database Layout

```
/db/apps/dracor-v1/        Application files (XQuery modules, resources)
/db/dracor/                Data root
/db/dracor/corpora/        TEI documents organized by corpus/play
/db/dracor/webhook/        Queued webhook delivery records
/db/dracor/config-v1.xml   Runtime configuration
/db/dracor/secrets.xml     Webhook + Fuseki secrets
```

### GitHub Webhook Flow

```
GitHub push → POST /webhook/github
  → webhook.xqm: HMAC-SHA-1 validation
  → Store delivery in /db/dracor/webhook/
  → Schedule async job: process-webhook-delivery.xq
  → Fetch updated TEI files from GitHub
  → Update documents in /db/dracor/corpora/
```

### External Integrations

- **Wikidata** — author/play metadata enrichment via SPARQL
- **Fuseki** — RDF triple store (configured via `FUSEKI_SERVER` env var)
- **dracor-metrics service** — separate service for network metrics (configured via `METRICS_SERVER` env var)

### Key Environment Variables

| Variable | Purpose |
|----------|---------|
| `EXIST_PASSWORD` | eXist-db admin password |
| `DRACOR_API_BASE` | Public API base URL |
| `FUSEKI_SERVER` | Fuseki triple store URI |
| `FUSEKI_SECRET` | Fuseki admin password |
| `METRICS_SERVER` | Metrics service URI |
| `GITHUB_WEBHOOK_SECRET` | GitHub webhook shared secret |

### Build & Deployment

- `ant` produces a `.xar` EXPath package deployable to any eXist-db instance
- `Dockerfile` is a multi-stage build: Ant builds the XAR, then it's installed into an eXist-db image
- `compose.yml` — production-like orchestration (API + frontend + metrics + Fuseki)
- `compose.t.yml` — overlay for CI test runs
- `compose.dev.yml` — development overlay (builds locally; uses hardcoded dev secrets `qwerty`)
- eXist-db dependencies (`expath-crypto-module`, `openapi`, `functx`) are auto-deployed via `/opt/exist/autodeploy`
- `post-install.xq` runs after XAR deployment: creates `/db/dracor/config-v1.xml` and `secrets.xml` from environment variables, and sets SETUID permissions on webhook and sitelinks modules

### XQuery Coding Patterns

**RESTXQ endpoint return shape**: Endpoints returning 200 with no custom headers can return the response body directly (JSON map/array or XML). A leading `<rest:response><http:response status="NNN"/></rest:response>` is only needed when setting a non-200 status code or emitting custom headers.

**JSON output**: Endpoints returning JSON require the `%output:method("json")` function annotation. XQuery 3.1 map/array constructors serialize directly — no `serialize()` call needed.

**Error handling**: Modules raise typed errors using `error(QName, message)` with namespace-qualified codes (e.g., `$dutil:invalid-corpus-document`). Callers catch specific codes via `catch $dutil:invalid-corpus-document { ... }` before a wildcard `catch * { ... }` fallback.

**Logging**: Use `util:log("info", $message)` for application logs (written to eXist log files) and `util:log-system-out($message)` for container stdout (visible in `docker compose logs`).

**OpenAPI spec**: `api.yaml` is the static source; when served at `/v1/openapi.yaml`, `api.xqm` dynamically replaces hardcoded server URLs with `$config:api-base` and injects the current package version.

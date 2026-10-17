# DraCor API

This is the [eXistdb](http://exist-db.org/) application providing the API for
https://dracor.org.

The API Documentation is available at https://dracor.org/doc/api/.

## Getting Started

```sh
git clone https://github.com/dracor-org/dracor-api.git
cd dracor-api
docker compose up
# load data, see below
```

We provide a [compose.yml](compose.yml) that allows to run an
eXist database with `dracor-api` locally, together with the supporting
[dracor-metrics service](https://github.com/dracor-org/dracor-metrics) and a
triple store. With [Docker installed](https://docs.docker.com/get-docker/)
simply run:

```sh
docker compose up
```

This pulls the necessary images from Docker Hub and starts the respective
containers. The **eXist database** will become available under
http://localhost:8080/. To check that the DraCor API is up run

```sh
curl http://localhost:8088/api/v1/info
```

By default, when you run `docker compose up` for the first time, a password for
the admin user of the eXist database is generated and printed to the console. If
you instead want to use a specific password use the `EXIST_PASSWORD` environment
variable like this:

```sh
EXIST_PASSWORD=mysecret docker compose up
```

To use the database with an empty password, e.g. on a local machine, run:

```sh
EXIST_PASSWORD= docker compose up
```

The docker-compose setup also includes a
[DraCor frontend](https://github.com/dracor-org/dracor-frontend) connected to
the local eXist instance. It can be accessed by opening http://localhost:8088/
in a browser.

### Load Data

To load corpus data into the database use the DraCor API calls. First [add a
corpus](https://dracor.org/doc/api/#operations-admin-post-corpora):

```sh
curl https://raw.githubusercontent.com/dracor-org/testdracor/main/corpus.xml | \
curl -X POST \
  -u admin: \
  -d@- \
  -H 'Content-type: text/xml' \
  http://localhost:8088/api/v1/corpora
```

Then
[load the TEI files](https://dracor.org/doc/api/#operations-admin-load-corpus)
for the newly added corpus (in this case `test`):

```sh
curl -X POST \
  -u admin: \
  -H 'Content-type: application/json' \
  -d '{"load":true}' \
  http://localhost:8088/api/v1/corpora/test
```

This may take a while. Eventually the added plays can be listed with

```sh
curl http://localhost:8088/api/v1/corpora/test
```

With [jq](https://stedolan.github.io/jq/) installed you can pretty print the
JSON output like this:

```sh
curl http://localhost:8088/api/v1/corpora/test | jq
```

## Test Setup

For running the schemathesis test suite (see [test/schemathesis.sh](test/schemathesis.sh))
or for iterating on the code with a small, reproducible dataset, use the test
compose overlay [compose.t.yml](compose.t.yml). Unlike the default setup, this
one builds the API image locally from the current working tree and
automatically loads the test corpus.

```sh
COMPOSE_FILE=compose.yml:compose.t.yml docker compose up --build --wait
```

- `--build` forces a rebuild of the API image from the current sources.
- `--wait` blocks until the `loadtest` service has finished registering and
  loading the [testdracor](https://github.com/dracor-org/testdracor) corpus,
  so the stack is only reported ready once test data is available.

In this setup the API is served on port **8081** (not 8088):

```sh
curl http://localhost:8081/exist/restxq/v1/info
curl http://localhost:8081/exist/restxq/v1/corpora/test
```

Once the stack is up you can run the schemathesis suite locally:

```sh
./test/schemathesis.sh
```

The DTS endpoints are additionally tested with the
[DTS validator](https://github.com/distributed-text-services/validator) and
with DraCor's own DTS contract tests in [test/dts](test/dts), which check rules
of the DTS 1.0 specification the validator does not cover. Both need Python
3.10 or newer; the script installs the validator into `test/.dts-validator`
and writes HTML and JUnit reports to `dts-reports/`:

```sh
./test/dts-validator.sh
# or against another DTS API; the contract tests check the `test` corpus
# unless other corpora are given with --corpus (or --all-corpora)
./test/dts-validator.sh http://localhost:8088/api/v1/dts --corpus bash
```

A deployed API (staging by default) can be validated with the manually
triggered [DTS Validator](.github/workflows/dts-validator.yml) workflow.

### Reset from scratch

The API image built by the test overlay is tagged `dracor/api-test` and may
persist across runs, along with the eXist-db data volume. To start over with a
freshly compiled image and an empty database:

```sh
COMPOSE_FILE=compose.yml:compose.t.yml docker compose down --volumes --rmi local
COMPOSE_FILE=compose.yml:compose.t.yml docker compose up --build --wait
```

- `--volumes` deletes the named volumes (including the eXist-db data volume).
- `--rmi local` removes the locally built `dracor/api-test` image so the next
  `up` recompiles it from scratch.

## Linting the OpenAPI Document

Changes to [api.yaml](api.yaml) are checked with
[Redocly CLI](https://redocly.com/docs/cli/) in CI (see
[lint-openapi.yml](.github/workflows/lint-openapi.yml)). The rules are
configured in [redocly.yaml](redocly.yaml). To run the linter locally:

```sh
npx @redocly/cli lint api.yaml
```

## VS Code Integration

For the [Visual Studio Code](https://code.visualstudio.com) editor an [eXist-db
extension](https://marketplace.visualstudio.com/items?itemName=eXist-db.existdb-vscode)
is available that allows syncing a local working directory with an eXist
database thus enabling comfortable development of XQuery code.

We provide a [configuration template](.existdb.json.tmpl) to connect your
`dracor-api` working copy to the `dracor-v1` workspace in a local eXist database
(e.g. the one started with `docker compose up`).

After installing the VS Code extension copy the template to create an
`.existdb.json` configuration file:

```sh
cp .existdb.json.tmpl .existdb.json
```

Adjust the settings if necessary and restart VS Code. You should now be able to
start the synchronization from a button in the status bar at the bottom of the
editor window.

## XAR Package

To build a `dracor-api` XAR [EXPath](http://expath.org/spec/pkg) package that
can be installed via the dashboard of any eXist DB instance you can just run:

```sh
./build.sh
```

The package is written to the `build` directory. It only requires `git`, `sed`
and `zip`.

## Deployment

The `deploy.sh` script installs a XAR package into a running eXist DB using its
REST interface, replacing any installed version of `dracor-api`. The corpus data
remains untouched. To deploy to a local instance:

```sh
EXIST_PASSWORD= ./deploy.sh build/dracor-v1-latest.xar
```

For a remote server open an SSH tunnel to its eXist port first and pass the
tunnel URL:

```sh
ssh -N -L 8888:localhost:8080 user@dev.dracor.org &
EXIST_PASSWORD=secret ./deploy.sh build/dracor-v1-latest.xar http://localhost:8888/exist
```

The [Deploy](.github/workflows/deploy.yml) GitHub workflow does the same for the
DraCor servers:

| Environment  | Deployed when                              |
| ------------ | ------------------------------------------ |
| `dev`        | run manually from the Actions tab          |
| `staging`    | pushed to `main`                           |
| `production` | a release is published (not a pre-release) |

The SSH connection uses the deploy key and user shared across the dracor-org
repositories (the organization secrets `DRACOR_ORG_DEPLOY_KEY` and
`DRACOR_ORG_DEPLOY_USER`). Everything specific to a server is configured in a
[GitHub environment](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments)
of the same name:

| Name                 | Type     | Description                                          |
| -------------------- | -------- | ---------------------------------------------------- |
| `EXIST_PASSWORD`     | secret   | eXist DB password                                    |
| `EXIST_USER`         | secret   | eXist DB user (optional, default `admin`)            |
| `DEPLOY_HOST`        | variable | server host name, e.g. `dev.dracor.org`              |
| `DEPLOY_KNOWN_HOSTS` | variable | the server's SSH host key(s) in `known_hosts` format |
| `EXIST_PORT`         | variable | eXist port on the server (default `8080`)            |

They can be set in the repository settings under _Environments_ or with the
GitHub CLI, e.g.:

```sh
gh api -X PUT repos/dracor-org/dracor-api/environments/staging # create it
gh secret set EXIST_PASSWORD --env staging
gh variable set DEPLOY_HOST --env staging --body staging.dracor.org
gh variable set DEPLOY_KNOWN_HOSTS --env staging \
  --body "$(ssh-keygen -F staging.dracor.org | grep -v "^#")"
```

## Webhook

The DraCor API provides a webhook (`/webhook/github`) that can trigger an update
of the corpus data when the configured GitHub repository for the corpus changes.

_Note:_ For the webhook to work, the shared secret between DraCor and GitHub
needs to be configured at `/db/data/dracor/secrets.xml` in the database.

## How to Contribute

See our [CONTRIBUTING](CONTRIBUTING.md) document. For ways to get in touch with
the team see https://dracor.org/doc/get-in-touch.

## License

dracor-api is [MIT licensed](./LICENSE).

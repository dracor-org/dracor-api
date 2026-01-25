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
can be installed via the dashboard of any eXist DB instance you can just run
`ant`.

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

# DraCor API

This is the [eXistdb](http://exist-db.org/) application providing the API for
https://dracor.org.

The API Documentation is available at https://dracor.org/doc/api/.

## Getting Started

```sh
git clone https://github.com/dracor-org/dracor-api.git
cd dracor-api
docker-compose up
# load data, see below
```

We provide a [docker-compose.yml](docker-compose.yml) that allows to run an
eXist database with `dracor-api` locally, together with the supporting
[dracor-metrics service](https://github.com/dracor-org/dracor-metrics) and a
triple store. With [Docker installed](https://docs.docker.com/get-docker/)
simply run:

```sh
docker-compose up
```

This builds the necessary images and starts the respective docker containers.
The eXist database will become available under http://localhost:8080/. To check
that the DraCor API is up run

```sh
curl http://localhost:8080/exist/restxq/info
```

### Load Data

To load corpus data into the database use the DraCor API calls. First [add a
corpus](https://dracor.org/doc/api/#operations-admin-post-corpora):

```sh
curl https://raw.githubusercontent.com/dracor-org/testdracor/main/corpus.xml | \
curl -X POST \
  -u admin: \
  -d@- \
  -H 'Content-type: text/xml' \
  http://localhost:8080/exist/restxq/corpora
```

Then
[load the TEI files](https://dracor.org/doc/api/#operations-admin-load-corpus)
for the newly added corpus (in this case `test`):

```sh
curl -X POST \
  -u admin: \
  -H 'Content-type: application/json' \
  -d '{"load":true}' \
  http://localhost:8080/exist/restxq/corpora/test
```

This may take a while. Eventually the added plays can be listed with

```sh
curl http://localhost:8080/exist/restxq/corpora/test
```

With [jq](https://stedolan.github.io/jq/) installed you can pretty print the
JSON output like this:

```sh
curl http://localhost:8080/exist/restxq/corpora/test | jq
```

## `ant` Workflow

If you prefer to run the eXist database directly without docker you can still
use the old [`ant` based workflow](README-ant.md). However you will have to
provision the metrics service and the triple store by yourself, which is why we
recommend using docker compose instead.

## Atom Integration

For the [Atom editor](https://atom.io) an [existdb
package](https://atom.io/packages/existdb) is available that allows syncing
changes made in the local git repo to the `dracor-api` application stored in
eXist.

After installing the package run the following command to create a
`.existdb.json` configuration file that connects your working directory to the
database:

```sh
sed 's/@jetty.http.port@/8080/' < .existdb.json.tmpl > .existdb.json
```

Then restart Atom.

## XAR Package

To build a `dracor-api` XAR [EXPath](http://expath.org/spec/pkg) package that
can be installed via the dashboard of any eXist DB instance you can just run
`ant`.

## Webhook

The DraCor API provides a webhook (`/webhook/github`) that can trigger an update
of the corpus data when the configured GitHub repository for the corpus changes.

*Note:* For the webhook to work, the shared secret between DraCor and GitHub
needs to be configured at `/db/data/dracor/config.xml` in the database.

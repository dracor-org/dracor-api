# dracor-api

The [eXistdb](http://exist-db.org/) application providing the API for
https://dracor.org.

API Documentation is available at [/documentation/api/](https://dracor.org/documentation/api/).

## tl;dr

Use `ant` to build a xar package or `ant devel` to set up a development
environment.

## Requirements

- ant
- bash
- (node)

For the calculation of network statistics *dracor-api* depends on the external
[dracor-metrics](https://github.com/dracor-org/dracor-metrics) service. To
(install and) run this service with `ant devel` [Node.js](https://nodejs.org)
(and `npm`) needs to be available.

## Build

This software uses `ant` to build its artifacts. While several targets are
exposed, the following ones are considered to be useful:

- `xar` (default)
- `devel`
- `devel.startup`
- `devel.shutdown`
- `load.corpus`
- `clean`

**Note:** Path and file names mentioned here refer to the default settings in
[build.properties](build.properties). Those can be overwritten in a private
`local.build.properties` file.

### xar

Creates an [EXPath](http://expath.org/spec/pkg) package in the `build`
directory.

### devel

Sets up a development environment inside the `devel` directory. If this
directory is present, the process will fail. Please remove it yourself.

This target will do the following in this order:

- xar, see above
- download and extract a specified version of eXist-db
- download all dependencies and place them in the `autodeploy` directory
- set the http and https port of this instance (see
  [build.properties](build.properties))
- start the database once to install all dependencies
  - this step is required to set up the sparql package as it requires a change
    in the configuration file of eXist to be made after the installation
  - the database will shut down immediately
- look for a running instance of the
  [metrics service](https://github.com/dracor-org/dracor-metrics) on
  `localhost:8030`
  - if it is not available, it will be installed to the `devel` directory
    and started
  - the process will be [spawned](https://ant.apache.org/manual/Tasks/exec.html)

Afterwards you can start the database with `ant devel.startup`.

### devel.startup

Starts the database. You can stop the database with `ant devel.shutdown`.

### devel.shutdown

Stops the database that has been started with `ant devel.startup`.

### load.corpus

Creates a test corpus and loads its data files into the database. You can use
this target to load other corpora as well by overriding the corpus property
like this:

```bash
ant load.corpus -Dcorpus=rus
```

Currently the following corpora are available (see [corpora](corpora)):

- ger
- rus
- shake
- test (default)

Note that loading the data can take several minutes depending on the size of the
corpus.

### atom.config

Creates a `.existdb.json` configuration for the database set up with `ant devel`
to support the [existdb package](https://atom.io/packages/existdb) for the
[Atom editor](https://atom.io).

### clean

Removes the `devel/` and the `build/` directories.

## Installation

You can install the XAR package built with `ant xar` via the dashboard of any
eXist DB instance.

For development purposes use `ant devel`.

## Webhook

The DraCor API provides a webhook (`/webhook/github`) that can trigger an update
of the corpus data when the configured GitHub repository for the corpus changes.

*Note:* For the webhook to work, the shared secret between DraCor and GitHub
needs to be configured at `/db/data/dracor/config.xml` in the database.

# dracor-api

The [eXistdb](http://exist-db.org/) application providing the API for
https://dracor.org.

API Documentation is available at [/documentation/api/](https://dracor.org/documentation/api/).

## tl;dr
Use `ant` to prepare an xar package or `ant devel` to prepare an development
environment. Both commands can be used together with `-Dtestdracor=true` to
initialize a small set of data for testing purposes.

## Requirements
- ant
- bash

For initialization an external service ([dracor-metrics](https://github.com/dracor-org/dracor-metrics))
is used. If not available, it will be installed during `ant devel`. As it is a
NodeJS tool, it requires `npm`.

The build tool uses Unix specific commands, that are available in most Linux
distributions and MacOS.

## Build
This software uses `ant` to build its artifacts. While several targets are exposed,
the following ones are considered to be useful:
- xar [default]
- devel
- cleanup

### xar
Prepares an [EXPath-Package](http://expath.org/spec/pkg) in the `build` directory.
It is aware of a so far not specified parameter `testdracor`. Instead of the
very complete import of all corpora, this parameter triggers the loading of
TestDraCor corpus. This is made for functional tests, but can be useful for
development when a complete data set is not necessary.

### devel
Prepares a development environment inside the `develop` directory. If this directory
is present, the process will fail. Please remove it yourself.

This target will do the following in this order:
- xar, see above
- download and extract a specified version of eXist-db
- download all dependencies and place them in the `autodeploy` directory
- set the http and https port of this instance (see [build.properties](build.properties))
- start the database once to install all dependencies
  - this step is required to set up the sparql package as it requires a change
  in the configuration file of eXist to be made after the installation
  - the database will shut down immediately
- look for a running instance of the [metrics service](https://github.com/dracor-org/dracor-metrics) on `localhost:8030`
  - if it is not available, it will be installed to the `develop` directory
  and started

### cleanup
Removes all loaded and prepared packages and files. It is like a `git reset` but
without restoring the source code.
It will remove the `develop/` and the `build/` directory.

## Installation
You can install the package in an eXist database. For development purposes
`ant devel` is recommended.

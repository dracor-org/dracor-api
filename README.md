# dracor-api

The [eXistdb](http://exist-db.org/) application providing the API for
https://dracor.org.

API Documentation is available at [/documentation/api/](https://dracor.org/documentation/api/).

## Build

There are several ant-targets defined:
- xar [default]
- cleanup
- test
- jetty-port
- exist-conf

```bash
ant
```

Running `ant` in the project root directory creates a .xar package in the
`build` directory.

## Installation

* install and start a recent version of [eXistdb](http://exist-db.org/)
* direct a browser to http://localhost:8080
* install the xar package using the package manager in the eXistdb dashboard

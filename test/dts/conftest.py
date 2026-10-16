"""
Fixtures for the DraCor DTS contract tests.

These tests complement the DTS validator. They check rules of the DTS 1.0
specification the validator does not cover, as well as DraCor-specific
conventions, against every resource of the selected corpora instead of a
randomly chosen one.

Run them with test/dts-validator.sh or directly:

    pytest test/dts --entry-endpoint=http://localhost:8081/exist/restxq/v1/dts
"""

import functools

import pytest
import requests
from uritemplate import URITemplate

DTS_CONTEXT = "https://dtsapi.org/context/v1.0.json"
DTS_VERSION = "1.0"
# the namespace of <dts:wrapper> as given in the DTS 1.0 specification
DTS_XML_NS = "https://w3id.org/api/dts#"
TEI_NS = "http://www.tei-c.org/ns/1.0"

TIMEOUT = 60


def pytest_addoption(parser):
    parser.addoption(
        "--entry-endpoint",
        action="store",
        required=True,
        help="URL of the DTS entry endpoint",
    )
    parser.addoption(
        "--corpus",
        action="append",
        default=[],
        help="restrict tests to the given corpus name (repeatable)",
    )
    parser.addoption(
        "--max-units",
        action="store",
        type=int,
        default=30,
        help="maximum number of CitableUnits checked individually per resource",
    )


class DTS:
    """Minimal client for a DTS API."""

    def __init__(self, entry_endpoint):
        self.entry_endpoint = entry_endpoint
        self.session = requests.Session()
        self.entry = self.get(entry_endpoint).json()

    def get(self, url, **kwargs):
        return self.session.get(url, timeout=TIMEOUT, **kwargs)

    def url(self, endpoint, **params):
        """Expand the URI template of an endpoint ignoring unset params."""
        params = {k: v for k, v in params.items() if v is not None}
        return URITemplate(self.entry[endpoint]).expand(**params)

    def collection(self, **params):
        return self.get(self.url("collection", **params))

    def navigation(self, **params):
        return self.get(self.url("navigation", **params))

    def document(self, **params):
        return self.get(self.url("document", **params))

    @functools.cache
    def whole_tree(self, resource):
        """Return the members of navigation with down=-1 for a resource."""
        r = self.navigation(resource=resource, down=-1)
        assert r.status_code == 200, r.text
        return r.json()["member"]


@functools.cache
def _client(entry_endpoint):
    return DTS(entry_endpoint)


def _corpora(config):
    dts = _client(config.getoption("--entry-endpoint"))
    root = dts.collection().json()
    selected = config.getoption("--corpus")
    corpora = []
    for member in root["member"]:
        name = member["@id"].rstrip("/").split("/")[-1]
        if not selected or name in selected:
            corpora.append(member["@id"])
    return corpora


def _resources(config):
    dts = _client(config.getoption("--entry-endpoint"))
    resources = []
    for corpus in _corpora(config):
        collection = dts.collection(id=corpus).json()
        resources += [
            m["@id"] for m in collection["member"] if m["@type"] == "Resource"
        ]
    return resources


def pytest_generate_tests(metafunc):
    if "corpus_id" in metafunc.fixturenames:
        metafunc.parametrize("corpus_id", _corpora(metafunc.config))
    if "resource_id" in metafunc.fixturenames:
        metafunc.parametrize("resource_id", _resources(metafunc.config))


@pytest.fixture(scope="session")
def dts(request):
    return _client(request.config.getoption("--entry-endpoint"))


@pytest.fixture(scope="session")
def max_units(request):
    return request.config.getoption("--max-units")


@pytest.fixture(scope="session")
def first_resource(request):
    resources = _resources(request.config)
    if not resources:
        pytest.skip("no resources found")
    return resources[0]


def sample_units(units, max_units):
    """
    Select the CitableUnits to check individually: all units of the two top
    levels plus an evenly spread sample of the deeper ones.
    """
    top = [u for u in units if u["level"] <= 2]
    deep = [u for u in units if u["level"] > 2]
    budget = max(max_units - len(top), 2)
    if len(deep) > budget:
        step = (len(deep) - 1) / (budget - 1)
        deep = [deep[round(i * step)] for i in range(budget)]
    return top + deep


def subtree(units, identifier, depth=None):
    """
    Return the unit with the given identifier followed by its descendants in
    document order, optionally limited to `depth` levels below it.
    """
    index = next(i for i, u in enumerate(units) if u["identifier"] == identifier)
    root = units[index]
    result = [root]
    ancestors = {identifier}
    for unit in units[index + 1:]:
        if unit["parent"] not in ancestors:
            break
        ancestors.add(unit["identifier"])
        if depth is None or unit["level"] - root["level"] <= depth:
            result.append(unit)
    return result

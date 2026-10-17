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


def spread(items, n):
    """Return n items evenly spread over a list, including first and last."""
    if len(items) <= n:
        return items
    if n == 1:
        return items[:1]
    step = (len(items) - 1) / (n - 1)
    return [items[round(i * step)] for i in range(n)]


def sample_units(units, max_units):
    """
    Select at most about `max_units` CitableUnits to check individually, in
    document order: all units of level 1 (front, body, back) and an evenly
    spread sample of each deeper level, so that every level is represented
    however the play is structured.
    """
    levels = sorted({u["level"] for u in units if u["level"] > 1})
    selected = [u for u in units if u["level"] == 1]
    if levels:
        per_level = max((max_units - len(selected)) // len(levels), 1)
        for level in levels:
            selected += spread([u for u in units if u["level"] == level], per_level)
    position = {u["identifier"]: i for i, u in enumerate(units)}
    return sorted(selected, key=lambda u: position[u["identifier"]])


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

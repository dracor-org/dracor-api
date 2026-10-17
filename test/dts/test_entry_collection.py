"""Contract tests for the DTS entry and collection endpoints."""

import pytest
from uritemplate import URITemplate

from conftest import DTS_CONTEXT, DTS_VERSION


def assert_json_ld(response):
    assert response.status_code == 200, response.text
    assert response.headers["Content-Type"].startswith("application/ld+json")
    return response.json()


def assert_top_level(body, type_):
    assert body["@type"] == type_


def find_key(obj, key):
    """Return True if `key` occurs anywhere in a JSON structure."""
    if isinstance(obj, dict):
        return key in obj or any(find_key(v, key) for v in obj.values())
    if isinstance(obj, list):
        return any(find_key(v, key) for v in obj)
    return False


def assert_cite_structure(structures):
    assert isinstance(structures, list)
    for structure in structures:
        assert structure["@type"] == "CiteStructure"
        assert isinstance(structure["citeType"], str) and structure["citeType"]
        assert_cite_structure(structure.get("citeStructure", []))


def assert_resource(resource):
    assert resource["@type"] == "Resource"
    for key in ("@id", "collection", "navigation", "document"):
        assert key in resource, f"Resource lacks {key}"
    assert isinstance(resource["totalParents"], int)
    assert "application/tei+xml" in resource.get("mediaTypes", [])


def test_context_and_version(dts, first_resource):
    """Every top-level response refers to the DTS 1.0 context and version."""
    responses = {
        "entry": dts.get(dts.entry_endpoint),
        "root collection": dts.collection(),
        "resource": dts.collection(id=first_resource),
        "navigation": dts.navigation(resource=first_resource, down=1),
    }
    for name, response in responses.items():
        body = assert_json_ld(response)
        assert body["@context"] == DTS_CONTEXT, name
        assert body["dtsVersion"] == DTS_VERSION, name


def test_entry_point(dts):
    body = assert_json_ld(dts.get(dts.entry_endpoint))
    assert_top_level(body, "EntryPoint")
    assert body["@id"]
    expected = {
        "collection": {"id", "page", "nav"},
        "navigation": {"resource", "ref", "start", "end", "down", "tree", "page"},
        "document": {"resource", "ref", "start", "end", "tree", "mediaType"},
    }
    for endpoint, variables in expected.items():
        assert URITemplate(body[endpoint]).variable_names == variables


def test_root_collection(dts):
    body = assert_json_ld(dts.collection())
    assert_top_level(body, "Collection")
    assert body["totalParents"] == 0
    assert isinstance(body["member"], list)
    assert body["totalChildren"] == len(body["member"])
    for member in body["member"]:
        assert member["@type"] == "Collection"
        assert member["totalParents"] == 1
        assert "collection" in member


def test_corpus_collection(dts, corpus_id):
    body = assert_json_ld(dts.collection(id=corpus_id))
    assert_top_level(body, "Collection")
    assert body["@id"] == corpus_id
    assert body["totalParents"] == 1
    assert isinstance(body["member"], list)
    assert body["totalChildren"] == len(body["member"])
    for member in body["member"]:
        assert_resource(member)
    assert not find_key(body, "maxCiteDepth")


def test_corpus_parents(dts, corpus_id):
    body = assert_json_ld(dts.collection(id=corpus_id, nav="parents"))
    assert isinstance(body["member"], list)
    assert len(body["member"]) == 1
    assert body["member"][0]["@type"] == "Collection"


def test_resource(dts, resource_id):
    body = assert_json_ld(dts.collection(id=resource_id))
    assert body["@id"] == resource_id
    assert_resource(body)
    trees = body["citationTrees"]
    assert isinstance(trees, list)
    for i, tree in enumerate(trees):
        assert tree["@type"] == "CitationTree"
        if i == 0:
            assert "identifier" not in tree, "the default tree has no identifier"
        assert_cite_structure(tree.get("citeStructure", []))
    assert not find_key(body, "maxCiteDepth")


def test_resource_parents(dts, resource_id):
    body = assert_json_ld(dts.collection(id=resource_id, nav="parents"))
    assert isinstance(body["member"], list)
    assert len(body["member"]) == 1
    assert body["member"][0]["@type"] == "Collection"


@pytest.mark.parametrize(
    "params,status",
    [
        ({"id": "https://example.org/id/nothing"}, 404),
        ({"id": "nothing-here"}, 404),
        ({"nav": "sideways"}, 400),
    ],
)
def test_collection_errors(dts, params, status):
    assert dts.collection(**params).status_code == status

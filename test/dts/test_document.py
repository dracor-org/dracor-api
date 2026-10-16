"""Contract tests for the DTS document endpoint."""

import xml.etree.ElementTree as ET

import pytest

from conftest import DTS_XML_NS, TEI_NS, sample_units

TEI = f"{{{TEI_NS}}}TEI"
WRAPPER = f"{{{DTS_XML_NS}}}wrapper"


def document(dts, **params):
    response = dts.document(**params)
    assert response.status_code == 200, f"{response.url}: {response.text[:500]}"
    return response


def tei(response):
    assert "xml" in response.headers["Content-Type"]
    root = ET.fromstring(response.content)
    assert root.tag == TEI, f"root element is {root.tag}"
    return root


def wrapper(root):
    wrappers = root.findall(f".//{WRAPPER}")
    assert len(wrappers) == 1, "fragment must be wrapped in a single dts:wrapper"
    assert len(wrappers[0]) > 0, "dts:wrapper is empty"
    return wrappers[0]


def assert_collection_link(response, resource_id):
    link = response.headers.get("Link", "")
    assert 'rel="collection"' in link, f"Link header: {link!r}"
    assert resource_id in link


def plain_text(response):
    assert response.headers["Content-Type"].startswith("text/plain")
    assert response.text.strip(), "text is empty"
    return response.text


def test_full_document(dts, resource_id):
    response = document(dts, resource=resource_id)
    root = tei(response)
    assert root.find(f"{{{TEI_NS}}}teiHeader") is not None
    assert_collection_link(response, resource_id)


def test_ref_fragments(dts, resource_id, max_units):
    units = dts.whole_tree(resource_id)
    for unit in sample_units(units, max_units // 3):
        response = document(dts, resource=resource_id, ref=unit["identifier"])
        wrapper(tei(response))
        assert_collection_link(response, resource_id)


def test_range_fragment(dts, resource_id):
    units = [u for u in dts.whole_tree(resource_id) if u["level"] == 1]
    if len(units) < 2:
        pytest.skip("less than two top-level units")
    start, end = units[0]["identifier"], units[-1]["identifier"]
    response = document(dts, resource=resource_id, start=start, end=end)
    wrapped = wrapper(tei(response))
    assert len(wrapped) >= 2


def test_plain_text(dts, resource_id):
    plain_text(document(dts, resource=resource_id, mediaType="text/plain"))
    units = dts.whole_tree(resource_id)
    if not units:
        return
    leaf = units[-1]["identifier"]
    plain_text(document(dts, resource=resource_id, ref=leaf, mediaType="text/plain"))
    top = [u for u in units if u["level"] == 1]
    if len(top) >= 2:
        plain_text(document(
            dts,
            resource=resource_id,
            start=top[0]["identifier"],
            end=top[-1]["identifier"],
            mediaType="text/plain",
        ))


@pytest.mark.parametrize(
    "params,status",
    [
        ({"ref": "body/div[9999]"}, 404),
        ({"mediaType": "application/x-nothing"}, 404),
    ],
)
def test_document_errors(dts, first_resource, params, status):
    response = dts.document(resource=first_resource, **params)
    assert response.status_code == status, f"{response.url}: {response.text[:500]}"


@pytest.mark.parametrize(
    "params",
    [
        {"ref": "body", "start": "front", "end": "body"},
        {"start": "front"},
        {"end": "body"},
    ],
)
def test_document_invalid_combinations(dts, first_resource, params):
    """The spec requires a 4xx error, but doesn't say which."""
    response = dts.document(resource=first_resource, **params)
    assert 400 <= response.status_code < 500, f"{response.url}"


def test_document_without_resource(dts):
    response = dts.get(dts.url("document"))
    assert response.status_code == 400


def test_unknown_document(dts):
    response = dts.document(resource="https://example.org/id/nothing")
    assert response.status_code == 404

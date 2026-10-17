"""Contract tests for the DTS navigation endpoint."""

import re

import pytest

from conftest import sample_units, subtree

# DraCor refs are XPath-like paths relative to tei:text
REF_PATTERN = re.compile(
    r"^(front|body|back)(/(div|sp|stage|set|castList|titlePage)\[[1-9][0-9]*\])*$"
)


def navigation(dts, **params):
    response = dts.navigation(**params)
    assert response.status_code == 200, f"{response.url}: {response.text}"
    assert response.headers["Content-Type"].startswith("application/ld+json")
    body = response.json()
    assert body["@type"] == "Navigation"
    assert body["@id"]
    resource = body["resource"]
    assert resource["@type"] == "Resource"
    assert resource["@id"] == params["resource"]
    for key in ("collection", "navigation", "document", "citationTrees"):
        assert key in resource, f"resource lacks {key}"
    if "member" in body:
        assert isinstance(body["member"], list), "member must be an array"
        for unit in body["member"]:
            assert_citable_unit(unit)
    for key in ("ref", "start", "end"):
        if key in body:
            assert_citable_unit(body[key])
    return body


def assert_citable_unit(unit):
    assert unit["@type"] == "CitableUnit"
    assert isinstance(unit["identifier"], str)
    assert isinstance(unit["level"], int) and unit["level"] >= 1
    assert "parent" in unit, f"{unit['identifier']} lacks parent"
    if unit["level"] == 1:
        assert unit["parent"] is None
    else:
        assert isinstance(unit["parent"], str)


def identifiers(units):
    return [u["identifier"] for u in units]


def test_whole_tree(dts, resource_id):
    units = navigation(dts, resource=resource_id, down=-1)["member"]
    ids = identifiers(units)
    assert len(ids) == len(set(ids)), "identifiers must be unique"
    seen = {}
    for unit in units:
        assert REF_PATTERN.match(unit["identifier"]), unit["identifier"]
        if unit["parent"] is not None:
            # pre-order: the parent precedes its children, one level up
            assert unit["parent"] in seen, unit["identifier"]
            assert seen[unit["parent"]]["level"] == unit["level"] - 1
        seen[unit["identifier"]] = unit


def test_down(dts, resource_id):
    units = dts.whole_tree(resource_id)
    for down in (1, 2):
        body = navigation(dts, resource=resource_id, down=down)
        expected = [u for u in units if u["level"] <= down]
        assert identifiers(body["member"]) == identifiers(expected)


def test_ref(dts, resource_id, max_units):
    units = dts.whole_tree(resource_id)
    for unit in sample_units(units, max_units):
        ref = unit["identifier"]

        body = navigation(dts, resource=resource_id, ref=ref)
        assert body["ref"]["identifier"] == ref
        assert body["ref"]["level"] == unit["level"]
        assert body["ref"]["parent"] == unit["parent"]
        assert "member" not in body

        body = navigation(dts, resource=resource_id, ref=ref, down=0)
        siblings = [u for u in units if u["parent"] == unit["parent"]]
        assert identifiers(body["member"]) == identifiers(siblings)

        body = navigation(dts, resource=resource_id, ref=ref, down=-1)
        assert identifiers(body["member"]) == identifiers(subtree(units, ref))

        body = navigation(dts, resource=resource_id, ref=ref, down=1)
        assert identifiers(body["member"]) == identifiers(subtree(units, ref, 1))


def test_leaf_ref(dts, resource_id):
    units = dts.whole_tree(resource_id)
    leaves = [
        u for i, u in enumerate(units)
        if i + 1 == len(units) or units[i + 1]["parent"] != u["identifier"]
    ]
    if not leaves:
        pytest.skip("resource has no citable units")
    leaf = leaves[-1]["identifier"]
    body = navigation(dts, resource=resource_id, ref=leaf, down=2)
    assert identifiers(body["member"]) == [leaf]


def sibling_range(units, level=None):
    """Return the first and third (or last) child of the first parent with at
    least two children, at the deepest level or the given level."""
    level = level or max(u["level"] for u in units)
    by_parent = {}
    for unit in units:
        if unit["level"] == level:
            by_parent.setdefault(unit["parent"], []).append(unit)
    for children in by_parent.values():
        if len(children) >= 2:
            return children[0], children[min(2, len(children) - 1)]
    return None


@pytest.mark.parametrize("level", [None, 2])
def test_range(dts, resource_id, level):
    units = dts.whole_tree(resource_id)
    if not units:
        pytest.skip("resource has no citable units")
    pair = sibling_range(units, level)
    if not pair:
        pytest.skip("no sibling units for a range")
    start, end = pair[0]["identifier"], pair[1]["identifier"]

    body = navigation(dts, resource=resource_id, start=start, end=end)
    assert body["start"]["identifier"] == start
    assert body["end"]["identifier"] == end
    assert "member" not in body

    ids = identifiers(units)
    first = ids.index(start)
    last = ids.index(subtree(units, end)[-1]["identifier"])
    in_range = units[first:last + 1]

    body = navigation(dts, resource=resource_id, start=start, end=end, down=-1)
    assert identifiers(body["member"]) == identifiers(in_range)

    body = navigation(dts, resource=resource_id, start=start, end=end, down=1)
    budget = pair[0]["level"] + 1
    expected = [u for u in in_range if u["level"] <= budget]
    assert identifiers(body["member"]) == identifiers(expected)


def test_xml_id_refs(dts, resource_id):
    """A ref may also be given as the @xml:id of a citable element."""
    units = [
        u for u in dts.whole_tree(resource_id)
        if u.get("extensions", {}).get("xmlId")
    ]
    if not units:
        pytest.skip("no citable units with @xml:id")
    for unit in units[:5]:
        xml_id = unit["extensions"]["xmlId"]
        body = navigation(dts, resource=resource_id, ref=xml_id)
        assert body["ref"]["identifier"] == unit["identifier"]


def test_empty_resource_param(dts):
    assert dts.navigation(resource="", down=1).status_code in (400, 404)


@pytest.mark.parametrize(
    "params,status",
    [
        ({}, 400),
        ({"down": 0}, 400),
        ({"ref": "body", "start": "body", "end": "body"}, 400),
        ({"ref": "body", "start": "body"}, 400),
        ({"start": "body"}, 400),
        ({"end": "body"}, 400),
        ({"start": "front", "end": "body", "down": 0}, 400),
        ({"ref": "body/div[9999]"}, 404),
        ({"ref": "not-a-ref"}, 404),
        ({"start": "body", "end": "body/div[9999]"}, 404),
        ({"ref": "body", "tree": "no-such-tree"}, 404),
    ],
)
def test_navigation_errors(dts, first_resource, params, status):
    response = dts.navigation(resource=first_resource, **params)
    assert response.status_code == status, f"{response.url}: {response.text}"


def test_unknown_resource(dts):
    response = dts.navigation(resource="https://example.org/id/nothing", down=1)
    assert response.status_code == 404

"""
Tests of the admin endpoints: creating, loading and deleting corpora, and
adding, updating and deleting plays.
"""

import pytest

from conftest import MINIMAL_PLAY, PLAY_NAME, SCRATCH_CORPUS, SCRATCH_CORPUS_XML

CORPUS_XML = f"""<?xml version="1.0" encoding="UTF-8"?>
<dracorCorpus xmlns="http://www.tei-c.org/ns/1.0">
  <teiHeader>
    <fileDesc>
      <titleStmt>
        <title>Scratch Corpus from XML</title>
      </titleStmt>
      <publicationStmt>
        <publisher>DraCor</publisher>
        <idno>{SCRATCH_CORPUS_XML}</idno>
      </publicationStmt>
    </fileDesc>
  </teiHeader>
</dracorCorpus>
"""


def corpus_names(api):
    return [corpus["name"] for corpus in api.get("/corpora").json()]


def play_names(api, corpus):
    return [play["name"] for play in api.get(f"/corpora/{corpus}").json()["plays"]]


# Creating corpora


def test_create_corpus_from_json(api):
    try:
        response = api.post_json(
            "/corpora", {"name": SCRATCH_CORPUS, "title": "Scratch Corpus"}
        )
        assert response.status_code == 200, response.text
        assert response.json() == {"name": SCRATCH_CORPUS, "title": "Scratch Corpus"}
        assert SCRATCH_CORPUS in corpus_names(api)
        assert play_names(api, SCRATCH_CORPUS) == []
    finally:
        api.delete(f"/corpora/{SCRATCH_CORPUS}")


def test_create_corpus_from_xml(api):
    try:
        response = api.request(
            "POST",
            "/corpora",
            data=CORPUS_XML.encode(),
            headers={"Content-Type": "application/xml"},
        )
        assert response.status_code == 200, response.text
        assert response.json()["name"] == SCRATCH_CORPUS_XML
        assert response.json()["title"] == "Scratch Corpus from XML"
        assert SCRATCH_CORPUS_XML in corpus_names(api)
    finally:
        api.delete(f"/corpora/{SCRATCH_CORPUS_XML}")


def test_create_existing_corpus(api, corpus):
    response = api.post_json("/corpora", {"name": corpus, "title": "Again"})
    assert response.status_code == 409, response.text


@pytest.mark.parametrize(
    "body",
    [
        {"name": "Scratch1", "title": "Invalid name"},
        {"name": SCRATCH_CORPUS},
        {"title": "No name"},
        {"name": SCRATCH_CORPUS, "title": {}},
        ["not", "an", "object"],
    ],
    ids=["invalid-name", "no-title", "no-name", "title-not-string", "array"],
)
def test_create_corpus_with_invalid_json(api, body):
    response = api.post_json("/corpora", body)
    assert response.status_code == 400, response.text
    assert SCRATCH_CORPUS not in corpus_names(api)


@pytest.mark.parametrize(
    "content_type,body",
    [
        ("application/json", '{"name":'),
        ("application/xml", "<dracorCorpus"),
        ("application/xml", "<notACorpus/>"),
    ],
    ids=["malformed-json", "malformed-xml", "not-a-corpus"],
)
def test_create_corpus_with_malformed_body(api, content_type, body):
    response = api.request(
        "POST", "/corpora", data=body, headers={"Content-Type": content_type}
    )
    assert response.status_code == 400, response.text


# Adding and updating plays


def test_add_play(api, corpus, play):
    info = api.get(play)
    assert info.status_code == 200, info.text
    assert info.json()["name"] == PLAY_NAME
    assert info.json()["corpus"] == corpus
    assert info.json()["title"] == "A Minimal Play"
    assert PLAY_NAME in play_names(api, corpus)

    characters = api.get(play + "/characters")
    assert characters.status_code == 200, characters.text
    assert sorted(c["id"] for c in characters.json()) == ["alice", "bob", "carol"]

    assert "Hello, Bob." in api.get(play + "/txt").text
    assert "A Minimal Play" in api.get(play + "/tei").text
    for path in ("/metrics", "/networkdata/csv", "/networkdata/gexf"):
        response = api.get(play + path)
        assert response.status_code == 200, f"{path}: {response.text}"


def test_update_play(api, corpus, play):
    changed = MINIMAL_PLAY.replace(b"A Minimal Play", b"A Changed Play")
    response = api.put_tei(corpus, PLAY_NAME, changed)
    assert response.status_code == 200, response.text
    assert api.get(play).json()["title"] == "A Changed Play"
    assert play_names(api, corpus) == [PLAY_NAME]


@pytest.mark.parametrize(
    "playname,body",
    [
        ("Bad_Name", MINIMAL_PLAY),
        ("other", b"<notTEI/>"),
        ("other", b"not XML"),
    ],
    ids=["invalid-name", "not-tei", "not-xml"],
)
def test_add_invalid_play(api, corpus, playname, body):
    response = api.put_tei(corpus, playname, body)
    assert response.status_code == 400, response.text
    assert play_names(api, corpus) == []


def test_add_play_to_unknown_corpus(api):
    response = api.put_tei("nosuchcorpus", PLAY_NAME, MINIMAL_PLAY)
    assert response.status_code == 404, response.text


# Loading corpora


def test_load_corpus(api, corpus):
    # The throwaway corpus has no repository, so the job finds nothing to load.
    response = api.post_json(f"/corpora/{corpus}", {"load": True})
    assert response.status_code == 202, response.text


@pytest.mark.parametrize(
    "body",
    [b'{"load": false}', b"", b'{"load":'],
    ids=["load-false", "empty", "malformed"],
)
def test_load_corpus_with_invalid_body(api, corpus, body):
    response = api.request(
        "POST",
        f"/corpora/{corpus}",
        data=body,
        headers={"Content-Type": "application/json"},
    )
    assert response.status_code == 400, response.text


def test_load_unknown_corpus(api):
    response = api.post_json("/corpora/nosuchcorpus", {"load": True})
    assert response.status_code == 404, response.text


# Deleting plays and corpora


def test_delete_play(api, corpus, play):
    response = api.delete(play)
    assert response.status_code == 200, response.text
    assert api.get(play).status_code == 404
    assert play_names(api, corpus) == []
    assert api.delete(play).status_code == 404


def test_delete_corpus(api, corpus, play):
    response = api.delete(f"/corpora/{corpus}")
    assert response.status_code == 200, response.text
    assert api.get(f"/corpora/{corpus}").status_code == 404
    assert api.get(play).status_code == 404
    assert corpus not in corpus_names(api)
    assert api.delete(f"/corpora/{corpus}").status_code == 404


# Requests without a body


@pytest.mark.parametrize(
    "method,path",
    [
        ("POST", "/corpora"),
        ("POST", f"/corpora/{SCRATCH_CORPUS}"),
        ("PUT", f"/corpora/{SCRATCH_CORPUS}/plays/{PLAY_NAME}/tei"),
    ],
    ids=["create-corpus", "load-corpus", "add-play"],
)
@pytest.mark.parametrize("content_type", [None, "text/plain"], ids=["none", "text"])
def test_unsupported_body(api, corpus, method, path, content_type):
    headers = {"Content-Type": content_type} if content_type else {}
    data = "x" if content_type else None
    response = api.request(method, path, data=data, headers=headers)
    assert response.status_code == 415, response.text


# Authentication

OPERATIONS = [
    ("POST", "/corpora", {"json": {"name": "other", "title": "Other"}}),
    ("POST", f"/corpora/{SCRATCH_CORPUS}", {"json": {"load": True}}),
    ("DELETE", f"/corpora/{SCRATCH_CORPUS}", {}),
    (
        "PUT",
        f"/corpora/{SCRATCH_CORPUS}/plays/{PLAY_NAME}/tei",
        {"data": MINIMAL_PLAY, "headers": {"Content-Type": "application/xml"}},
    ),
    ("DELETE", f"/corpora/{SCRATCH_CORPUS}/plays/{PLAY_NAME}", {}),
]


class BearerAuth:
    """An Authorization header with a scheme eXist-db doesn't accept."""

    def __call__(self, request):
        request.headers["Authorization"] = "Bearer x"
        return request


@pytest.mark.parametrize(
    "method,path,kwargs",
    OPERATIONS,
    ids=[f"{method} {path}" for method, path, _ in OPERATIONS],
)
@pytest.mark.parametrize("auth", [None, BearerAuth()], ids=["anonymous", "bearer"])
def test_unauthenticated_request(api, play, method, path, kwargs, auth):
    response = api.request(method, path, auth=auth, **kwargs)
    assert response.status_code == 401, response.text
    # nothing changed
    assert api.get(play).status_code == 200
    assert "other" not in corpus_names(api)

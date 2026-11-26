"""
Tests of the root elements of corpus.xml documents and of the check that
keeps webhooks and archives from storing a corpus.xml that breaks the corpus.

The root element is `teiHeader`. The deprecated `dracorCorpus` and `teiCorpus`
roots are still supported.
"""

from urllib.parse import urlparse

import pytest

from conftest import SCRATCH_CORPUS, SCRATCH_CORPUS_XML

CORPORA_ROOT = "/db/dracor/corpora"
REPO = "https://github.com/dracor-org/scratchdracor"

HEADER = """<teiHeader xmlns="http://www.tei-c.org/ns/1.0">
  <fileDesc>
    <titleStmt>
      <title>Scratch Corpus with {root} root</title>
    </titleStmt>
    <publicationStmt>
      <publisher>DraCor</publisher>
      <idno>{name}</idno>
      <ref type="repo" target="{repo}"/>
    </publicationStmt>
  </fileDesc>
  <encodingDesc>
    <projectDesc>
      <p>Description of the {root} corpus.</p>
    </projectDesc>
  </encodingDesc>
</teiHeader>"""


def corpus_xml(root, name=SCRATCH_CORPUS, repo=REPO):
    """A corpus.xml with the given root element."""
    header = HEADER.format(root=root, name=name, repo=repo)
    if root == "teiHeader":
        return header
    if root == "dracorCorpus":
        return (
            f'<dracorCorpus xmlns="http://www.tei-c.org/ns/1.0">{header}</dracorCorpus>'
        )
    # legacy teiCorpus, including the text it needed to be valid TEI
    return (
        '<teiCorpus xmlns="http://www.tei-c.org/ns/1.0">'
        f"{header}<text><body><p/></body></text></teiCorpus>"
    )


def store(rest, corpus, xml):
    """Store a corpus.xml in the database, as a webhook or archive would."""
    response = rest.request(
        "PUT",
        f"{CORPORA_ROOT}/{corpus}/corpus.xml",
        data=xml.encode(),
        headers={"Content-Type": "application/xml"},
    )
    assert response.status_code == 201, response.text


def xquery(rest, query):
    """Run an XQuery with the util module imported and return the result."""
    prolog = (
        'import module namespace dutil = "http://dracor.org/ns/exist/v1/util" '
        'at "/db/apps/dracor-v1/modules/util.xqm"; '
    )
    response = rest.get("/db", params={"_query": prolog + query, "_wrap": "no"})
    assert response.status_code == 200, response.text
    return response.text


@pytest.fixture
def repo_corpus(rest, corpus):
    """The throwaway corpus with a repository."""
    store(rest, corpus, corpus_xml("teiHeader"))
    return corpus


# Reading stored corpus.xml documents


@pytest.mark.parametrize("root", ["teiHeader", "dracorCorpus", "teiCorpus"])
def test_corpus_root(api, rest, play, root):
    store(rest, SCRATCH_CORPUS, corpus_xml(root))
    title = f"Scratch Corpus with {root} root"

    corpora = {c["name"]: c for c in api.get("/corpora").json()}
    assert corpora[SCRATCH_CORPUS]["title"] == title
    assert corpora[SCRATCH_CORPUS]["repository"] == REPO

    corpus = api.get(f"/corpora/{SCRATCH_CORPUS}")
    assert corpus.status_code == 200, corpus.text
    assert corpus.json()["title"] == title
    assert corpus.json()["description"] == f"Description of the {root} corpus."
    assert [p["name"] for p in corpus.json()["plays"]] == ["minimal"]

    metadata = api.get(f"/corpora/{SCRATCH_CORPUS}/metadata")
    assert metadata.status_code == 200, metadata.text
    assert len(metadata.json()) == 1

    # OAI identifiers use the host name of the API base
    identifier = f"oai:{urlparse(api.base).hostname}:{SCRATCH_CORPUS}"
    oai = api.get(
        "/oai",
        params={
            "verb": "GetRecord",
            "identifier": identifier,
            "metadataPrefix": "oai_dc",
        },
    )
    assert oai.status_code == 200, oai.text
    assert title in oai.text

    dts = api.get("/dts/collection")
    assert dts.status_code == 200, dts.text
    assert title in [m["title"] for m in dts.json()["member"]]

    # the corpus document is found when deleting the corpus
    response = api.delete(f"/corpora/{SCRATCH_CORPUS}")
    assert response.status_code == 200, response.text


@pytest.mark.parametrize("root", ["teiHeader", "dracorCorpus", "teiCorpus"])
def test_create_corpus_from_xml_root(api, rest, root):
    try:
        response = api.request(
            "POST",
            "/corpora",
            data=corpus_xml(root, name=SCRATCH_CORPUS_XML).encode(),
            headers={"Content-Type": "application/xml"},
        )
        assert response.status_code == 200, response.text
        assert response.json()["title"] == f"Scratch Corpus with {root} root"

        # the corpus.xml is stored with a teiHeader root
        stored = rest.get(f"{CORPORA_ROOT}/{SCRATCH_CORPUS_XML}/corpus.xml")
        assert stored.status_code == 200, stored.text
        assert stored.text.lstrip().startswith("<teiHeader")
    finally:
        api.delete(f"/corpora/{SCRATCH_CORPUS_XML}")


def test_create_corpus_from_play(api):
    play = corpus_xml("teiHeader", name=SCRATCH_CORPUS_XML).replace(
        "<teiHeader xmlns", "<TEI xmlns", 1
    )
    play = play.replace("<fileDesc>", "<teiHeader><fileDesc>", 1)
    play = play.replace("</teiHeader>", "</teiHeader><text/></TEI>")
    try:
        response = api.request(
            "POST",
            "/corpora",
            data=play.encode(),
            headers={"Content-Type": "application/xml"},
        )
        assert response.status_code == 400, response.text
        assert "Unexpected root element" in response.json()["error"]
    finally:
        api.delete(f"/corpora/{SCRATCH_CORPUS_XML}")


def test_create_corpus_from_json_root(api, rest, corpus):
    stored = rest.get(f"{CORPORA_ROOT}/{corpus}/corpus.xml")
    assert stored.status_code == 200, stored.text
    assert stored.text.lstrip().startswith("<teiHeader")


# Checking corpus.xml updates


def check_update(rest, xml, corpus=SCRATCH_CORPUS):
    """Result of dutil:check-corpus-update for xml passed as string."""
    literal = xml.replace("&", "&amp;").replace('"', '""')
    return xquery(rest, f'dutil:check-corpus-update("{literal}", "{corpus}")')


@pytest.mark.parametrize("root", ["teiHeader", "dracorCorpus", "teiCorpus"])
def test_check_corpus_update_accepts(rest, repo_corpus, root):
    assert check_update(rest, corpus_xml(root)) == ""


@pytest.mark.parametrize(
    "xml,message",
    [
        ("<teiHeader", "not well-formed"),
        ("not XML", "not well-formed"),
        (
            '<TEI xmlns="http://www.tei-c.org/ns/1.0"/>',
            "unexpected root element Q{http://www.tei-c.org/ns/1.0}TEI",
        ),
        (
            corpus_xml("teiHeader").replace("http://www.tei-c.org/ns/1.0", "x"),
            "unexpected root element Q{x}teiHeader",
        ),
        (corpus_xml("teiHeader", name="other"), "name 'other'"),
        (
            corpus_xml("teiHeader").replace(f"<idno>{SCRATCH_CORPUS}</idno>", ""),
            "name ''",
        ),
        (
            corpus_xml("teiHeader", repo="https://github.com/x/y"),
            "repository 'https://github.com/x/y'",
        ),
        (
            corpus_xml("teiHeader").replace(f'<ref type="repo" target="{REPO}"/>', ""),
            "repository ''",
        ),
    ],
    ids=[
        "malformed",
        "not-xml",
        "play",
        "no-tei-namespace",
        "other-name",
        "no-name",
        "other-repo",
        "no-repo",
    ],
)
def test_check_corpus_update_rejects(rest, repo_corpus, xml, message):
    assert message in check_update(rest, xml)


def test_check_corpus_update_without_repo(rest, corpus):
    # a corpus without repository may get one
    assert check_update(rest, corpus_xml("teiHeader")) == ""


def test_check_corpus_update_element(rest, repo_corpus):
    # an element is checked itself, not its children
    literal = corpus_xml("teiHeader").replace('"', '""')
    query = f'dutil:check-corpus-update(parse-xml("{literal}")/*, "{repo_corpus}")'
    assert xquery(rest, query) == ""


def test_check_corpus_update_several_repos(api, rest, corpus):
    # a stored corpus.xml with both an idno and a ref of type repo
    xml = corpus_xml("teiHeader").replace(
        "<ref ", f'<idno type="repo">{REPO}</idno><ref ', 1
    )
    store(rest, corpus, xml)
    assert api.get(f"/corpora/{corpus}").json()["repository"] == REPO
    assert check_update(rest, corpus_xml("teiHeader")) == ""
    message = check_update(rest, corpus_xml("teiHeader", repo="https://github.com/x/y"))
    assert message.endswith(f"instead of '{REPO}'")

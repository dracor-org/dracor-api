"""
Fixtures for the tests of the admin endpoints.

The tests create, change and delete corpora and plays, so they only use
throwaway corpora (see SCRATCH_CORPORA), which are removed before and after
the test session. Never run them against a production API.

Run them with test/admin.sh or directly:

    pytest test/admin --api-base=http://localhost:8081/exist/restxq/v1
"""

import os
from pathlib import Path

import pytest
import requests

TIMEOUT = 60

# the corpora the tests may create and delete
SCRATCH_CORPUS = "scratch"
SCRATCH_CORPUS_XML = "scratchxml"
SCRATCH_CORPORA = (SCRATCH_CORPUS, SCRATCH_CORPUS_XML)

PLAY_NAME = "minimal"
MINIMAL_PLAY = (Path(__file__).parent / "minimal-play.xml").read_bytes()


def pytest_addoption(parser):
    parser.addoption(
        "--api-base",
        action="store",
        default="http://localhost:8081/exist/restxq/v1",
        help="base URL of the DraCor API (default: the test stack)",
    )


class API:
    """Requests to the API, authenticated unless `auth=None` is passed."""

    def __init__(self, base, auth):
        self.base = base.rstrip("/")
        self.auth = auth

    def request(self, method, path, auth="default", **kwargs):
        return requests.request(
            method,
            self.base + path,
            auth=self.auth if auth == "default" else auth,
            timeout=TIMEOUT,
            **kwargs,
        )

    def get(self, path, **kwargs):
        return self.request("GET", path, **kwargs)

    def post_json(self, path, data, **kwargs):
        return self.request("POST", path, json=data, **kwargs)

    def put_tei(self, corpus, play, tei, **kwargs):
        return self.request(
            "PUT",
            f"/corpora/{corpus}/plays/{play}/tei",
            data=tei,
            headers={"Content-Type": "application/xml"},
            **kwargs,
        )

    def delete(self, path, **kwargs):
        return self.request("DELETE", path, **kwargs)


@pytest.fixture(scope="session")
def api(request):
    auth = (os.environ.get("EXIST_USER", "admin"), os.environ.get("EXIST_PASSWORD", ""))
    api = API(request.config.getoption("--api-base"), auth)
    try:
        api.get("/info").raise_for_status()
    except requests.RequestException as error:
        pytest.exit(f"No DraCor API at {api.base}: {error}", returncode=1)

    def remove_scratch_corpora():
        for name in SCRATCH_CORPORA:
            api.delete(f"/corpora/{name}")

    remove_scratch_corpora()
    yield api
    remove_scratch_corpora()


@pytest.fixture
def corpus(api):
    """An empty throwaway corpus, deleted after the test."""
    response = api.post_json(
        "/corpora", {"name": SCRATCH_CORPUS, "title": "Scratch Corpus"}
    )
    assert response.status_code == 200, response.text
    yield SCRATCH_CORPUS
    api.delete(f"/corpora/{SCRATCH_CORPUS}")


@pytest.fixture
def play(api, corpus):
    """The minimal play in the throwaway corpus."""
    response = api.put_tei(corpus, PLAY_NAME, MINIMAL_PLAY)
    assert response.status_code == 200, response.text
    return f"/corpora/{corpus}/plays/{PLAY_NAME}"

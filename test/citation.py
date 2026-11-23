# /// script
# requires-python = ">=3.10"
# dependencies = ["pyyaml==6.0.2"]
# ///
"""
Check that CITATION.cff and .zenodo.json agree on the metadata they share:
title, license, keywords and the authors (Zenodo creators) with their ORCIDs
and affiliations. Fields that only exist in one of them (e.g. Zenodo
contributors and communities) are not compared.

Usage:
  uv run test/citation.py
"""

import json
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent


def cff_person(author):
    name = ", ".join(
        part for part in (author.get("family-names"), author.get("given-names")) if part
    )
    return {
        "name": name or author.get("name"),
        "orcid": (author.get("orcid") or "").removeprefix("https://orcid.org/") or None,
        "affiliation": author.get("affiliation"),
    }


def zenodo_person(creator):
    return {
        "name": creator.get("name"),
        "orcid": creator.get("orcid"),
        "affiliation": creator.get("affiliation"),
    }


def main():
    cff = yaml.safe_load((ROOT / "CITATION.cff").read_text(encoding="utf-8"))
    zenodo = json.loads((ROOT / ".zenodo.json").read_text(encoding="utf-8"))

    pairs = {
        "title": (cff.get("title"), zenodo.get("title")),
        "license": (
            (cff.get("license") or "").lower(),
            (zenodo.get("license") or "").lower(),
        ),
        "keywords": (cff.get("keywords", []), zenodo.get("keywords", [])),
        "authors/creators": (
            [cff_person(a) for a in cff.get("authors", [])],
            [zenodo_person(c) for c in zenodo.get("creators", [])],
        ),
    }

    errors = 0
    for field, (in_cff, in_zenodo) in pairs.items():
        if in_cff != in_zenodo:
            errors += 1
            print(f"::error::{field} differ between CITATION.cff and .zenodo.json")
            print(f"  CITATION.cff: {json.dumps(in_cff, ensure_ascii=False)}")
            print(f"  .zenodo.json: {json.dumps(in_zenodo, ensure_ascii=False)}")

    for field in ("version", "publication_date"):
        if field in zenodo:
            errors += 1
            print(
                f"::error::.zenodo.json sets {field}; leave it out so Zenodo takes"
                " it from the release"
            )

    if errors == 0:
        print("CITATION.cff and .zenodo.json are in sync")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())

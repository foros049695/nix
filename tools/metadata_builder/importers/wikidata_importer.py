#!/usr/bin/env python3
"""
Importador de metadados abertos da Wikidata.
Licença dos Dados: CC0 1.0 Universal (Domínio Público).
"""

import json
import os
import time
import urllib.request
import urllib.parse
from typing import List, Dict, Any, Optional

CACHE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "cache"))

def fetch_wikidata_sparql(query: str, cache_file: str, timeout: int = 25) -> List[Dict[str, Any]]:
    os.makedirs(CACHE_DIR, exist_ok=True)
    cache_path = os.path.join(CACHE_DIR, cache_file)

    if os.path.exists(cache_path):
        with open(cache_path, "r", encoding="utf-8") as f:
            return json.load(f)

    url = "https://query.wikidata.org/sparql?" + urllib.parse.urlencode({"query": query, "format": "json"})
    req = urllib.request.Request(url, headers={
        "User-Agent": "ProjetoNixCatalogBuilder/1.0 (dev@nix.local; open-data-ingestion)",
        "Accept": "application/sparql-results+json"
    })

    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            data = json.load(resp)
            bindings = data.get("results", {}).get("bindings", [])
            with open(cache_path, "w", encoding="utf-8") as f:
                json.dump(bindings, f)
            return bindings
    except Exception as e:
        print(f"[Aviso Wikidata] Falha na consulta SPARQL ({cache_file}): {e}")
        return []

def import_wikidata_category(
    qid: str,
    kind: str,
    cache_name: str,
    limit: int = 3000,
    has_year: bool = True
) -> List[Dict[str, Any]]:
    """Importa registros de uma categoria cultural da Wikidata via SPARQL."""
    if has_year:
        sparql = f"""
        SELECT ?item ?title ?year WHERE {{
          ?item wdt:P31 wd:{qid};
                wdt:P577 ?date;
                rdfs:label ?title.
          FILTER(LANG(?title) = 'en')
          BIND(YEAR(?date) AS ?year)
        }}
        LIMIT {limit}
        """
    else:
        sparql = f"""
        SELECT ?item ?title WHERE {{
          ?item wdt:P31 wd:{qid};
                rdfs:label ?title.
          FILTER(LANG(?title) = 'en')
        }}
        LIMIT {limit}
        """

    bindings = fetch_wikidata_sparql(sparql, f"wikidata_{cache_name}.json")
    records: List[Dict[str, Any]] = []

    for b in bindings:
        item_uri = b.get("item", {}).get("value", "")
        item_qid = item_uri.split("/")[-1] if "/" in item_uri else ""
        title = b.get("title", {}).get("value", "").strip()

        if not item_qid or not title:
            continue

        raw_year = b.get("year", {}).get("value")
        year = int(raw_year) if raw_year and str(raw_year).isdigit() else None

        records.append({
            "id": f"nix:work:{kind}:wikidata:{item_qid}",
            "kind": kind,
            "title": title,
            "original_title": None,
            "creators": None,
            "genres": None,
            "release_year": year,
            "summary": None,  # Não inventa sinopses ausentes
            "cover_thumb": f"placeholder:{kind}",
            "external_ids": {"wikidata": item_qid},
            "source": "wikidata",
            "license": "CC0-1.0",
        })

    return records

def import_wikidata_all(
    movie_limit: int = 15000,
    series_limit: int = 8000,
    book_limit: int = 8000,
    manga_limit: int = 5000
) -> List[Dict[str, Any]]:
    all_records: List[Dict[str, Any]] = []

    print("[Wikidata] Ingerindo Filmes (Q11424)...")
    movies = import_wikidata_category("Q11424", "movie", "movies", limit=movie_limit, has_year=True)
    all_records.extend(movies)
    print(f"  -> {len(movies)} filmes ingeridos.")

    print("[Wikidata] Ingerindo Séries de TV (Q5398426)...")
    series = import_wikidata_category("Q5398426", "series", "series", limit=series_limit, has_year=True)
    all_records.extend(series)
    print(f"  -> {len(series)} séries ingeridas.")

    print("[Wikidata] Ingerindo Livros e Obras Literárias (Q571)...")
    books = import_wikidata_category("Q571", "book", "books", limit=book_limit, has_year=True)
    all_records.extend(books)
    print(f"  -> {len(books)} livros ingeridos.")

    print("[Wikidata] Ingerindo Mangás (Q21198342)...")
    mangas = import_wikidata_category("Q21198342", "manga", "manga", limit=manga_limit, has_year=False)
    all_records.extend(mangas)
    print(f"  -> {len(mangas)} mangás ingeridos.")

    return all_records

#!/usr/bin/env python3
"""
Importador de metadados do Anime Offline Database (manami-project).
Licença do Dataset: ODbL 1.0 (Database) / DbCL 1.0 (Contents).
"""

import json
import os
import hashlib
from typing import List, Dict, Any

def import_anime_offline_database(file_path: str, max_records: int = 50000) -> List[Dict[str, Any]]:
    if not os.path.exists(file_path):
        raise FileNotFoundError(f"Arquivo do Anime Offline Database não encontrado: {file_path}")

    with open(file_path, "r", encoding="utf-8") as f:
        raw = json.load(f)

    entries = raw.get("data", [])
    records: List[Dict[str, Any]] = []

    for item in entries:
        if len(records) >= max_records:
            break

        title = (item.get("title") or "").strip()
        if not title:
            continue

        raw_type = (item.get("type") or "TV").upper()
        # Mapeia para os 5 tipos canônicos do Nix: 'anime', 'movie', 'series', 'manga', 'book'
        kind = "anime"
        if raw_type == "MOVIE":
            kind = "anime"  # mantido como anime de metragem longa para integridade de catálogo

        # Identificadores externos
        sources = item.get("sources", [])
        ext_ids: Dict[str, str] = {}
        for s in sources:
            if "myanimelist.net/anime/" in s:
                ext_ids["mal"] = s.split("/")[-1]
            elif "anilist.co/anime/" in s:
                ext_ids["anilist"] = s.split("/")[-1]
            elif "kitsu.app/anime/" in s:
                ext_ids["kitsu"] = s.split("/")[-1]
            elif "anidb.net/anime/" in s:
                ext_ids["anidb"] = s.split("/")[-1]

        # ID determinístico canônico
        primary_ext = ext_ids.get("mal") or ext_ids.get("anilist") or ext_ids.get("kitsu")
        if primary_ext:
            work_id = f"nix:work:{kind}:aod:{primary_ext}"
        else:
            h = hashlib.sha256(title.encode("utf-8")).hexdigest()[:12]
            work_id = f"nix:work:{kind}:aod:{h}"

        year = None
        season = item.get("animeSeason", {})
        if season and isinstance(season, dict):
            year = season.get("year")

        creators = ", ".join(item.get("studios", [])) or None
        genres = ", ".join(item.get("tags", [])[:5]) or None
        synonyms = item.get("synonyms", [])
        original_title = synonyms[0] if synonyms else None

        records.append({
            "id": work_id,
            "kind": kind,
            "title": title,
            "original_title": original_title,
            "creators": creators,
            "genres": genres,
            "release_year": int(year) if year and str(year).isdigit() else None,
            "summary": None,  # Não inventa sinopses ausentes
            "cover_thumb": "placeholder:anime",  # Placeholder local para privacidade e conformidade de direitos
            "external_ids": ext_ids,
            "source": "anime-offline-database",
            "license": "ODbL-1.0",
        })

    return records

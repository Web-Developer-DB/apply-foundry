#!/usr/bin/env python3
"""Normalize the portable fields that must be byte-equal across both cores."""

import json
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: normalize_order.py ORDER OUTPUT", file=sys.stderr)
        return 2
    source = Path(sys.argv[1])
    target = Path(sys.argv[2])
    order = json.loads(source.read_text(encoding="utf-8-sig"))
    scope = order.get("dokumentumfang") or {}
    logistics = order.get("bewerbungslogistik") or {}
    normalized = {
        "schemaVersion": order.get("schemaVersion"),
        "pfadModus": order.get("pfadModus"),
        "firma": order.get("firma"),
        "firmaSlug": order.get("firmaSlug"),
        "rolle": order.get("rolle"),
        "rolleSlug": order.get("rolleSlug"),
        "datum": order.get("datum"),
        "bewerberDateiname": order.get("bewerberDateiname"),
        "zielOrdner": order.get("zielOrdner"),
        "arbeitsOrdner": order.get("arbeitsOrdner"),
        "kandidatOrdner": order.get("kandidatOrdner"),
        "dokumentmodus": order.get("dokumentmodus"),
        "dokumentumfang": {
            key: scope.get(key)
            for key in ("auswahl", "kennung", "lebenslauf", "anschreiben", "emailNachricht", "quelle", "bestaetigt", "emailAlleinBestaetigt")
        },
        "seitenstrategie": order.get("seitenstrategie"),
        "bewerbungsentscheidung": order.get("bewerbungsentscheidung"),
        "bewerbungslogistik": {
            key: logistics.get(key)
            for key in ("verfuegbarkeit", "fruehesterEintrittstermin", "stellenart", "stundenumfang", "arbeitsmodell", "region")
        },
        "quellnachweise": order.get("quellnachweise"),
    }
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(normalized, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

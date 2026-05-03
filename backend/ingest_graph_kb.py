"""
Ingest rebi_skincare_graph_kb.xlsx into public skincare Graph KB tables.

Requires: migration 20260503140000_skincare_graph_kb.sql applied.
Usage:
  GRAPH_KB_XLSX=/path/to/rebi_skincare_graph_kb.xlsx python3 ingest_graph_kb.py
  python3 ingest_graph_kb.py --file /path/to/rebi_skincare_graph_kb.xlsx
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path

import pandas as pd

from config import get_logger
from knowledge.db import pg_conn

log = get_logger("ingest_graph_kb")

HEADER_ROW = 4


def _truthy_tr(v) -> bool | None:
    if v is None or (isinstance(v, float) and pd.isna(v)):
        return None
    s = str(v).strip().upper()
    if s in ("EVET", "TRUE", "1", "YES"):
        return True
    if s in ("HAYIR", "FALSE", "0", "NO"):
        return False
    return None


def _float(v):
    if v is None or (isinstance(v, float) and pd.isna(v)):
        return None
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def _int(v):
    if v is None or (isinstance(v, float) and pd.isna(v)):
        return None
    try:
        return int(v)
    except (TypeError, ValueError):
        return None


def _text(v) -> str | None:
    if v is None or (isinstance(v, float) and pd.isna(v)):
        return None
    s = str(v).strip()
    return s or None


def _load_sheet(path: Path, name: str) -> pd.DataFrame:
    df = pd.read_excel(path, sheet_name=name, header=HEADER_ROW)
    drop = [c for c in df.columns if str(c).startswith("Unnamed")]
    return df.drop(columns=drop, errors="ignore")


def ingest_ingredient_profiles(cur, path: Path) -> int:
    df = _load_sheet(path, "ingredient_profiles")
    sql = """
        insert into public.ingredient_profiles (
          ingredient_id, ingredient_tr, ingredient_en, category,
          min_conc_pct, max_conc_pct, effective_conc_pct,
          ph_min, ph_max, solubility, penetration, skin_type_suitable,
          pregnancy_safe, evidence_level, pubmed_source
        ) values (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
        on conflict (ingredient_id) do update set
          ingredient_tr = excluded.ingredient_tr,
          ingredient_en = excluded.ingredient_en,
          category = excluded.category,
          min_conc_pct = excluded.min_conc_pct,
          max_conc_pct = excluded.max_conc_pct,
          effective_conc_pct = excluded.effective_conc_pct,
          ph_min = excluded.ph_min,
          ph_max = excluded.ph_max,
          solubility = excluded.solubility,
          penetration = excluded.penetration,
          skin_type_suitable = excluded.skin_type_suitable,
          pregnancy_safe = excluded.pregnancy_safe,
          evidence_level = excluded.evidence_level,
          pubmed_source = excluded.pubmed_source,
          updated_at = now()
    """
    n = 0
    for _, row in df.iterrows():
        cur.execute(
            sql,
            (
                _text(row.get("ingredient_id")),
                _text(row.get("ingredient_tr")) or "",
                _text(row.get("ingredient_en")),
                _text(row.get("category")),
                _float(row.get("min_conc_pct")),
                _float(row.get("max_conc_pct")),
                _float(row.get("effective_conc_pct")),
                _float(row.get("ph_min")),
                _float(row.get("ph_max")),
                _text(row.get("solubility")),
                _text(row.get("penetration")),
                _text(row.get("skin_type_suitable")),
                _truthy_tr(row.get("pregnancy_safe")),
                _text(row.get("evidence_level")),
                _text(row.get("pubmed_source")),
            ),
        )
        n += 1
    return n


def ingest_skin_conditions(cur, path: Path) -> int:
    df = _load_sheet(path, "skin_conditions")
    sql = """
        insert into public.skin_conditions (
          condition_id, condition_tr, condition_en, category, description_tr,
          icd10_code, severity_scale, affected_layer, trigger_factors, evidence_notes
        ) values (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
        on conflict (condition_id) do update set
          condition_tr = excluded.condition_tr,
          condition_en = excluded.condition_en,
          category = excluded.category,
          description_tr = excluded.description_tr,
          icd10_code = excluded.icd10_code,
          severity_scale = excluded.severity_scale,
          affected_layer = excluded.affected_layer,
          trigger_factors = excluded.trigger_factors,
          evidence_notes = excluded.evidence_notes,
          updated_at = now()
    """
    n = 0
    for _, row in df.iterrows():
        cur.execute(
            sql,
            (
                _text(row.get("condition_id")),
                _text(row.get("condition_tr")) or "",
                _text(row.get("condition_en")),
                _text(row.get("category")),
                _text(row.get("description_tr")),
                _text(row.get("icd10_code")),
                _text(row.get("severity_scale")),
                _text(row.get("affected_layer")),
                _text(row.get("trigger_factors")),
                _text(row.get("evidence_notes")),
            ),
        )
        n += 1
    return n


def ingest_ingredient_relationships(cur, path: Path) -> int:
    df = _load_sheet(path, "ingredient_relationships")
    sql = """
        insert into public.ingredient_relationships (
          relation_id, entity_a_id, entity_a_tr, relation_type, entity_b_id, entity_b_tr,
          strength, direction, condition_note, safety_critical, evidence_level, pubmed_ref
        ) values (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
        on conflict (relation_id) do update set
          entity_a_id = excluded.entity_a_id,
          entity_a_tr = excluded.entity_a_tr,
          relation_type = excluded.relation_type,
          entity_b_id = excluded.entity_b_id,
          entity_b_tr = excluded.entity_b_tr,
          strength = excluded.strength,
          direction = excluded.direction,
          condition_note = excluded.condition_note,
          safety_critical = excluded.safety_critical,
          evidence_level = excluded.evidence_level,
          pubmed_ref = excluded.pubmed_ref,
          updated_at = now()
    """
    n = 0
    for _, row in df.iterrows():
        cur.execute(
            sql,
            (
                _text(row.get("relation_id")),
                _text(row.get("entity_a_id")),
                _text(row.get("entity_a_tr")),
                _text(row.get("relation_type")) or "",
                _text(row.get("entity_b_id")),
                _text(row.get("entity_b_tr")),
                _float(row.get("strength")),
                _text(row.get("direction")),
                _text(row.get("condition_note")),
                _truthy_tr(row.get("safety_critical")),
                _text(row.get("evidence_level")),
                _text(row.get("pubmed_ref")),
            ),
        )
        n += 1
    return n


def ingest_condition_ingredient_map(cur, path: Path) -> int:
    df = _load_sheet(path, "condition_ingredient_map")
    sql = """
        insert into public.condition_ingredient_map (
          map_id, condition_id, condition_tr, ingredient_id, ingredient_tr,
          priority, use_case, min_conc_recommended, max_conc_recommended,
          time_of_day, notes_tr
        ) values (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
        on conflict (map_id) do update set
          condition_id = excluded.condition_id,
          condition_tr = excluded.condition_tr,
          ingredient_id = excluded.ingredient_id,
          ingredient_tr = excluded.ingredient_tr,
          priority = excluded.priority,
          use_case = excluded.use_case,
          min_conc_recommended = excluded.min_conc_recommended,
          max_conc_recommended = excluded.max_conc_recommended,
          time_of_day = excluded.time_of_day,
          notes_tr = excluded.notes_tr,
          updated_at = now()
    """
    n = 0
    for _, row in df.iterrows():
        cur.execute(
            sql,
            (
                _text(row.get("map_id")),
                _text(row.get("condition_id")),
                _text(row.get("condition_tr")),
                _text(row.get("ingredient_id")),
                _text(row.get("ingredient_tr")),
                _int(row.get("priority")),
                _text(row.get("use_case")),
                _text(row.get("min_conc_recommended")),
                _text(row.get("max_conc_recommended")),
                _text(row.get("time_of_day")),
                _text(row.get("notes_tr")),
            ),
        )
        n += 1
    return n


def ingest_safety_rules(cur, path: Path) -> int:
    df = _load_sheet(path, "safety_rules")
    sql = """
        insert into public.safety_rules (
          rule_id, rule_category, trigger_condition, blocked_ingredient, safe_alternative,
          severity, user_message_tr, evidence, always_refer_dermatologist, pubmed_ref
        ) values (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
        on conflict (rule_id) do update set
          rule_category = excluded.rule_category,
          trigger_condition = excluded.trigger_condition,
          blocked_ingredient = excluded.blocked_ingredient,
          safe_alternative = excluded.safe_alternative,
          severity = excluded.severity,
          user_message_tr = excluded.user_message_tr,
          evidence = excluded.evidence,
          always_refer_dermatologist = excluded.always_refer_dermatologist,
          pubmed_ref = excluded.pubmed_ref,
          updated_at = now()
    """
    n = 0
    for _, row in df.iterrows():
        cur.execute(
            sql,
            (
                _text(row.get("rule_id")),
                _text(row.get("rule_category")),
                _text(row.get("trigger_condition")) or "",
                _text(row.get("blocked_ingredient")),
                _text(row.get("safe_alternative")),
                _text(row.get("severity")),
                _text(row.get("user_message_tr")),
                _text(row.get("evidence")),
                _truthy_tr(row.get("always_refer_dermatologist")),
                _text(row.get("pubmed_ref")),
            ),
        )
        n += 1
    return n


def main() -> None:
    ap = argparse.ArgumentParser(description="Ingest skincare Graph KB xlsx into Postgres")
    ap.add_argument(
        "--file",
        dest="file",
        default=os.getenv("GRAPH_KB_XLSX", "").strip() or None,
        help="Path to rebi_skincare_graph_kb.xlsx (or set GRAPH_KB_XLSX)",
    )
    args = ap.parse_args()
    path_s = args.file
    if not path_s:
        raise SystemExit("Provide --file or set GRAPH_KB_XLSX to the xlsx path")
    path = Path(path_s).expanduser().resolve()
    if not path.is_file():
        raise SystemExit(f"File not found: {path}")

    log.info("Ingest Graph KB from %s", path)
    with pg_conn(autocommit=False) as conn:
        with conn.cursor() as cur:
            n1 = ingest_ingredient_profiles(cur, path)
            n2 = ingest_skin_conditions(cur, path)
            n3 = ingest_ingredient_relationships(cur, path)
            n4 = ingest_condition_ingredient_map(cur, path)
            n5 = ingest_safety_rules(cur, path)
        conn.commit()

    summary = {
        "ingredient_profiles": n1,
        "skin_conditions": n2,
        "ingredient_relationships": n3,
        "condition_ingredient_map": n4,
        "safety_rules": n5,
    }
    log.info("Done: %s", summary)
    print(summary)


if __name__ == "__main__":
    main()

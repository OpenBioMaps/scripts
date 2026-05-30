#!/usr/bin/env python3
# 
# Description: Validate taxon names using "superspecies"
# Arguments:
# --input:  the input CSV file containing the columns of taxon names 
# --column: the name of the column to be validated and the validation configuration.
#           The configuration can be "taxon" or "token". The "taxon" setting
#           is used for validating scientific names. The "token" setting can be used 
#           for common names.
#           usage: --column="my_species_names:taxon"
# Output: validation_errors.csv, which contains the input names, name suggestions,
#         the number of rows, and validation scores, 
# Version: 1.0
# Author: Bán Miklós
# Date: 2026. május 29.
# Usage note: The ssp_speciesnames.csv and ssp_nationalnames_hun.csv files must be placed 
#             from the superspecies folder into the directory where the script runs.
# Usage example:
# python3 csv_validation.py --input=fajnevek.csv --columns="Élőhely_Kötődő_fajok_(lista)_latin:taxon" --columns="Faj_neve_latin:taxon" --columns="Élőhely_Kötődő_fajok_(lista)_hu:token" --columns="Faj_neve_hu:token"

import pandas as pd
from rapidfuzz import process, fuzz
from pathlib import Path
import re
import unicodedata
import argparse

# =========================================================
# CLI
# =========================================================

parser = argparse.ArgumentParser()

parser.add_argument(
    "--input",
    required=True
)

parser.add_argument(
    "--columns",
    action="append",
    required=True,
    help="format: COLUMN_NAME:SCORER"
)

args = parser.parse_args()

# =========================================================
# SSP CONFIG
# =========================================================

SSP_SPECIES = "ssp_speciesnames.csv"
SSP_HUN = "ssp_nationalnames_hun.csv"

SSP_CONFIG = {

    "taxon": {
        "file": SSP_SPECIES,
        "column": "species_name",
        "type": "scientific_name",
        "scorer": "taxon",
        "low_score": 60,
        "high_score": 90
    },

    "token": {
        "file": SSP_HUN,
        "column": "magyarnev",
        "type": "hungarian",
        "scorer": "token",
        "low_score": 72,
        "high_score": 90
    }
}

VALIDATION_CONFIG = {} 

for item in args.columns:

    try:

        col_name, scorer_name = item.split(":", 1)

    except ValueError:

        raise ValueError(
            f"Failure --columns format: {item}"
        )

    if scorer_name not in SSP_CONFIG:

        raise ValueError(
            f"Unknown scorer: {scorer_name}"
        )

    VALIDATION_CONFIG[col_name] = (
        SSP_CONFIG[scorer_name].copy()
    )

VALIDATION_INPUT_CSV = args.input

# fuzzy minimum score
#FUZZY_HIGH = 90
#FUZZY_LOW = 60
EPITHET_PRIORITY_THRESHOLD = 70

def canonicalize(text):

    if text is None:
        return ""

    text = str(text)

    text = unicodedata.normalize("NFKC", text)

    text = text.lower()

    # kötőjel normalizálás
    text = (
        text.replace("–", "-")
            .replace("—", "-")
    )

    # minden whitespace/kötőjel egységes
    text = re.sub(r'[-\s]+', ' ', text)

    # csak betűk/számok
    text = re.sub(r'[^a-z0-9áéíóöőúüűà-ÿ ]', '', text)

    text = re.sub(r'\s+', ' ', text)

    return text.strip()

# Normalize names
def normalize_taxon(text):

    text = canonicalize(text)

    replacements = {
        "subsp": "",
        "subsp.": "",
        "ssp": "",
        "ssp.": "",
        "var": "",
        "var.": "",
    }

    parts = []

    for p in text.split():

        if p in replacements:
            continue

        parts.append(p)

    return parts

GENERIC_SPECIES = {
    "sp",
    "sp.",
    "spp",
    "spp."
}


# =========================================================
# SSP ADATOK BETÖLTÉSE
# =========================================================

print("Loading SSP data...")

ssp_cache = {}

species_epithet_index = {}

for cfg in SSP_CONFIG.values():

    key = (cfg["file"], cfg["column"])

    if key not in ssp_cache:

        tmp_df = pd.read_csv(cfg["file"])

        values = (
            tmp_df[cfg["column"]]
            .dropna()
            .astype(str)
            .str.strip()
            .unique()
            .tolist()
        )

        ssp_cache[key] = {

            "original_set": set(values),

            "canonical_map": {
                canonicalize(v): v
                for v in values
            }
        }

    for full_name in values:

        parts = normalize_taxon(full_name)

        if len(parts) >= 2:

            species = parts[1]

            if species in GENERIC_SPECIES:
                continue

            if species not in species_epithet_index:

                species_epithet_index[species] = []

            species_epithet_index[species].append(
                full_name
            )

print("OK")


# =========================================================
# VALIDATION_INPUT CSV BETÖLTÉS
# =========================================================

print("Loading Validation Input CSV...")

df = pd.read_csv(VALIDATION_INPUT_CSV)

print(f"{len(df)} rows")


def taxon_score(a, b):

    a_parts = normalize_taxon(a)
    b_parts = normalize_taxon(b)

    score = 0

    # =====================================================
    # GENUS
    # =====================================================

    if len(a_parts) > 0 and len(b_parts) > 0:

        genus_score = fuzz.ratio(
            a_parts[0],
            b_parts[0]
        )

        score += genus_score * 0.55 #0.25

        # genus mismatch penalty
        if genus_score < 85:

            score -= 30

    # =====================================================
    # SPECIES
    # =====================================================

    if len(a_parts) > 1 and len(b_parts) > 1:

        a_species = a_parts[1]
        b_species = b_parts[1]
        
        # -------------------------------------------------
        # GENERIC spp./sp.
        # -------------------------------------------------

        if (
            a_species in GENERIC_SPECIES
            or b_species in GENERIC_SPECIES
        ):

            # genus egyezés esetén erős bonus
            if a_parts[0] == b_parts[0]:

                score += 25

        else:

            species_score = fuzz.ratio(
                a_species,
                b_species
            )

            score += species_score * 0.45

    # =====================================================
    # INFRA TAXON
    # =====================================================

    if len(a_parts) > 2 and len(b_parts) > 2:

        infra_score = fuzz.ratio(
            a_parts[2],
            b_parts[2]
        )

        # ez kapja a LEGNAGYOBB súlyt
        score += infra_score * 0.35 #0.60

    # =====================================================
    # TOKEN COUNT PENALTY
    # =====================================================

    token_diff = abs(
        len(a_parts) - len(b_parts)
    )

    score -= token_diff * 8

    return max(score, 0)

# =========================================================
# VALIDÁLÁS
# =========================================================
def canonicalize_compact(text):

    text = canonicalize(text)

    text = re.sub(r'[\s\-]+', '', text)

    return text


results = []

for col, cfg in VALIDATION_CONFIG.items():

    print(f"\nValidation: {col}")

    cache = ssp_cache[(cfg["file"], cfg["column"])]

    lookup_set = cache["original_set"]

    lookup_canonical = cache["canonical_map"]

    canonical_keys = list(lookup_canonical.keys())

    not_found_count = 0

    for idx, value in df[col].items():

        if pd.isna(value):
            continue

        value = str(value).strip()

        if value == "":
            continue

        value_canonical = canonicalize(value)

        # =================================================
        # 1. EXACT MATCH
        # =================================================

        if value in lookup_set:

            continue

        # =================================================
        # 2. CANONICAL EXACT MATCH
        # =================================================

        if value_canonical in lookup_canonical:

            results.append({
                "dataframe_index": idx,
                "csv_row": idx + 2,
                "validated_column": col,
                "original_value": value,
                "match_type": "canonical_exact",
                "fuzzy_score": 100,
                "suggestions": lookup_canonical[value_canonical]
            })

            continue

        # =================================================
        # 3. FUZZY
        # =================================================

        not_found_count += 1

        matches = []

        for candidate in canonical_keys:

            # For scientific names we have our own scorer: taxon_score()
            if cfg.get("scorer") == "taxon":

                score = taxon_score(
                    value_canonical,
                    candidate
                )

            # For national names we can use the built in token_set_ratio()
            else:

                score = fuzz.token_set_ratio(
                    canonicalize_compact(value_canonical),
                    canonicalize_compact(candidate)
                )

            if score >= cfg.get("low_score"):

                matches.append(
                    (
                        candidate,
                        score
                    )
                )

        # score szerint rendezés
        matches = sorted(
            matches,
            key=lambda x: x[1],
            reverse=True
        )[:5]

        best_score = 0

        if matches:

            best_score = matches[0][1]

        # SPLIT HIGH/MEDIUM

        high_matches = []
        medium_matches = []

        for match, score in matches:

            original_match = lookup_canonical[match]

            if score >= cfg.get("high_score"):

                high_matches.append(
                    f"{original_match}"
                )

            elif score >= cfg.get("low_score"):

                medium_matches.append(
                    f"{original_match}"
                )

        # =================================================
        # RESULT
        # =================================================

        if high_matches:

            match_type = "high_fuzzy"
            suggestions = "; ".join(high_matches)

        elif medium_matches:

            match_type = "medium_fuzzy"
            suggestions = "; ".join(medium_matches)

        else:

            match_type = "not_found"
            suggestions = None

        # =================================================
        # SPECIES EPITHET RESCUE
        # =================================================

        if cfg["scorer"] == "taxon":

            parts = normalize_taxon(value)

            if len(parts) >= 2:

                species = parts[1]

                if species not in GENERIC_SPECIES:

                    epithet_matches = []

                    for indexed_species, hits in species_epithet_index.items():

                        if indexed_species in GENERIC_SPECIES:
                            continue

                        species_score = fuzz.ratio(
                            species,
                            indexed_species
                        )

                        if species_score >= 85:

                            for hit in hits:

                                hit_parts = normalize_taxon(hit)

                                genus_score = 0

                                if (
                                    len(parts) > 0
                                    and len(hit_parts) > 0
                                ):

                                    genus_score = fuzz.ratio(
                                        parts[0],
                                        hit_parts[0]
                                    )

                                combined_score = (
                                    species_score * 0.8
                                    + genus_score * 0.2
                                )

                                epithet_matches.append(
                                    (
                                        hit,
                                        combined_score,
                                        species_score,
                                        genus_score
                                    )
                                )

                    # ----------------------------------------
                    # SORT
                    # ----------------------------------------

                    epithet_matches = sorted(
                        epithet_matches,
                        key=lambda x: x[1],
                        reverse=True
                    )

                    rescue_hits = []

                    already_seen = set()

                    for (
                        hit,
                        combined_score,
                        species_score,
                        genus_score
                    ) in epithet_matches:

                        if hit in already_seen:
                            continue

                        already_seen.add(hit)

                        rescue_hits.append(
                            f"{hit} "
                            f"(epithet:{species_score:.1f}, "
                            f"genus:{genus_score:.1f})"
                        )

                    rescue_hits = rescue_hits[:5]

                    # ----------------------------------------
                    # PRIORITY MERGE
                    # ----------------------------------------

                    if rescue_hits:

                        all_suggestions = []

                        if best_score < 70:

                            all_suggestions.extend(
                                rescue_hits
                            )

                            if suggestions:

                                all_suggestions.extend(
                                    suggestions.split("; ")
                                )

                        else:

                            if suggestions:

                                all_suggestions.extend(
                                    suggestions.split("; ")
                                )

                            #all_suggestions.extend(
                            #    rescue_hits
                            #)

                        suggestions = "; ".join(
                            all_suggestions
                        )

        # =================================================
        # SAVE RESULT
        # =================================================

        results.append({
            "row_index": idx,
            "csv_row": idx + 2,
            "validated_column": col,
            "original_value": value,
            "match_type": match_type,
            "fuzzy_score": best_score,
            "suggestions": suggestions
        })

    print(f"Not found: {not_found_count}")

# =========================================================
# EXPORT
# =========================================================

result_df = pd.DataFrame(results)

result_df.to_csv(
    "validation_errors.csv",
    index=False
)

print("\nDone:")
print("validation_errors.csv")

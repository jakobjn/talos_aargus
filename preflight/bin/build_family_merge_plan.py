#!/usr/bin/env python3

from __future__ import annotations

import argparse
import csv
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pedigree", required=True, type=Path)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args()


def load_manifest(path: Path) -> dict[str, str]:
    with path.open() as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        return {row["sample_id"]: row["vcf_path"] for row in reader}


def main() -> None:
    args = parse_args()
    sample_to_vcf = load_manifest(args.manifest)

    rows: list[dict[str, str]] = []
    with args.pedigree.open() as handle:
        for raw_line in handle:
            line = raw_line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            fields = line.split("\t")
            if len(fields) < 6:
                raise SystemExit(f"Malformed pedigree row: {line}")
            family_id, sample_id, father_id, mother_id, sex, phenotype = fields[:6]
            if phenotype != "2":
                continue

            members = [sample_id, father_id, mother_id]
            input_vcfs = []
            for member_id in members:
                member_id = member_id.strip()
                if not member_id or member_id == "0":
                    continue
                try:
                    input_vcfs.append(sample_to_vcf[member_id])
                except KeyError as exc:
                    raise SystemExit(
                        f"No prepared VCF found for pedigree member {member_id}"
                    ) from exc

            if not input_vcfs:
                raise SystemExit(f"No input VCFs resolved for proband {sample_id}")

            rows.append(
                {
                    "family_id": family_id,
                    "proband_id": sample_id,
                    "output_name": f"{family_id}_{sample_id}",
                    "input_vcfs": "|".join(input_vcfs),
                }
            )

    with args.output.open("w", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=["family_id", "proband_id", "output_name", "input_vcfs"],
            delimiter="\t",
        )
        writer.writeheader()
        writer.writerows(rows)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3

from __future__ import annotations

import argparse
import csv
import gzip
import io
import re
import zipfile
from pathlib import Path
from xml.etree import ElementTree

NS = {
    "main": "http://schemas.openxmlformats.org/spreadsheetml/2006/main",
    "rel": "http://schemas.openxmlformats.org/package/2006/relationships",
    "office_rel": "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Prepare department preflight inputs from the Excel sample list.")
    parser.add_argument("--samplelist", type=Path, default=Path("samplelist.xlsx"))
    parser.add_argument("--department", default="DEPT")
    parser.add_argument("--manifest-output", type=Path, default=Path("preflight_inputs/sample_manifest.tsv"))
    parser.add_argument("--pedigree-output", type=Path, default=Path("preflight_inputs/pedigree.ped"))
    parser.add_argument("--report-output", type=Path, default=Path("preflight_inputs/mapping_report.tsv"))
    parser.add_argument("--symlink-dir", type=Path, default=Path("VCF/VCF_symlinks"))
    parser.add_argument("--mapping-roots", default="")
    parser.add_argument("--exclude", action="append", default=[])
    return parser.parse_args()


def col_index(cell_ref: str) -> int:
    letters = re.match(r"[A-Z]+", cell_ref).group(0)
    value = 0
    for char in letters:
        value = value * 26 + ord(char) - ord("A") + 1
    return value - 1


def shared_strings(xlsx: zipfile.ZipFile) -> list[str]:
    try:
        root = ElementTree.fromstring(xlsx.read("xl/sharedStrings.xml"))
    except KeyError:
        return []
    strings = []
    for si in root.findall("main:si", NS):
        strings.append("".join(t.text or "" for t in si.findall(".//main:t", NS)).strip())
    return strings


def first_sheet_path(xlsx: zipfile.ZipFile) -> str:
    workbook = ElementTree.fromstring(xlsx.read("xl/workbook.xml"))
    sheet = workbook.find("main:sheets/main:sheet", NS)
    if sheet is None:
        raise ValueError("No sheets found in workbook")
    rel_id = sheet.attrib[f"{{{NS['office_rel']}}}id"]
    rels = ElementTree.fromstring(xlsx.read("xl/_rels/workbook.xml.rels"))
    for rel in rels.findall("rel:Relationship", NS):
        if rel.attrib["Id"] == rel_id:
            target = rel.attrib["Target"].lstrip("/")
            return target if target.startswith("xl/") else f"xl/{target}"
    raise ValueError(f"Could not resolve worksheet relationship {rel_id}")


def read_xlsx_rows(path: Path, width: int = 7) -> list[list[str]]:
    with zipfile.ZipFile(path) as xlsx:
        strings = shared_strings(xlsx)
        sheet = ElementTree.fromstring(xlsx.read(first_sheet_path(xlsx)))
    rows: list[list[str]] = []
    for row in sheet.findall(".//main:sheetData/main:row", NS):
        values = [""] * width
        for cell in row.findall("main:c", NS):
            idx = col_index(cell.attrib["r"])
            if idx >= width:
                continue
            cell_type = cell.attrib.get("t")
            if cell_type == "inlineStr":
                value = "".join(t.text or "" for t in cell.findall(".//main:t", NS))
            else:
                raw = cell.find("main:v", NS)
                value = "" if raw is None or raw.text is None else raw.text
                if cell_type == "s" and value:
                    value = strings[int(value)]
            values[idx] = value.strip()
        if any(values):
            rows.append(values)
    return rows


def interpretation_roots(samplelist: Path, department: str, override: str) -> tuple[Path, ...]:
    if override:
        parts = [Path(p) for p in override.split("|") if p.strip()]
        if not parts:
            raise SystemExit("--mapping-roots must contain at least one path")
        return tuple(parts)
    local_source_vcfs = samplelist.resolve().parent / "source_vcfs"
    if local_source_vcfs.is_dir():
        return (local_source_vcfs,)
    project_root = Path(f"/faststorage/project/MomaDiagnosticSamples-{department.strip()}")
    return (
        project_root / "BACKUP" / "interpretation",
        project_root / "BACKUP" / department.strip() / "extra_samples" / "interpretation",
    )


def find_vcf(subject_id: str, roots: tuple[Path, ...]) -> tuple[str, Path | None]:
    for root in roots:
        base = root / subject_id
        for major in ("2", "1"):
            for version_dir in sorted(p for p in base.glob(f"v{major}.*") if p.is_dir()):
                vcfs = sorted(version_dir.glob("*/*.gatk.haplotype_caller.vcf.gz"))
                if vcfs:
                    return version_dir.name, vcfs[0]
    return "MISSING", None


def single_sample_name(vcf: Path) -> str:
    with gzip.open(vcf, "rt") as handle:
        for line in handle:
            if line.startswith("#CHROM"):
                samples = line.rstrip("\n").split("\t")[9:]
                if len(samples) != 1:
                    raise ValueError(f"{vcf} has {len(samples)} samples; expected 1")
                return samples[0]
    raise ValueError(f"No #CHROM line found in {vcf}")


def link_one(source: Path, target: Path) -> None:
    if target.exists() or target.is_symlink():
        if target.resolve() != source.resolve():
            raise FileExistsError(f"{target} already exists and points elsewhere")
        return
    target.symlink_to(source.resolve())


def symlink_vcf(vcf: Path, symlink_dir: Path) -> Path:
    symlink_dir.mkdir(parents=True, exist_ok=True)
    link_path = symlink_dir / vcf.name
    link_one(vcf, link_path)
    for suffix in (".tbi", ".csi"):
        index = Path(f"{vcf}{suffix}")
        if index.exists():
            link_one(index, symlink_dir / index.name)
    return link_path


def tsv_text(rows: list[tuple[str, ...]] | list[list[str]], header: tuple[str, ...] | None = None) -> str:
    buffer = io.StringIO()
    writer = csv.writer(buffer, delimiter="\t", lineterminator="\n")
    if header is not None:
        writer.writerow(header)
    writer.writerows(rows)
    return buffer.getvalue()


def write_text_if_changed(path: Path, text: str) -> str:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and path.read_text() == text:
        return "unchanged"
    path.write_text(text)
    return "written"


def main() -> None:
    args = parse_args()
    rows = read_xlsx_rows(args.samplelist)
    roots = interpretation_roots(args.samplelist, args.department, args.mapping_roots)
    excluded = set(args.exclude or [])

    subject_to_sample: dict[str, str] = {}
    manifest_rows: list[tuple[str, str]] = []
    report_rows: list[tuple[str, str, str, str, str, str]] = []
    manifest_samples: set[str] = set()

    for row in rows:
        if len(row) < 2:
            continue
        subject_id = row[1].strip()
        if not subject_id or subject_id.startswith("#") or subject_id.lower().startswith("sample id") or subject_id in excluded:
            continue
        version, path = find_vcf(subject_id, roots)
        if path is None:
            report_rows.append((subject_id, version, "", "", "", "missing"))
            continue
        try:
            sample_name = single_sample_name(path)
        except Exception as exc:
            report_rows.append((subject_id, version, str(path), "", "", f"error:{exc}"))
            continue
        if sample_name in excluded:
            report_rows.append((subject_id, version, str(path), sample_name, "", "excluded"))
            continue
        symlink = symlink_vcf(path, args.symlink_dir)
        subject_to_sample[subject_id] = sample_name
        if sample_name not in manifest_samples:
            manifest_samples.add(sample_name)
            manifest_rows.append((sample_name, str(symlink)))
        report_rows.append((subject_id, version, str(path), sample_name, str(symlink), "resolved"))

    if not manifest_rows:
        searched = ", ".join(str(root) for root in roots)
        raise SystemExit(f"No VCFs resolved from {args.samplelist}; searched: {searched}")

    pedigree_rows: list[list[str]] = []
    for row in rows[1:]:
        padded = (row + [""] * 7)[:7]
        if not padded[0] or padded[1] in excluded:
            continue
        for idx in (1, 2, 3):
            value = padded[idx].strip()
            if value and value != "0":
                padded[idx] = subject_to_sample.get(value, value)
        if padded[1] in excluded:
            continue
        pedigree_rows.append(padded)

    manifest_status = write_text_if_changed(
        args.manifest_output,
        tsv_text(manifest_rows, header=("sample_id", "vcf_path")),
    )
    report_status = write_text_if_changed(
        args.report_output,
        tsv_text(report_rows, header=("subject_id", "version", "vcf_path", "vcf_sample", "symlink_path", "status")),
    )
    pedigree_status = write_text_if_changed(args.pedigree_output, tsv_text(pedigree_rows))

    print(f"manifest: {args.manifest_output} ({len(manifest_rows)} samples, {manifest_status})")
    print(f"pedigree: {args.pedigree_output} ({pedigree_status})")
    print(f"mapping report: {args.report_output} ({report_status})")
    print(f"vcf symlinks: {args.symlink_dir}")


if __name__ == "__main__":
    main()

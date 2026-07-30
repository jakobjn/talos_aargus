#!/usr/bin/env python3

"""
Native mitochondrial VCF reformatter and labeller.

This path intentionally keeps mito support narrow: only ClinVar pathogenic / likely pathogenic
mitochondrial variants in PanelApp green genes are emitted.
"""

from __future__ import annotations

from argparse import ArgumentParser

from cyvcf2 import VCF
from loguru import logger

from talos.models import PanelApp
from talos.native_run_filtering import (
    MISSING_STRING,
    PATHOGENIC,
    annotate_clinvar_for_variant,
    apply_info_annotations,
    extract_bcsq_fields,
    format_csq,
    normalise_float,
    parse_bcsq_entries,
    prepare_writer,
)
from talos.utils import read_json_from_path


def cli_main():
    parser = ArgumentParser(description='Reformat and label mitochondrial VCF records without Hail')
    parser.add_argument('--input', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--panelapp', required=True)
    parser.add_argument('--pedigree', required=False)
    parser.add_argument('--clinvar', required=True)
    args = parser.parse_args()
    main(
        vcf_path=args.input,
        output_path=args.output,
        panelapp_path=args.panelapp,
        clinvar_path=args.clinvar,
    )


def main(vcf_path: str, output_path: str, panelapp_path: str, clinvar_path: str) -> None:
    panel_data = read_json_from_path(panelapp_path, return_model=PanelApp)
    symbol_to_ensg = {gene.symbol: ensg for ensg, gene in panel_data.genes.items() if gene.chrom.startswith('M')}
    green_genes = set(symbol_to_ensg.values())

    reader = VCF(vcf_path)
    clinvar_reader = VCF(clinvar_path)
    writer = prepare_writer(reader, output_path)
    bcsq_fields = extract_bcsq_fields(reader.raw_header)

    written = 0
    for variant in reader:
        if variant.FILTER and variant.FILTER not in {'PASS', '.'}:
            continue

        transcript_consequences = parse_bcsq_entries(variant, bcsq_fields, {variant.CHROM: symbol_to_ensg}, {})
        if not transcript_consequences:
            continue

        for transcript_consequence in transcript_consequences:
            transcript_consequence['mane_id'] = ''
            transcript_consequence['mane'] = ''
            transcript_consequence['ensp'] = ''
            transcript_consequence['am_class'] = ''
            transcript_consequence['am_pathogenicity'] = ''

        gene_ids = {str(entry['gene_id']) for entry in transcript_consequences if entry.get('gene_id')}
        if not gene_ids.intersection(green_genes):
            continue

        clinvar_info = annotate_clinvar_for_variant(variant, clinvar_reader)
        if clinvar_info['clinvar_significance'] != PATHOGENIC:
            continue

        for gene_id in sorted(gene_ids.intersection(green_genes)):
            gene_txs = [entry for entry in transcript_consequences if entry.get('gene_id') == gene_id]
            if not gene_txs:
                continue
            info_updates = {
                'gene_id': gene_id,
                'clinvar_significance': clinvar_info['clinvar_significance'],
                'clinvar_stars': clinvar_info['clinvar_stars'],
                'clinvar_allele': clinvar_info['clinvar_allele'],
                'clinvar_talos': 1,
                'categorybooleanclinvarplp': 1,
                'categorybooleanclinvar0star': int(clinvar_info['clinvar_stars'] == 0),
                'categorybooleanclinvar0starnewgene': 0,
                'categorybooleanalphamissense': 0,
                'categorybooleanhighimpact': 0,
                'categorybooleanspliceai': 0,
                'categorybooleanavi': 0,
                'categorysampledenovo': MISSING_STRING,
                'categorydetailspm5': MISSING_STRING,
                'categorydetailsexomiser': MISSING_STRING,
                'gnomad_AC': 0,
                'gnomad_AF': normalise_float(variant.INFO.get('gnomad_AF_joint')),
                'gnomad_AC_XY': 0,
                'gnomad_HomAlt': 0,
                'CSQ': format_csq(gene_txs),
            }
            apply_info_annotations(variant, info_updates)
            writer.write_record(variant)
            written += 1

    clinvar_reader.close()
    writer.close()
    reader.close()
    logger.info(f'Wrote {written} labelled mitochondrial records to {output_path}')


if __name__ == '__main__':
    cli_main()

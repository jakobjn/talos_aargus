"""
Native small-variant filtering and categorisation without Hail.
"""

from __future__ import annotations

import json
import re
from argparse import ArgumentParser
from collections import defaultdict
from pathlib import Path
from typing import Any

from cyvcf2 import VCF, Writer
from loguru import logger
from mendelbrot.bcftools_interpreter import TYPES_RE, classify_change
from mendelbrot.pedigree_parser import PedigreeParser

from talos.config import config_retrieve
from talos.models import PanelApp
from talos.utils import HETALT, HOMALT, NON_HOM_CHROM, read_json_from_path

MISSING_INT = 0
MISSING_STRING = 'missing'
PATHOGENIC = 'Pathogenic/Likely Pathogenic'
BENIGN = 'benign'
ADDITIONAL_CSQ_DEFAULT = ['missense', 'inframe_deletion', 'inframe_insertion']
CRITICAL_CSQ_DEFAULT = [
    'frameshift',
    'splice_acceptor',
    'splice_donor',
    'start_lost',
    'stop_gained',
    'stop_lost',
    'transcript_ablation',
]
INFO_IDS = {
    'gene_id',
    'clinvar_significance',
    'clinvar_stars',
    'clinvar_allele',
    'clinvar_talos',
    'categorybooleanclinvarplp',
    'categorybooleanclinvar0star',
    'categorybooleanclinvar0starnewgene',
    'categorybooleanalphamissense',
    'categorybooleanhighimpact',
    'categorybooleanspliceai',
    'categorybooleanavi',
    'categorysampledenovo',
    'categorydetailspm5',
    'categorydetailsexomiser',
    'gnomad_AC',
    'gnomad_AF',
    'gnomad_AC_XY',
    'gnomad_HomAlt',
}
INFO_HEADER_LINES = [
    ('gene_id', '1', 'String', 'Single gene ID assigned to this gene-specific Talos record'),
    ('clinvar_significance', '1', 'String', 'ClinvArbitration significance'),
    ('clinvar_stars', '1', 'Integer', 'ClinvArbitration gold stars'),
    ('clinvar_allele', '1', 'Integer', 'ClinvArbitration allele ID'),
    ('clinvar_talos', '1', 'Integer', 'Talos ClinVar override flag'),
    ('categorybooleanclinvarplp', '1', 'Integer', 'ClinVar pathogenic/likely pathogenic with stars'),
    ('categorybooleanclinvar0star', '1', 'Integer', 'ClinVar pathogenic/likely pathogenic with 0 stars'),
    ('categorybooleanclinvar0starnewgene', '1', 'Integer', '0-star ClinVar hit in a new PanelApp gene'),
    ('categorybooleanalphamissense', '1', 'Integer', 'AlphaMissense category'),
    ('categorybooleanhighimpact', '1', 'Integer', 'High-impact consequence category'),
    ('categorybooleanspliceai', '1', 'Integer', 'SpliceAI category'),
    ('categorybooleanavi', '1', 'Integer', 'AVI category'),
    ('categorysampledenovo', '1', 'String', 'Comma-delimited de novo sample IDs'),
    ('categorydetailspm5', '1', 'String', 'PM5 ClinVar allele details'),
    ('categorydetailsexomiser', '1', 'String', 'Exomiser details'),
    ('gnomad_AC', '1', 'Integer', 'gnomAD allele count'),
    ('gnomad_AF', '1', 'Float', 'gnomAD allele frequency'),
    ('gnomad_AC_XY', '1', 'Integer', 'gnomAD XY allele count'),
    ('gnomad_HomAlt', '1', 'Integer', 'gnomAD homozygous alternate count'),
]


def parse_args():
    parser = ArgumentParser(description='Filter and classify annotated VCFs without Hail')
    parser.add_argument('--input', nargs='+', required=True)
    parser.add_argument('--panelapp', required=True)
    parser.add_argument('--pedigree', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--clinvar', required=True)
    parser.add_argument('--pm5', required=True)
    parser.add_argument('--gene_bed', required=True)
    parser.add_argument('--mane', required=True)
    return parser.parse_args()


def extract_bcsq_fields(vcf_header: str) -> list[str]:
    match = re.search(r'ID=BCSQ.*?Format: ([^"]+)', vcf_header)
    if not match:
        raise ValueError('BCSQ header not found in input VCF')
    return [field.strip().lower() for field in match.group(1).split('|')]


def load_gene_map(bed_file: str) -> dict[str, dict[str, str]]:
    gene_map: dict[str, dict[str, str]] = defaultdict(dict)
    with open(bed_file) as handle:
        for line in handle:
            if line.startswith('#'):
                continue
            chrom, _start, _end, details = line.rstrip().split('\t')
            ensg, symbol = details.split(';')
            gene_map[chrom][symbol] = ensg
    return dict(gene_map)


def load_mane(mane_file: str) -> dict[str, dict[str, str]]:
    with open(mane_file) as handle:
        return json.load(handle)


def normalise_float(value: Any, default: float = 0.0) -> float:
    if value is None:
        return default
    if isinstance(value, (list, tuple)):
        value = value[0] if value else default
    if value == '.':
        return default
    return float(value)


def normalise_int(value: Any, default: int = 0) -> int:
    if value is None:
        return default
    if isinstance(value, (list, tuple)):
        value = value[0] if value else default
    if value == '.':
        return default
    return int(value)


def stringify_info(value: Any) -> str:
    if value is None:
        return MISSING_STRING
    if isinstance(value, float) and value.is_integer():
        return str(int(value))
    return str(value)


def parse_bcsq_entries(variant, bcsq_fields: list[str], gene_map: dict[str, dict[str, str]], mane: dict[str, dict[str, str]]):
    entries = variant.INFO.get('BCSQ')
    if not entries:
        return []
    raw_entries = entries if isinstance(entries, list) else [entries]
    transcripts: list[dict[str, Any]] = []
    for raw_entry in raw_entries:
        parts = str(raw_entry).split('|')
        while len(parts) < len(bcsq_fields):
            parts.append('')
        entry = {bcsq_fields[i]: parts[i] for i in range(len(bcsq_fields)) if bcsq_fields[i] != 'strand'}
        tx = entry.get('transcript', '')
        gene_symbol = entry.get('gene', '')
        mane_tx = mane.get(tx, {})
        amino_acid_change = entry.get('amino_acid_change', '')
        codon = ''
        if amino_acid_change and re.match(r'^([0-9]+).+$', amino_acid_change):
            codon = re.sub(r'^([0-9]+).+$', r'\1', amino_acid_change)
        transcripts.append(
            {
                'consequence': entry.get('consequence', ''),
                'gene_id': gene_map.get(variant.CHROM, {}).get(gene_symbol, gene_symbol),
                'gene': gene_symbol,
                'transcript': tx,
                'mane_id': mane_tx.get('mane_id', ''),
                'mane': mane_tx.get('mane_status', ''),
                'biotype': entry.get('biotype', ''),
                'dna_change': entry.get('dna_change', ''),
                'amino_acid_change': amino_acid_change,
                'codon': codon,
                'ensp': mane_tx.get('ensp', ''),
                'am_class': entry.get('transcript', '') == stringify_info(variant.INFO.get('am_transcript')) and stringify_info(variant.INFO.get('am_class')) or '',
                'am_pathogenicity': (
                    normalise_float(variant.INFO.get('am_score'))
                    if entry.get('transcript', '') == stringify_info(variant.INFO.get('am_transcript'))
                    else ''
                ),
            },
        )
    return transcripts


def format_csq(transcript_consequences: list[dict[str, Any]]) -> str:
    csq_fields = config_retrieve(['RunHailFiltering', 'csq_string'])
    formatted = []
    for consequence in transcript_consequences:
        row = []
        for field in csq_fields:
            value = consequence.get(field, '')
            row.append(str(value).replace(',', '&'))
        formatted.append('|'.join(row))
    return ','.join(formatted)


def consequence_is_relevant(consequence: dict[str, Any], allowed_terms: set[str]) -> bool:
    if consequence.get('biotype') == 'snRNA':
        return True
    return len(set(str(consequence.get('consequence', '')).split('&')).intersection(allowed_terms)) > 0


def consequence_is_high_impact(consequence: dict[str, Any], critical_terms: set[str]) -> bool:
    return len(set(str(consequence.get('consequence', '')).split('&')).intersection(critical_terms)) > 0


def collect_new_genes(panelapp: PanelApp) -> set[str]:
    return {ensg for ensg, data in panelapp.genes.items() if data.new}


def annotate_clinvar_for_variant(variant, clinvar_reader: VCF) -> dict[str, Any]:
    matches = list(clinvar_reader(f'{variant.CHROM}:{variant.POS}-{variant.POS}'))
    for candidate in matches:
        if candidate.REF != variant.REF or list(candidate.ALT) != list(variant.ALT):
            continue
        significance = (
            candidate.INFO.get('clinical_significance')
            or candidate.INFO.get('CLINICAL_SIGNIFICANCE')
            or candidate.INFO.get('significance')
            or MISSING_STRING
        )
        stars = normalise_int(candidate.INFO.get('gold_stars') or candidate.INFO.get('GOLD_STARS'))
        allele_id = normalise_int(candidate.INFO.get('allele_id') or candidate.INFO.get('ALLELE_ID'))
        return {
            'clinvar_significance': stringify_info(significance),
            'clinvar_stars': stars,
            'clinvar_allele': allele_id,
        }
    return {
        'clinvar_significance': MISSING_STRING,
        'clinvar_stars': 0,
        'clinvar_allele': 0,
    }


def load_pm5_lookup(pm5_tsv: str) -> dict[str, list[str]]:
    pm5_lookup: dict[str, list[str]] = defaultdict(list)
    with open(pm5_tsv) as handle:
        for idx, line in enumerate(handle):
            line = line.strip()
            if not line:
                continue
            if idx == 0 and line.startswith('transcript\tcodon\tclinvar_alleles'):
                continue
            parts = line.split('\t')
            if len(parts) < 3:
                continue
            transcript, codon, clinvar_alleles = parts[:3]
            if not codon or not clinvar_alleles:
                continue
            pm5_lookup[f'{transcript}::{codon}'].extend(clinvar_alleles.split('+'))
    return dict(pm5_lookup)


def get_sample_index_map(vcf: VCF) -> dict[str, int]:
    return {sample: index for index, sample in enumerate(vcf.samples)}


def is_male(participant) -> bool:
    return participant.sex == 1


def get_genotype_type(variant, sample_idx: int) -> int:
    return int(variant.gt_types[sample_idx])


def get_gq(variant, sample_idx: int) -> int:
    if 'GQ' not in variant.FORMAT:
        return 999
    value = variant.format('GQ')[sample_idx]
    if hasattr(value, '__len__'):
        value = value[0]
    return int(value)


def get_dp(variant, sample_idx: int) -> int:
    if 'DP' in variant.FORMAT:
        value = variant.format('DP')[sample_idx]
        if hasattr(value, '__len__'):
            value = value[0]
        return int(value)
    if 'AD' in variant.FORMAT:
        values = variant.format('AD')[sample_idx]
        return int(sum(v for v in values if v >= 0))
    return 999


def find_de_novo_samples(variant, pedigree: PedigreeParser, sample_index: dict[str, int]) -> list[str]:
    de_novo_config = config_retrieve(['RunHailFiltering', 'de_novo'])
    min_depth = de_novo_config.get('min_depth', 5)
    max_depth = de_novo_config.get('max_depth', 1000)
    min_proband_gq = de_novo_config.get('min_proband_gq', 25)
    min_all_sample_gq = de_novo_config.get('min_all_sample_gq', 19)
    denovos: list[str] = []
    chrom = variant.CHROM.replace('chr', '')
    for participant in pedigree.participants.values():
        if not participant.is_affected or not participant.mother_id or not participant.father_id:
            continue
        if participant.sample_id not in sample_index:
            continue
        if participant.mother_id not in sample_index or participant.father_id not in sample_index:
            continue
        child_idx = sample_index[participant.sample_id]
        mother_idx = sample_index[participant.mother_id]
        father_idx = sample_index[participant.father_id]
        child_gt = get_genotype_type(variant, child_idx)
        mother_gt = get_genotype_type(variant, mother_idx)
        father_gt = get_genotype_type(variant, father_idx)
        if get_gq(variant, child_idx) < min_proband_gq:
            continue
        if min(get_gq(variant, mother_idx), get_gq(variant, father_idx)) < min_all_sample_gq:
            continue
        child_dp = get_dp(variant, child_idx)
        if child_dp < min_depth or child_dp > max_depth:
            continue
        is_candidate = False
        if chrom in {'M', 'MT'}:
            is_candidate = child_gt == HOMALT and mother_gt == 0
        elif chrom == 'Y':
            is_candidate = child_gt in {HETALT, HOMALT} and father_gt == 0
        elif chrom == 'X':
            if is_male(participant):
                is_candidate = child_gt in {HETALT, HOMALT} and mother_gt == 0 and father_gt == 0
            else:
                is_candidate = child_gt == HETALT and mother_gt == 0 and father_gt == 0
        else:
            is_candidate = child_gt == HETALT and mother_gt == 0 and father_gt == 0
        if is_candidate:
            denovos.append(participant.sample_id)
    return denovos


def ensure_output_headers(vcf_reader: VCF) -> None:
    for info_id, number, info_type, description in INFO_HEADER_LINES:
        if f'ID={info_id},' not in vcf_reader.raw_header:
            vcf_reader.add_info_to_header(
                {'ID': info_id, 'Description': description, 'Type': info_type, 'Number': number},
            )
    csq_contents = '|'.join(config_retrieve(['RunHailFiltering', 'csq_string']))
    if 'ID=CSQ,' not in vcf_reader.raw_header:
        vcf_reader.add_info_to_header(
            {'ID': 'CSQ', 'Description': f'Format: {csq_contents}', 'Type': 'String', 'Number': '.'},
        )


def prepare_writer(input_reader: VCF, output_path: str) -> Writer:
    ensure_output_headers(input_reader)
    return Writer(output_path, input_reader)


def apply_info_annotations(variant, info_updates: dict[str, Any]) -> None:
    for key in INFO_IDS:
        if key in variant.INFO:
            del variant.INFO[key]
    for key, value in info_updates.items():
        variant.INFO[key] = value


def classify_variants(
    input_paths: list[str],
    panelapp_path: str,
    pedigree_path: str,
    output_path: str,
    clinvar_path: str,
    pm5_path: str,
    gene_bed: str,
    mane_path: str,
) -> None:
    pedigree = PedigreeParser(pedigree_path)
    panelapp = PanelApp.model_validate(read_json_from_path(panelapp_path))
    green_genes = set(panelapp.genes)
    new_green_genes = collect_new_genes(panelapp)
    gene_map = load_gene_map(gene_bed)
    mane = load_mane(mane_path)
    pm5_lookup = load_pm5_lookup(pm5_path)
    allowed_terms = set(config_retrieve(['RunHailFiltering', 'critical_csq'], CRITICAL_CSQ_DEFAULT)) | set(
        config_retrieve(['RunHailFiltering', 'additional_csq'], ADDITIONAL_CSQ_DEFAULT),
    )
    critical_terms = set(config_retrieve(['RunHailFiltering', 'critical_csq'], CRITICAL_CSQ_DEFAULT))
    rare_af_threshold = config_retrieve(['RunHailFiltering', 'af_semi_rare'])
    af_threshold = config_retrieve(['RunHailFiltering', 'ac_threshold'], 0.01)
    min_ac_to_filter = config_retrieve(['ValidateMOI', 'min_callset_ac_to_filter'], 5)
    am_threshold = config_retrieve(['RunHailFiltering', 'am_pathogenicity'], 0.564)
    spliceai_threshold = config_retrieve(['RunHailFiltering', 'spliceai'], None)
    avi_threshold = config_retrieve(['RunHailFiltering', 'avi'], None)

    first_reader = VCF(input_paths[0])
    writer = prepare_writer(first_reader, output_path)
    first_reader.close()

    written = 0
    for input_path in input_paths:
        reader = VCF(input_path)
        ensure_output_headers(reader)
        bcsq_fields = extract_bcsq_fields(reader.raw_header)
        sample_index = get_sample_index_map(reader)
        clinvar_reader = VCF(clinvar_path)
        for variant in reader:
            transcript_consequences = parse_bcsq_entries(variant, bcsq_fields, gene_map, mane)
            gene_ids = {str(entry['gene_id']) for entry in transcript_consequences if entry.get('gene_id')}
            if not gene_ids.intersection(green_genes):
                continue

            clinvar_info = annotate_clinvar_for_variant(variant, clinvar_reader)
            significance = clinvar_info['clinvar_significance']
            if BENIGN in significance.lower() and clinvar_info['clinvar_stars'] > 0:
                continue
            clinvar_talos = int(significance == PATHOGENIC)

            ac = normalise_int(variant.INFO.get('AC'))
            af = normalise_float(variant.INFO.get('AF'))
            gnomad_af = normalise_float(variant.INFO.get('gnomad_AF_joint'))
            if not ((ac <= min_ac_to_filter or af < af_threshold) or clinvar_talos == 1):
                continue
            if not (gnomad_af < rare_af_threshold or clinvar_talos == 1):
                continue
            if variant.FILTER and variant.FILTER not in {'PASS', '.'} and clinvar_talos != 1:
                continue

            denovo_samples = find_de_novo_samples(variant, pedigree, sample_index)
            for gene_id in sorted(gene_ids.intersection(green_genes)):
                gene_txs = [
                    consequence
                    for consequence in transcript_consequences
                    if consequence.get('gene_id') == gene_id
                    and (
                        consequence.get('biotype') in {'protein_coding', 'snRNA'}
                        or str(consequence.get('mane_id', '')).startswith('NM')
                    )
                ]
                filtered_txs = [consequence for consequence in gene_txs if consequence_is_relevant(consequence, allowed_terms)]
                if not filtered_txs and clinvar_talos == 0:
                    continue

                category_highimpact = int(any(consequence_is_high_impact(tx, critical_terms) for tx in filtered_txs))
                category_alphamissense = int(
                    any(
                        isinstance(tx.get('am_pathogenicity'), float) and tx['am_pathogenicity'] >= am_threshold
                        for tx in filtered_txs
                    ),
                )
                category_spliceai = (
                    int(normalise_float(variant.INFO.get('splice_ai_delta')) >= spliceai_threshold)
                    if spliceai_threshold is not None and variant.INFO.get('splice_ai_delta') is not None
                    else 0
                )
                category_avi = (
                    int(normalise_float(variant.INFO.get('avi_score')) >= avi_threshold)
                    if avi_threshold is not None and variant.INFO.get('avi_score') is not None
                    else 0
                )
                category_clinvarplp = int(clinvar_talos == 1 and clinvar_info['clinvar_stars'] > 0)
                category_clinvar0star = int(clinvar_talos == 1 and clinvar_info['clinvar_stars'] == 0)
                category_clinvar0starnewgene = int(category_clinvar0star == 1 and gene_id in new_green_genes)

                pm5_entries: list[str] = []
                seen_pm5: set[str] = set()
                for tx in filtered_txs:
                    codon = str(tx.get('codon', ''))
                    transcript = str(tx.get('transcript', ''))
                    if not codon or not transcript or 'missense' not in str(tx.get('consequence', '')):
                        continue
                    for pm5_entry in pm5_lookup.get(f'{transcript}::{codon}', []):
                        allele_id = pm5_entry.split('::')[0]
                        if allele_id != str(clinvar_info['clinvar_allele']) and pm5_entry not in seen_pm5:
                            seen_pm5.add(pm5_entry)
                            pm5_entries.append(pm5_entry)

                if not any(
                    [
                        category_clinvarplp,
                        category_clinvar0star,
                        category_clinvar0starnewgene,
                        category_alphamissense,
                        category_highimpact,
                        category_spliceai,
                        category_avi,
                        denovo_samples,
                        pm5_entries,
                    ],
                ):
                    continue

                info_updates = {
                    'gene_id': gene_id,
                    'clinvar_significance': significance,
                    'clinvar_stars': clinvar_info['clinvar_stars'],
                    'clinvar_allele': clinvar_info['clinvar_allele'],
                    'clinvar_talos': clinvar_talos,
                    'categorybooleanclinvarplp': category_clinvarplp,
                    'categorybooleanclinvar0star': category_clinvar0star,
                    'categorybooleanclinvar0starnewgene': category_clinvar0starnewgene,
                    'categorybooleanalphamissense': category_alphamissense,
                    'categorybooleanhighimpact': category_highimpact,
                    'categorybooleanspliceai': category_spliceai,
                    'categorybooleanavi': category_avi,
                    'categorysampledenovo': ','.join(denovo_samples) if denovo_samples else MISSING_STRING,
                    'categorydetailspm5': '+'.join(pm5_entries) if pm5_entries else MISSING_STRING,
                    'categorydetailsexomiser': MISSING_STRING,
                    'gnomad_AC': normalise_int(variant.INFO.get('gnomad_AC_joint')),
                    'gnomad_AF': normalise_float(variant.INFO.get('gnomad_AF_joint')),
                    'gnomad_AC_XY': normalise_int(variant.INFO.get('gnomad_AC_joint_XY')),
                    'gnomad_HomAlt': normalise_int(variant.INFO.get('gnomad_HomAlt_joint')),
                    'CSQ': format_csq(filtered_txs),
                }
                apply_info_annotations(variant, info_updates)
                writer.write_record(variant)
                written += 1
        clinvar_reader.close()
        reader.close()

    writer.close()
    logger.info(f'Wrote {written} labelled variant records to {output_path}')


def cli_main():
    args = parse_args()
    classify_variants(
        input_paths=args.input,
        panelapp_path=args.panelapp,
        pedigree_path=args.pedigree,
        output_path=args.output,
        clinvar_path=args.clinvar,
        pm5_path=args.pm5,
        gene_bed=args.gene_bed,
        mane_path=args.mane,
    )


if __name__ == '__main__':
    cli_main()

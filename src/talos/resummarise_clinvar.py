#!/usr/bin/env python3

import logging
import re
import zoneinfo
from argparse import ArgumentParser
from collections import defaultdict
from collections.abc import Generator
from dataclasses import dataclass
from datetime import datetime
from enum import Enum

try:
    from loguru import logger
except ModuleNotFoundError:
    logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
    logger = logging.getLogger(__name__)

ASSEMBLY = 'Assembly'
GRCH37 = 'GRCh37'
GRCH38 = 'GRCh38'
BENIGN_SIGS = {'Benign', 'Likely benign', 'Benign/Likely benign', 'protective'}
PATH_SIGS = {
    'Pathogenic',
    'Likely pathogenic',
    'Pathogenic, low penetrance',
    'Likely pathogenic, low penetrance',
    'Pathogenic/Likely pathogenic',
}
UNCERTAIN_SIGS = {'Uncertain significance', 'Uncertain risk allele'}
NO_STAR_RATINGS: set[str] = {'no assertion criteria provided'}
MAJORITY_RATIO: float = 0.6
MINORITY_RATIO: float = 0.2
STRONG_REVIEWS: list[str] = ['practice guideline', 'reviewed by expert panel']
ORDERED_CONTIGS: dict[str, list[str]] = {
    GRCH38: [f'chr{x}' for x in list(range(1, 23))] + ['chrX', 'chrY', 'chrM', 'chrMT'],
    GRCH37: [*list(map(str, range(1, 23))), 'X', 'Y', 'M', 'MT'],
}
TSV_KEYS = ['contig', 'position', 'reference', 'alternate', 'clinical_significance', 'gold_stars', 'allele_id']
TIMEZONE = zoneinfo.ZoneInfo('Australia/Brisbane')
ACMG_THRESHOLD = datetime(year=2016, month=1, day=1, tzinfo=TIMEZONE)
VERY_OLD = datetime(year=1970, month=1, day=1, tzinfo=TIMEZONE)
LARGEST_COMPLEX_INDELS = 40
BASES = re.compile(r'[ACGTN]+')
BLACKLIST: set[str] = set()


class Consequence(Enum):
    BENIGN = 'Benign'
    CONFLICTING = 'Conflicting'
    PATHOGENIC = 'Pathogenic/Likely Pathogenic'
    UNCERTAIN = 'VUS'
    UNKNOWN = 'Unknown'


QUALIFIED_BLACKLIST = [(Consequence.BENIGN, ['illumina laboratory services; illumina'])]


@dataclass
class Submission:
    date: datetime
    submitter: str
    classification: Consequence
    review_status: str


def dicts_from_gzip(filename: str) -> Generator[dict[str, str], None, None]:
    import gzip

    header: list[str] = []
    with gzip.open(filename, 'rt') as handle:
        for line in handle:
            if line.startswith('#'):
                header = line[1:].rstrip().split('\t')
                continue
            yield dict(zip(header, line.rstrip().split('\t'), strict=True))


def get_allele_locus_map(summary_file: str, assembly: str) -> dict[str, dict]:
    allele_dict = {}
    for line in dicts_from_gzip(summary_file):
        if line[ASSEMBLY] != assembly:
            continue
        chromosome = f'chr{line["Chromosome"]}' if assembly == GRCH38 else line['Chromosome']
        if chromosome == 'chrMT':
            chromosome = 'chrM'
        ref = line['ReferenceAlleleVCF']
        alt = line['AlternateAlleleVCF']
        if any(x == 'na' for x in [ref, alt]) or ref == alt:
            continue
        if chromosome not in ORDERED_CONTIGS[assembly]:
            continue
        if len(ref) + len(alt) > LARGEST_COMPLEX_INDELS:
            continue
        allele_id = int(line['AlleleID'])
        var_id = int(line['VariationID'])
        uniq_var_id = f'{chromosome}_{var_id}'
        pos = int(line['PositionVCF'])
        if BASES.match(ref) and BASES.match(alt):
            allele_dict[uniq_var_id] = {
                'var_id': var_id,
                'allele': allele_id,
                'chrom': chromosome,
                'pos': pos,
                'ref': ref,
                'alt': alt,
            }
    return allele_dict


def consequence_decision(subs: list[Submission]) -> Consequence:
    decision = Consequence.UNCERTAIN
    counts = {
        Consequence.BENIGN: 0,
        Consequence.PATHOGENIC: 0,
        Consequence.UNCERTAIN: 0,
        Consequence.UNKNOWN: 0,
        'total': 0,
    }
    for each_sub in subs:
        if each_sub.review_status in STRONG_REVIEWS:
            return each_sub.classification
        counts['total'] += 1
        if each_sub.classification in counts:
            counts[each_sub.classification] += 1
    if counts[Consequence.PATHOGENIC] and counts[Consequence.BENIGN]:
        if (max(counts[Consequence.PATHOGENIC], counts[Consequence.BENIGN]) >= (counts['total'] * MAJORITY_RATIO)) and (
            min(counts[Consequence.PATHOGENIC], counts[Consequence.BENIGN]) <= (counts['total'] * MINORITY_RATIO)
        ):
            decision = Consequence.BENIGN if counts[Consequence.BENIGN] > counts[Consequence.PATHOGENIC] else Consequence.PATHOGENIC
        else:
            decision = Consequence.CONFLICTING
    elif counts[Consequence.UNKNOWN] > (counts['total'] * MAJORITY_RATIO):
        decision = Consequence.UNKNOWN
    elif counts[Consequence.UNCERTAIN] > (counts['total'] * MAJORITY_RATIO):
        decision = Consequence.UNCERTAIN
    elif counts[Consequence.PATHOGENIC]:
        decision = Consequence.PATHOGENIC
    elif counts[Consequence.BENIGN]:
        decision = Consequence.BENIGN
    return decision


def check_stars(subs: list[Submission]) -> int:
    minimum = 0
    for sub in subs:
        if sub.classification in (Consequence.UNCERTAIN, Consequence.UNKNOWN):
            continue
        if sub.review_status == 'practice guideline':
            minimum = 4
        if sub.review_status == 'reviewed by expert panel':
            minimum = max(minimum, 3)
        if sub.review_status not in NO_STAR_RATINGS:
            minimum = max(minimum, 1)
    return minimum


def process_submission_line(data: dict[str, str]) -> tuple[int, Submission]:
    var_id = int(data['VariationID'])
    if data['ClinicalSignificance'] in PATH_SIGS:
        classification = Consequence.PATHOGENIC
    elif data['ClinicalSignificance'] in BENIGN_SIGS:
        classification = Consequence.BENIGN
    elif data['ClinicalSignificance'] in UNCERTAIN_SIGS:
        classification = Consequence.UNCERTAIN
    else:
        classification = Consequence.UNKNOWN
    date = datetime.strptime(data['DateLastEvaluated'], '%b %d, %Y').replace(tzinfo=TIMEZONE) if data['DateLastEvaluated'] != '-' else VERY_OLD
    sub = data['Submitter'].lower()
    rev_status = data['ReviewStatus'].lower()
    return var_id, Submission(date, sub, classification, rev_status)


def get_all_decisions(submission_file: str, var_ids: set[int]) -> dict[int, list[Submission]]:
    submission_dict = defaultdict(list)
    for line in dicts_from_gzip(submission_file):
        var_id, line_sub = process_submission_line(line)
        if (var_id not in var_ids) or (line_sub.submitter in BLACKLIST) or (line_sub.classification == Consequence.UNKNOWN):
            continue
        skip = False
        for consequence, submitters in QUALIFIED_BLACKLIST:
            if line_sub.classification == consequence and line_sub.submitter in submitters:
                skip = True
                break
        if skip:
            continue
        submission_dict[var_id].append(line_sub)
    return submission_dict


def acmg_filter_submissions(subs: list[Submission]) -> list[Submission]:
    filtered = [sub for sub in subs if sub.date >= ACMG_THRESHOLD or sub.review_status in STRONG_REVIEWS]
    return filtered or subs


def sort_decisions(all_subs: list[dict], assembly: str) -> list[dict]:
    return sorted(all_subs, key=lambda x: (ORDERED_CONTIGS[assembly].index(x['contig']), x['position']))


def write_vcf(rows: list[dict], output_vcf: str, pm5_filter: bool = True) -> None:
    filtered = []
    for row in rows:
        ref, alt = row['alleles']
        if pm5_filter and not (
            row['clinical_significance'] == Consequence.PATHOGENIC.value
            and row['contig'] != 'chrM'
        ):
            continue
        filtered.append(row)

    header = [
        '##fileformat=VCFv4.2',
        f'##fileDate={datetime.now(tz=TIMEZONE).strftime("%Y%m%d")}',
        '##INFO=<ID=allele_id,Number=1,Type=Integer,Description="ClinVar allele identifier">',
        '##INFO=<ID=gold_stars,Number=1,Type=Integer,Description="ClinVar review stars">',
        '##INFO=<ID=clinical_significance,Number=1,Type=String,Description="ClinVar summary classification">',
        '#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO',
    ]

    with open(output_vcf, 'w', encoding='utf-8') as handle:
        for line in header:
            handle.write(line + '\n')
        for row in filtered:
            ref, alt = row['alleles']
            info = f'allele_id={row["allele_id"]};gold_stars={row["gold_stars"]};clinical_significance={row["clinical_significance"].replace(" ", "_")}'
            handle.write(f'{row["contig"]}\t{row["position"]}\t.\t{ref}\t{alt}\t.\tPASS\t{info}\n')

    logger.info(f'Wrote VCF to {output_vcf}')


def write_dicts_as_tsv(rows: list[dict], output_path: str) -> None:
    if not rows:
        raise ValueError('No ClinVar decisions present.')
    with open(output_path, 'w', encoding='utf-8') as tsv_file:
        tsv_file.write('\t'.join(TSV_KEYS) + '\n')
        for row in rows:
            ref, alt = row['alleles']
            row['reference'] = ref
            row['alternate'] = alt
            tsv_file.write('\t'.join(str(row[key]) for key in TSV_KEYS) + '\n')


def main(subs: str, variants: str, output_root: str, assembly: str, all_vcf: str | None = None) -> None:
    allele_map = get_allele_locus_map(variants, assembly)
    all_uniq_ids = {x['var_id'] for x in allele_map.values()}
    decision_dict = get_all_decisions(submission_file=subs, var_ids=all_uniq_ids)
    all_decisions = {}
    for var_id, submissions in decision_dict.items():
        filtered_submissions = acmg_filter_submissions(submissions)
        rating = Consequence.UNCERTAIN if not filtered_submissions else consequence_decision(filtered_submissions)
        stars = check_stars(filtered_submissions)
        all_decisions[var_id] = (rating, stars)

    complete_decisions = []
    for var_details in allele_map.values():
        var_id = var_details['var_id']
        if var_id not in all_decisions:
            continue
        complete_decisions.append(
            {
                'contig': var_details['chrom'],
                'position': var_details['pos'],
                'alleles': [var_details['ref'], var_details['alt']],
                'clinical_significance': all_decisions[var_id][0].value,
                'gold_stars': all_decisions[var_details['var_id']][1],
                'allele_id': var_details['allele'],
            },
        )

    complete_decisions_sorted = sort_decisions(complete_decisions, assembly=assembly)
    write_dicts_as_tsv(complete_decisions_sorted, output_path=f'{output_root}.tsv')
    if all_vcf:
        write_vcf(complete_decisions_sorted, all_vcf, pm5_filter=False)
    write_vcf(complete_decisions_sorted, f'{output_root}.vcf')


if __name__ == '__main__':
    parser = ArgumentParser(description='Generate ClinVar summary files without Hail/Spark')
    parser.add_argument('-s', required=True, help='submission_summary.txt.gz from NCBI')
    parser.add_argument('-v', required=True, help='variant_summary.txt.gz from NCBI')
    parser.add_argument('-o', required=True, help='output root, for TSV and pathogenic-only VCF')
    parser.add_argument('-b', nargs='+', default=[], help='sites to blacklist')
    parser.add_argument('--assembly', default='GRCh38', choices=[GRCH37, GRCH38], help='genome build to use')
    parser.add_argument('--all_vcf', default=None, help='if provided, write a VCF containing all entries')
    args = parser.parse_args()
    if args.b:
        BLACKLIST.update(args.b)
    main(subs=args.s, variants=args.v, output_root=args.o, assembly=args.assembly, all_vcf=args.all_vcf)

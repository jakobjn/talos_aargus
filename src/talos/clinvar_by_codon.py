#!/usr/bin/env python3

import logging
import re
from argparse import ArgumentParser
from collections import defaultdict

try:
    from loguru import logger
except ModuleNotFoundError:
    logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
    logger = logging.getLogger(__name__)

NUMBER_RE = re.compile(r'(\d+)\D+>(\d+)\D*')
TSV_KEYS = ['transcript', 'codon', 'clinvar_alleles']


def parse_tsv_into_dict(input_tsv: str) -> dict[str, set[str]]:
    clinvar_dict = defaultdict(set)
    with open(input_tsv, encoding='utf-8') as tsv_reader:
        for row in tsv_reader:
            tx, aa, aid, stars = row.rstrip().split('\t')
            match = NUMBER_RE.match(aa)
            if not match:
                continue
            if match.group(1) != match.group(2):
                continue
            aa_number = match.group(1)
            clinvar_key = f'{aid}::{stars}'
            transcript_key = f'{tx}::{aa_number}'
            clinvar_dict[transcript_key].add(clinvar_key)
    return clinvar_dict


def write_results_as_tsv(clinvar_dict: dict[str, set[str]], tsv_path: str) -> None:
    with open(tsv_path, 'w', encoding='utf-8') as tsv_writer:
        tsv_writer.write('\t'.join(TSV_KEYS) + '\n')
        for key, value in clinvar_dict.items():
            transcript_id, codon_number = key.split('::')
            tsv_writer.write(f'{transcript_id}\t{codon_number}\t{"+".join(sorted(value))}\n')
    logger.info(f'TSV written to {tsv_path}')


def main(input_tsv: str, output_root: str) -> None:
    clinvar_dict = parse_tsv_into_dict(input_tsv)
    tsv_path = f'{output_root}.tsv'
    write_results_as_tsv(clinvar_dict, tsv_path)
    logger.info(f'PM5 TSV ready at {tsv_path}')


if __name__ == '__main__':
    parser = ArgumentParser()
    parser.add_argument('-i', required=True, help='Path to the TSV')
    parser.add_argument('-o', required=True, help='Root to export PM5 TSV')
    args = parser.parse_args()
    main(input_tsv=args.i, output_root=args.o)

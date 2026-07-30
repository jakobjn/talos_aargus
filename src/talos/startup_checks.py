"""
Native startup checks for annotated VCF inputs and local resources.
"""

from __future__ import annotations

import sys
from argparse import ArgumentParser
from datetime import datetime
from os import getenv
from pathlib import Path
import re

import pendulum
from cyvcf2 import VCF
from cloudpathlib.anypath import to_anypath
from loguru import logger
from mendelbrot.pedigree_parser import PedigreeParser

from talos.config import config_check, config_retrieve

LOG_ERRORS: list[str] = []
CONFIG_ERRORS: list[str] = []
REQUIRED_INFO_FIELDS = {'AC', 'AF', 'AN', 'BCSQ', 'gnomad_AF_joint'}

SCHEMA = {
    'GeneratePanelData': {
        'default_panel': int,
        'panelapp': str,
    },
    'RunHailFiltering': {
        'ac_threshold': float,
        'additional_csq': list,
        'af_semi_rare': float,
        'callset_af_sv_recessive': float,
        'critical_csq': list,
        'minimum_depth': int,
        'csq_string': list,
        'de_novo': {
            'min_child_ab': float,
            'min_depth': int,
            'max_depth': int,
            'min_proband_gq': int,
            'min_alt_depth': int,
        },
    },
    'ValidateMOI': {
        'min_callset_ac_to_filter': int,
        'gnomad_max_af': float,
        'gnomad_sv_max_af': float,
        'callset_max_af': float,
        'callset_sv_max_af': float,
        'gnomad_max_homozygotes': int,
        'gnomad_max_hemizygotes': int,
        'dominant_gnomad_max_af': float,
        'dominant_gnomad_sv_max_af': float,
        'dominant_gnomad_max_ac': int,
        'dominant_gnomad_max_homozygotes': int,
        'dominant_callset_max_af': float,
        'dominant_callset_sv_max_af': float,
        'dominant_callset_max_ac': int,
        'clinvar_gnomad_max_af': float,
        'clinvar_dominant_gnomad_max_af': float,
        'clinvar_callset_max_af': float,
        'clinvar_dominant_callset_max_af': float,
        'ignore_categories': list,
        'support_categories': list,
        'phenotype_match': list,
    },
}
SCHEMA_OPTIONAL = {
    'GeneratePanelData': {
        'require_pheno_match': list,
        'forbidden_genes': list,
        'forced_panels': list,
        'manual_overrides': list,
        'within_x_months': int,
    },
    'ValidateMOI': {
        'ignore_categories': list,
        'support_categories': list,
        'phenotype_match': list,
    },
    'HPOFlagging': {
        'semantic_match': bool,
        'min_similarity': float,
    },
}


def check_vcfs(vcf_paths: list[str]) -> None:
    logger.info(f'Checking annotated VCF inputs: {vcf_paths}')
    all_samples: set[str] | None = None
    for each_path in vcf_paths:
        vcf_path = to_anypath(each_path)
        if not vcf_path.exists():
            LOG_ERRORS.append(f'VCF does not exist: {each_path}')
            continue
        try:
            reader = VCF(each_path)
        except Exception as exc:  # noqa: BLE001
            LOG_ERRORS.append(f'Could not open VCF {each_path}: {exc}')
            continue
        these_samples = set(reader.samples)
        if all_samples is None:
            all_samples = these_samples
        elif all_samples != these_samples:
            LOG_ERRORS.append(f'VCF {each_path} contains different samples')
            reader.close()
            continue
        missing_info = [field for field in REQUIRED_INFO_FIELDS if f'ID={field},' not in reader.raw_header]
        if missing_info:
            LOG_ERRORS.append(f'VCF {each_path} is missing required INFO headers: {", ".join(missing_info)}')
        if 'ID=BCSQ,' not in reader.raw_header:
            LOG_ERRORS.append(f'VCF {each_path} is missing the BCSQ header description')
        reader.close()


def validate_pedigree(pedigree_path: str | None):
    if pedigree_path is None:
        LOG_ERRORS.append('Pedigree path is not provided.')
        return
    ped_path = to_anypath(pedigree_path)
    if not ped_path.exists():
        LOG_ERRORS.append(f'Pedigree file does not exist: {ped_path}')
        return
    try:
        pedigree = PedigreeParser(pedigree_path)
    except ValueError as exc:
        LOG_ERRORS.append(f'Error parsing pedigree file: {ped_path}\n{exc}')
        return
    if not pedigree.get_affected_member_ids():
        LOG_ERRORS.append(f'Pedigree file is empty or does not contain affected members: {ped_path}')


def recursive_schema_validation(schema: dict, lead: list[str] | None = None, optional: bool = False):
    if lead is None:
        lead = []
    for key, value in schema.items():
        if key not in config_retrieve(lead):
            if not optional:
                LOG_ERRORS.append(f'Missing required config key: {".".join([*lead, key])}')
            continue
        if isinstance(value, dict):
            recursive_schema_validation(schema=value, lead=[*lead, key], optional=optional)
            continue
        CONFIG_ERRORS.extend(config_check(key=[*lead, key], expected_type=value, optional=optional))


def check_config():
    if (config_path := getenv('TALOS_CONFIG')) is None:
        LOG_ERRORS.append('The TALOS_CONFIG environment variable is not set.')
        return
    if not Path(config_path).exists():
        LOG_ERRORS.append(f'TALOS_CONFIG points to a non-existent file: {config_path}')
        return
    recursive_schema_validation(schema=SCHEMA)
    recursive_schema_validation(schema=SCHEMA_OPTIONAL, optional=True)


def check_clinvar(clinvar_path: str) -> None:
    path = Path(clinvar_path)
    if not path.exists():
        LOG_ERRORS.append(f'ClinVar file does not exist: {clinvar_path}')
        return
    match = re.search(r'(\d{4}-\d{2})', path.name)
    if not match:
        logger.warning(f'Could not infer ClinVar month from filename: {path.name}')
        return
    created = pendulum.from_format(match.group(1), 'YYYY-MM')
    if created < pendulum.datetime(datetime.now().year, datetime.now().month, 1).subtract(months=2):
        LOG_ERRORS.append(f'ClinVar resource appears stale based on filename month: {path.name}')


def main(pedigree_path: str, vcf_paths: list[str], clinvar_path: str):
    check_config()
    validate_pedigree(pedigree_path)
    check_vcfs(vcf_paths)
    check_clinvar(clinvar_path)
    errors = [*LOG_ERRORS, *CONFIG_ERRORS]
    if errors:
        for error in errors:
            logger.error(error)
        sys.exit(1)
    logger.info('Startup checks completed successfully')


def cli_main():
    parser = ArgumentParser()
    parser.add_argument('--vcf', nargs='+', required=True)
    parser.add_argument('--pedigree', required=True)
    parser.add_argument('--clinvar', required=True)
    args = parser.parse_args()
    main(pedigree_path=args.pedigree, vcf_paths=args.vcf, clinvar_path=args.clinvar)


if __name__ == '__main__':
    cli_main()

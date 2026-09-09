from pathlib import Path

from talos.resummarise_clinvar import Consequence, write_vcf


def test_pathogenic_indels_are_written_to_annotation_vcf(tmp_path: Path):
    output_vcf = tmp_path / 'clinvarbitration.vcf'
    rows = [
        {
            'contig': 'chr1',
            'position': 100,
            'alleles': ['A', 'G'],
            'clinical_significance': Consequence.PATHOGENIC.value,
            'gold_stars': 1,
            'allele_id': 1,
        },
        {
            'contig': 'chr1',
            'position': 200,
            'alleles': ['AT', 'A'],
            'clinical_significance': Consequence.PATHOGENIC.value,
            'gold_stars': 1,
            'allele_id': 2,
        },
        {
            'contig': 'chr1',
            'position': 300,
            'alleles': ['C', 'CT'],
            'clinical_significance': Consequence.PATHOGENIC.value,
            'gold_stars': 1,
            'allele_id': 3,
        },
        {
            'contig': 'chr1',
            'position': 400,
            'alleles': ['C', 'T'],
            'clinical_significance': Consequence.BENIGN.value,
            'gold_stars': 1,
            'allele_id': 4,
        },
    ]

    write_vcf(rows, str(output_vcf))

    records = [line for line in output_vcf.read_text().splitlines() if not line.startswith('#')]
    assert len(records) == 3
    assert any('\t100\t.\tA\tG\t' in record for record in records)
    assert any('\t200\t.\tAT\tA\t' in record for record in records)
    assert any('\t300\t.\tC\tCT\t' in record for record in records)
    assert all('allele_id=4' not in record for record in records)

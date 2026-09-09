from pathlib import Path

from talos.clinvar_by_codon import parse_tsv_into_dict


def test_pm5_parser_accepts_same_codon_multi_amino_acid_changes(tmp_path: Path):
    input_tsv = tmp_path / "clinvar.annotated.tsv"
    input_tsv.write_text(
        "\n".join(
            [
                "ENST00000379370\t51VE>51V\t4866913\t1",
                "ENST00000379370\t76G>75S\t244110\t1",
                "ENST00000379370\t.\t2005563\t1",
            ],
        )
        + "\n",
    )

    result = parse_tsv_into_dict(str(input_tsv))

    assert result == {"ENST00000379370::51": {"4866913::1"}}

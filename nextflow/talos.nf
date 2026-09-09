#!/usr/bin/env nextflow

nextflow.enable.dsl=2

include { AnnotateMitoVcf } from './modules/talos/AnnotateMitoVcf/main'
include { UnifiedPanelAppParser } from './modules/talos/UnifiedPanelAppParser/main'
include { RunHailFiltering } from './modules/talos/RunHailFiltering/main'
include { ValidateMOI } from './modules/talos/ValidateMOI/main'
include { HPOFlagging } from './modules/talos/HPOFlagging/main'
include { CreateTalosHTML } from './modules/talos/CreateTalosHTML/main'
include { StartupChecks } from './modules/talos/StartupChecks/main'

def processedAnnotationPath(String name) {
    return file("${params.processed_annotations}/${name}")
}

workflow TALOS {
	take:
		ch_mane
		ch_gff
		ch_ref_genome
		ch_vcfs

    main:
    // existence of these files is necessary for starting the workflow
    // we open them as a channel, and pass the channel through to the method
    ch_hpo_file = channel.fromPath(params.hpo, checkIfExists: true).first()
    ch_gen2phen = channel.fromPath(params.gen2phen, checkIfExists: true).first()
    ch_phenio = channel.fromPath(params.phenio_db, checkIfExists: true).first()

    // current year-month as a String, used to prompt for up to date resource updates
    def current_month = new java.util.Date().format('yyyy-MM')
    def timestamp = new java.util.Date().format('yyyy-MM-dd')

    // check if clinvar and panelapp data exist using the timestamp
    String current_clinvarbitration_all = "${params.processed_annotations}/clinvarbitration_${current_month}.vcf.bgz"
    String current_clinvarbitration_pm5 = "${params.processed_annotations}/clinvarbitration_${current_month}.pm5.tsv"

    if (!file(current_clinvarbitration_pm5).exists()) {
        println "ClinvArbitration data for this month (${current_clinvarbitration_pm5}) doesn't exist, run the Talos Prep workflow"
        exit 1
    }

    // read in each Clinvar input source as channel
    ch_clinvar_all = channel.fromPath(current_clinvarbitration_all, checkIfExists: true).first()
    ch_clinvar_all_tbi = channel.fromPath("${current_clinvarbitration_all}.tbi", checkIfExists: true).first()
    ch_clinvar_pm5 = channel.fromPath(current_clinvarbitration_pm5, checkIfExists: true).first()
    ch_bed = channel.fromPath(processedAnnotationPath('GRCh38.bed'), checkIfExists: true).first()

    String panelapp_path = "${params.processed_annotations}/panelapp_${current_month}.json"

    if (!file(panelapp_path).exists()) {
        println "PanelApp data for this month (${panelapp_path}) doesn't exist, run the Talos Prep workflow"
        exit 1
    }
    ch_panelapp = channel.fromPath(panelapp_path, checkIfExists: true).first()

    // run pre-Talos startup checks
    StartupChecks(
        ch_vcfs,
        ch_clinvar_all,
    )

    // UnifiedPanelAppParser
    ch_panel_app_inputs = StartupChecks.out
        .join(ch_vcfs)
        .map { cohort, check_file, _vcfs, pedigree, config, _history, _ext, _seqr, _mito ->
            tuple(cohort, check_file, config, pedigree)
        }

    UnifiedPanelAppParser(
        ch_panel_app_inputs,
	ch_panelapp,
	ch_hpo_file,
    )

    ch_run_hail_inputs = ch_vcfs
        .join(UnifiedPanelAppParser.out)
        .join(StartupChecks.out)
        .map { cohort, vcfs, pedigree, config, _history, _ext, _seqr, _mito, panelapp_data, check_file ->
            tuple(cohort, vcfs, panelapp_data, check_file, pedigree, config)
        }

    RunHailFiltering(
        ch_run_hail_inputs,
        ch_clinvar_all,
        ch_clinvar_all_tbi,
        ch_clinvar_pm5,
        ch_bed,
        ch_mane,
    )

    // surprise! It's Mito data!
    ch_mito_joined = ch_vcfs
        .join(UnifiedPanelAppParser.out)
        .join(StartupChecks.out)
        .map { cohort, _vcfs, pedigree, config, _history, _ext, _seqr, mito, panelapp_data, check_file ->
          tuple(cohort, mito, panelapp_data, pedigree, config)
    }

    ch_mito_branched = ch_mito_joined.branch {
        real:     it[1].name != 'NO_MITO'
        sentinel: it[1].name == 'NO_MITO'
    }

    ch_mito_for_annotation = ch_mito_branched.real
        .map { cohort, mito, panelapp, ped, config ->
            tuple(cohort, mito, panelapp, ped, config,
                  file(processedAnnotationPath('mitimpact.zip'), checkIfExists: true),
                  file(processedAnnotationPath('mitotip.zip'), checkIfExists: true),
                  file(processedAnnotationPath('napogee.zip'), checkIfExists: true))
        }

    AnnotateMitoVcf(
        ch_mito_for_annotation,
        ch_ref_genome,
        ch_gff,
        ch_clinvar_all,
        ch_clinvar_all_tbi,
    )

    ch_mito_resolved = AnnotateMitoVcf.out
        .mix(ch_mito_branched.sentinel.map { cohort, mito, _pa, _ped, _cfg -> tuple(cohort, mito) })

    // Validate MOI of all variants
    ch_validate_moi_inputs = RunHailFiltering.out
        .join(UnifiedPanelAppParser.out)
        .join(ch_vcfs)
        .join(ch_mito_resolved)
        .map { cohort, labelled_vcf, labelled_vcf_index, panelapp_out, _vcfs, pedigree, config, history, _ext, _seqr, _mito, anno_mito ->
            tuple(cohort, labelled_vcf, labelled_vcf_index, anno_mito, panelapp_out, pedigree, config, history)
        }

    ValidateMOI(
        ch_validate_moi_inputs,
        timestamp,
    )

    // Flag any relevant HPO terms
    ch_hpo_inputs = ValidateMOI.out
        .join(ch_vcfs)
        .map { cohort, talos_result_json, _vcfs, _pedigree, config, _history, _ext, _seqr, _mito ->
            tuple(cohort, talos_result_json, config)
        }

    HPOFlagging(
        ch_hpo_inputs,
        ch_mane,
        ch_gen2phen,
        ch_phenio,
        timestamp,
    )

    // Generate HTML report
    ch_create_html_inputs = HPOFlagging.out
        .join(UnifiedPanelAppParser.out)
        .join(ch_vcfs)
        .map { cohort, result_json, panelapp_data, _vcfs, _pedigree, config, _history, ext, seqr, _mito ->
            tuple(cohort, result_json, panelapp_data, config, ext, seqr)
        }

    CreateTalosHTML(
        ch_create_html_inputs,
        timestamp,
    )

    emit:
	json = HPOFlagging.out
	html = CreateTalosHTML.out
	labelled = RunHailFiltering.out
	panelapp = UnifiedPanelAppParser.out
}


requiredParams = [
    params.project, params.genotypes_typed,
    params.genotypes_imputed, params.genotypes_build,
    params.genotypes_imputed_format, params.phenotypes_filename,
    params.phenotypes_columns, params.phenotypes_binary_trait,
    params.regenie_test
]

for (param in requiredParams) {
    if (param == null) {
      exit 1, "Please specify all required parameters."
    }
}

if(params.outdir == null) {
  outdir = "output/${params.project}"
} else {
  outdir = params.outdir
}

phenotypes_array = params.phenotypes_columns.trim().split(',')

covariates_array= []
if(!params.covariates_columns.isEmpty()){
  covariates_array = params.covariates_columns.trim().split(',')
}

gwas_report_template = file("$baseDir/reports/gwas_report_template.Rmd",checkIfExists: true)

//JBang scripts
regenie_log_parser_java  = file("$baseDir/bin/RegenieLogParser.java", checkIfExists: true)
regenie_filter_java = file("$baseDir/bin/RegenieFilter.java", checkIfExists: true)

//Annotation files
genes_hg19 = file("$baseDir/genes/genes.hg19.sorted.bed", checkIfExists: true)
genes_hg38 = file("$baseDir/genes/genes.hg38.sorted.bed", checkIfExists: true)

//Phenotypes
phenotype_file = file(params.phenotypes_filename, checkIfExists: true)
phenotypes = Channel.from(phenotypes_array)

//Covariates
covariate_file = file(params.covariates_filename)
if (params.covariates_filename != 'NO_COV_FILE' && !covariate_file.exists()){
  exit 1, "Covariate file ${params.covariates_filename} not found."
}

//Optional sample file
sample_file = file(params.regenie_sample_file)
if (params.regenie_sample_file != 'NO_SAMPLE_FILE' && !sample_file.exists()){
  exit 1, "Sample file ${params.regenie_sample_file} not found."
}

//Check specified test
if (params.regenie_test != 'additive' && params.regenie_test != 'recessive' && params.regenie_test != 'dominant'){
  exit 1, "Test ${params.regenie_test} not supported."
}

//Check imputed file format
if (params.genotypes_imputed_format != 'vcf' && params.genotypes_imputed_format != 'bgen'){
  exit 1, "File format ${params.genotypes_imputed_format} not supported."
}

//Array genotypes
Channel.fromFilePairs("${params.genotypes_typed}", size: 3).set {genotyped_plink_ch}

include { CACHE_JBANG_SCRIPTS      } from '../modules/local/cache_jbang_scripts'
include { VCF_TO_PLINK2            } from '../modules/local/vcf_to_plink2' addParams(outdir: "$outdir")
include { SNP_PRUNING              } from '../modules/local/snp_pruning'
include { QC_FILTER                } from '../modules/local/qc_filter'
include { REGENIE_STEP1            } from '../modules/local/regenie_step1'
include { REGENIE_LOG_PARSER_STEP1 } from '../modules/local/regenie_log_parser_step1'  addParams(outdir: "$outdir")
include { REGENIE_STEP2            } from '../modules/local/regenie_step2'
include { REGENIE_LOG_PARSER_STEP2 } from '../modules/local/regenie_log_parser_step2'  addParams(outdir: "$outdir")
include { FILTER_RESULTS           } from '../modules/local/filter_results'
include { MERGE_RESULTS_FILTERED   } from '../modules/local/merge_results_filtered'  addParams(outdir: "$outdir")
include { MERGE_RESULTS            } from '../modules/local/merge_results'  addParams(outdir: "$outdir")
include { TOPHITS                  } from '../modules/local/tophits'
include { ANNOTATE_TOPHITS         } from '../modules/local/annotate_tophits'  addParams(outdir: "$outdir")
include { REPORT                   } from '../modules/local/report'  addParams(outdir: "$outdir")

workflow GWAS_REGENIE {

    CACHE_JBANG_SCRIPTS (
        regenie_log_parser_java,
        regenie_filter_java
    )

    //convert vcf files to plink2 format (not bgen!)
    if (params.genotypes_imputed_format == "vcf"){
        imputed_files =  channel.fromPath("${params.genotypes_imputed}")

        VCF_TO_PLINK2 (
            imputed_files
        )

        imputed_plink2_ch = VCF_TO_PLINK2.out.imputed_plink2

    }  else {

        //no conversion needed (already BGEN), set input to imputed_plink2_ch channel
        channel.fromPath("${params.genotypes_imputed}")
        .map { tuple(it.baseName, it, file('dummy_a'), file('dummy_b')) }
        .set {imputed_plink2_ch}
    }


    if(params.prune_enabled) {

        SNP_PRUNING (
            genotyped_plink_ch
        )

        genotyped_plink_pruned_ch = SNP_PRUNING.out.genotypes_pruned

      } else {
          //no pruning applied, set raw genotyped directly to genotyped_plink_pruned_ch
          Channel.fromFilePairs("${params.genotypes_typed}", size: 3, flat: true).set {genotyped_plink_pruned_ch}
      }

    QC_FILTER (
        genotyped_plink_pruned_ch
    )

    if (!params.regenie_skip_predictions){

        REGENIE_STEP1 (
            genotyped_plink_pruned_ch,
            phenotype_file,
            QC_FILTER.out.genotyped_filtered,
            covariate_file
        )

        REGENIE_LOG_PARSER_STEP1 (
            REGENIE_STEP1.out.regenie_step1_out.collect(),
            CACHE_JBANG_SCRIPTS.out.regenie_log_parser_jar
        )

        regenie_step1_out_ch = REGENIE_STEP1.out.regenie_step1_out
        regenie_step1_parsed_logs_ch = REGENIE_LOG_PARSER_STEP1.out.regenie_step1_parsed_logs

    } else {

        regenie_step1_out_ch = Channel.of('/')

        regenie_step1_parsed_logs_ch = Channel.fromPath("NO_LOG")

    }

    REGENIE_STEP2 (
        regenie_step1_out_ch.collect(),
        imputed_plink2_ch,
        phenotype_file,
        sample_file,
        covariate_file
    )

    REGENIE_LOG_PARSER_STEP2 (
        REGENIE_STEP2.out.regenie_step2_log_out.collect(),
        CACHE_JBANG_SCRIPTS.out.regenie_log_parser_jar
    )

    FILTER_RESULTS (
        REGENIE_STEP2.out.regenie_step2_out.flatten(),
        CACHE_JBANG_SCRIPTS.out.regenie_filter_jar
    )

    MERGE_RESULTS_FILTERED (
        FILTER_RESULTS.out.results_filtered.collect(),
        phenotypes
    )

    MERGE_RESULTS (
        FILTER_RESULTS.out.results.collect(),
        phenotypes
    )

    TOPHITS (
        MERGE_RESULTS_FILTERED.out.results_filtered_merged
    )

    ANNOTATE_TOPHITS (
        TOPHITS.out.tophits_ch,
        genes_hg19,
        genes_hg38
    )

    REPORT (
        MERGE_RESULTS.out.results_merged,
        phenotype_file,
        gwas_report_template,
        regenie_step1_parsed_logs_ch.collect(),
        REGENIE_LOG_PARSER_STEP2.out.regenie_step2_parsed_logs
    )
}

workflow.onComplete {
    println "Pipeline completed at: $workflow.complete"
    println "Execution status: ${ workflow.success ? 'OK' : 'failed' }"
}

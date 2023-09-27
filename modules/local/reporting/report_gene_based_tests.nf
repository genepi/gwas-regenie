process REPORT_GENE_BASED_TESTS {

    publishDir "${params.pubDir}", mode: 'copy'

    input:
    tuple val(phenotype), path(regenie_merged)
    path phenotype_file_validated
    path gwas_report_template
    path r_functions_file
    path mask_file
    path rmd_pheno_stats_file
    path rmd_valdiation_logs_file
    path phenotype_log
    path covariate_log
    path step1_log
    path step2_log

    output:
    path "*.html"

    script:
    def annotation_as_string = params.manhattan_annotation_enabled.toString().toUpperCase()

    """
    Rscript -e "require( 'rmarkdown' ); render('${gwas_report_template}',
        params = list(
          project = '${params.project}',
          date = '${params.project_date}',
          version = '$workflow.manifest.version',
          regenie_merged='${regenie_merged}',
          regenie_filename='${regenie_merged.baseName}',
          phenotype_file='${phenotype_file_validated}',
          phenotype='${phenotype}',
          covariates='${params.covariates_columns}',
          condition_list='${params.regenie_condition_list}',
          phenotype_log='${phenotype_log}',
          covariate_log='${covariate_log}',
          regenie_step1_log='${step1_log}',
          regenie_step2_log='${step2_log}',
          plot_ylimit=${params.plot_ylimit},
          manhattan_annotation_enabled = $annotation_as_string,
          annotation_min_log10p = ${params.annotation_min_log10p},
          mask_file='${mask_file}',
          r_functions='${r_functions_file}',
          rmd_pheno_stats='${rmd_pheno_stats_file}',
          rmd_valdiation_logs='${rmd_valdiation_logs_file}'
        ),
      intermediates_dir='\$PWD',
      knit_root_dir='\$PWD',
      output_file='\$PWD/${params.project}.${regenie_merged.baseName}.html'
    )"
    """
}

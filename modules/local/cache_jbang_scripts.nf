process CACHE_JBANG_SCRIPTS {

  input:
    path regenie_log_parser_java
    path regenie_filter_java
    path regenie_validate_phenotypes_java

  output:
    path "RegenieLogParser.jar", emit: regenie_log_parser_jar
    path "RegenieFilter.jar", emit: regenie_filter_jar
    path "RegenieValidatePhenotypes.jar", emit: regenie_validate_phenotypes_jar

  """
  jbang export portable -O=RegenieLogParser.jar ${regenie_log_parser_java}
  jbang export portable -O=RegenieFilter.jar ${regenie_filter_java}
  jbang export portable -O=RegenieValidatePhenotypes.jar ${regenie_validate_phenotypes_java}
  """

}

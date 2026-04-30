# vcf-vep-annotation-pipeline

### Introduction 
This repository implements a variant annotation pipeline built around the Ensembl Variant Effect Predictor (VEP), with attention to a specific design question raised by the input data: how to handle a VCF whose two sample columns turn out not to be independent samples. The pipeline was developed against the given dataset, **input_vcf_data.vcf**, which features two sample columns labeled _normal_ and _vaf5_, with no accompanying documentation about their relationship. Inspection of the data using the **compare_samples.sh** script shows that the sample genotypes are the same across 99.97% of variants and ~75% of sample "FORMAT" columns are entirely identical. These and other descriptive statistics, along with the sample naming, suggest these are paired outputs from the same source, with *vaf5* representing a particular VAF sensitivity threshold and *normal* representing a standard tier. 

This pipeline writes a separate CSV for each sample to preserve the distinction between the two analytical views. As it stands, it omits MAF from the output as it is a population-level metric that requires multiple independent samples. This pipeline uses VEP's --pick parameter, which selects a single canonical transcript per variant according to VEP's pick order. This yields a flat, easy-to-filter output at the cost of discarding alternative transcript annotations and regulatory predictions; for clinical or research workflows requiring all transcript-level effects, --pick should be removed and the pipeline updated to emit one row per (variant, transcript) pair. 

The CSV output functions as a precursor for several downstream analytical functions, including:

* **Filtering and Aggregation**: narrowing thousands of variants into a shortlist for further analysis *or* rolling up variants across a particular category 
* **Statistical/ML Workflows**: treating each variant entry as a feature for model training
* **Visualization**: plotting variant distributions across the genome, mutation type breakdowns, etc.

### Data Inspection

Prior to annotation, **compare_samples.sh** inspects the descriptive statistics comparing the similarity of the two samples in the VCF input file, printing the results to the terminal interface. The high concordance between the two samples across most variant fields suggests they originate from a common source but were processed under different standards.

### Annotation Pipeline

The **run_annotation.sh** script first splits multiallelic variants into distinct lines to preserve each of their downstream annotations. As a preprocessing step, the pipeline strips the FORMAT/DPR field, which has a header inconsistency in the input VCF that prevents `bcftools` normalization from executing this split. Then, the script runs:

1. The VEP Docker container using a mounted GRCh37 cache to access VEP annotations.
2. The `bcftools` command line suite to extract relevant data fields.
3. A Python script *write_variant_csv.py* to reformat and save the final output to a CSV.

Note that while **compare_samples.sh** is hard-coded to inspect this particular VCF, **run_annotation.sh** can run across different inputs with any number of samples.

#### Pipeline Execution: [0] Installing Dependencies and Ensembl VEP Docker Image

Navigate to the *envs* folder and utilize the YML file to create an environment with the `bcftools` command line suite as well as the appropriate `pandas` package and Python version. 

```
conda env create -f vcf_vep_annotation_env.yml
conda activate vcf_vep_annotation_env
```

Ensembl provides specific documentation for installing the ensemblorg/ensembl-vep image [here](https://useast.ensembl.org/info/docs/tools/vep/script/vep_download.html#docker). Navigate to these guidelines or follow the installation described below.
```
# download ensembl-vep docker image
docker pull ensemblorg/ensembl-vep

# set up cache and fasta files; note that the VCF file specifies the GRCh37 assembly
docker run -t -i -v $HOME/vep_data:/data ensemblorg/ensembl-vep INSTALL.pl -a cf -s homo_sapiens -y GRCh37
```

#### Pipeline Execution: [1] Running Sample Comparison and Annotation Scripts

Ensure that the input VCF file is located in the repository's root directory. From this directory, first ensure that **compare_samples.sh** and **run_annotation.sh** are executable: ```chmod +x <filename>```. Each shell script can be run as follows: 

```
# compare sample statistics
./compare_samples.sh

# run the annotation pipeline 
./run_annotation.sh input_vcf_data.vcf
```

### Appendix

| CSV Column Name    | Description                                                                 | VCF Source                              |
| :----------------- | :-------------------------------------------------------------------------- | :-------------------------------------- |
| CHROM              | Chromosome containing the variant (e.g., chr1, chrX)                        | `CHROM`                                 |
| POS                | Genomic coordinate of the variant                                           | `POS`                                   |
| REF                | Reference allele at the variant position                                    | `REF`                                   |
| ALT                | Alternate allele observed at the variant position                           | `ALT`                                   |
| QUAL               | Per-site measure of variant caller confidence                               | `QUAL`                                  |
| GENOTYPE           | Sample genotype encoded as slash-separated allele indices                   | `FORMAT/GT`                             |
| DEPTH              | Total read depth at the variant locus                                       | `FORMAT/DP`                             |
| COUNT_REF          | Number of reads supporting the reference allele                             | `FORMAT/RO`                             |
| PERC_REF *         | Fraction of total reads supporting the reference allele                     | `FORMAT/RO ÷ FORMAT/DP`                 |
| COUNT_ALT          | Number of reads supporting the alternate allele                             | `FORMAT/AO`                             |
| PERC_ALT *         | Fraction of total reads supporting the alternate allele                     | `FORMAT/AO ÷ FORMAT/DP`                 |
| GENE_SYMBOL        | HGNC gene symbol associated with the selected transcript                    | `INFO/CSQ.SYMBOL`                       |
| GENE_ID            | Ensembl gene identifier (e.g., ENSG...) for the selected transcript         | `INFO/CSQ.Gene`                         |
| TRANSCRIPT_ID      | Ensembl transcript identifier (e.g., ENST...) for the selected transcript   | `INFO/CSQ.Feature`                      |
| VARIANT_CLASS      | Broad mutation category (e.g., SNV, insertion, deletion)                    | `INFO/CSQ.VARIANT_CLASS`                |
| BIOTYPE            | Transcript biotype (e.g., protein_coding, lncRNA, pseudogene)               | `INFO/CSQ.BIOTYPE`                      |
| CONSEQUENCE        | Predicted functional consequence(s) using Sequence Ontology terms           | `INFO/CSQ.Consequence`                  |
| IMPACT             | VEP-assigned impact rating (HIGH, MODERATE, LOW, MODIFIER)                  | `INFO/CSQ.IMPACT`                       |
| HGVSC              | HGVS coding DNA notation (e.g., c.123A>G)                                   | `INFO/CSQ.HGVSc`                        |
| HGVSP              | HGVS protein notation (e.g., p.Lys41Arg); blank for non-coding variants     | `INFO/CSQ.HGVSp`                        |
| EXISTING_VARIATION | Known external variant identifiers (e.g., dbSNP, COSMIC), comma-separated   | `INFO/CSQ.Existing_variation`           |

**PERC fields use FORMAT/DP as the denominator, which includes reads at the locus that the variant caller may not assign to any specific allele. As a result, PERC_REF + PERC_ALT can fall below 1 at certain loci and at multiallelic sites (now split across rows).*

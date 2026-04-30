#!/usr/bin/env bash

# [0] run checks / set up

set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "Usage: ./run_with_docker.sh <input_vcf>"
    exit 1
fi

mkdir -p ./temp

VEP_INPUT="$1"
VEP_OUTPUT_BASENAME="vep_annotated_output.vcf"
NORMALIZED_INPUT="./temp/normalized_input.vcf"

bcftools annotate -x FORMAT/DPR "${VEP_INPUT}" -O v | \
  bcftools norm -m- -O v -o "${NORMALIZED_INPUT}"

# [1] run VEP in docker

echo "Running VEP..."

docker run \
  -v "$HOME/vep_data":/data \
  -v "$PWD/temp":/input \
  -v "$PWD/temp":/output \
  ensemblorg/ensembl-vep \
    vep \
    --cache --offline \
    --assembly GRCh37 \
    --format vcf --vcf \
    --pick --everything \
    --force_overwrite \
    -i "/input/$(basename ${NORMALIZED_INPUT})" \
    -o "/output/${VEP_OUTPUT_BASENAME}"

# [2] split and query with BCFTools

echo "...VEP completed..."

for SAMPLE in $(bcftools query -l "./temp/${VEP_OUTPUT_BASENAME}"); do
    echo "Running bcftools and python on sample: ${SAMPLE} ... "

    BCF_OUTPUT_FILEPATH="./temp/bcftools_${SAMPLE}_output.tsv"

    bcftools +split-vep "./temp/${VEP_OUTPUT_BASENAME}" \
        -d \
        -c SYMBOL,Gene,Feature,VARIANT_CLASS,BIOTYPE,Consequence,IMPACT,HGVSc,HGVSp,Existing_variation  \
    | bcftools query \
        -H \
        -s "$SAMPLE" \
        -f '%CHROM\t%POS\t%REF\t%ALT\t%QUAL[\t%GT\t%DP\t%RO\t%AO]\t%SYMBOL\t%Gene\t%Feature\t%VARIANT_CLASS\t%BIOTYPE\t%Consequence\t%IMPACT\t%HGVSc\t%HGVSp\t%Existing_variation\n' \
        > "$BCF_OUTPUT_FILEPATH"

# [3] process with python
    python ./python/write_variant_csv.py "$BCF_OUTPUT_FILEPATH" "$SAMPLE"

    rm "$BCF_OUTPUT_FILEPATH"
done

echo "...annotation completed!"

rm "./temp/${VEP_OUTPUT_BASENAME}"
rm "./temp/${VEP_OUTPUT_BASENAME}_summary.html"
rm ${NORMALIZED_INPUT}

import pandas as pd
import sys
import argparse
import datetime
import pathlib
import re

### ### ###

date = datetime.datetime.today().strftime("%Y%b%d")

### ### ###
# check CLI usage and read in vcf tsv data

parser = argparse.ArgumentParser()
parser.add_argument ("filename", help = "input TSV file")
parser.add_argument ("sample_name", help = "sample name from VCF file")
args = parser.parse_args()

input_path = pathlib.Path (args.filename)
vcf_sample_name = args.sample_name

if not input_path.is_file() :
    print ("Invalid filepath.")
    sys.exit(1)

variant_df = pd.read_csv (input_path, sep = '\t')

# reformat column titles and select column values

def clean_column(col):
    col = re.sub(r'^#?\[\d+\]', '', col)    
    col = re.sub(rf'^{re.escape(vcf_sample_name)}:', '', col)  
    return col.upper()
variant_df.columns = [clean_column(c) for c in variant_df.columns]

readable_renames = {
    'DP':      'DEPTH',
    'RO':      'COUNT_REF',
    'AO':      'COUNT_ALT',
    'GT':      'GENOTYPE',
    'FEATURE': 'TRANSCRIPT_ID',
    'GENE':    'GENE_ID',
    'SYMBOL':  'GENE_SYMBOL',
}
variant_df = variant_df.rename(columns=readable_renames)

for item in ["BIOTYPE", "CONSEQUENCE", "VARIANT_CLASS", "EXISTING_VARIATION"] : 
    variant_df[item] = variant_df[item].str.upper()
numeric_cols = ["POS", "DEPTH", "COUNT_REF", "COUNT_ALT"]
variant_df[numeric_cols] = variant_df[numeric_cols].apply(pd.to_numeric, errors="coerce")
variant_df.insert (variant_df.columns.get_loc("COUNT_REF") + 1, "PERC_REF", (variant_df["COUNT_REF"]/variant_df["DEPTH"]).round(2) )
variant_df.insert (variant_df.columns.get_loc("COUNT_ALT") + 1, "PERC_ALT", (variant_df["COUNT_ALT"]/variant_df["DEPTH"]).round(2) )

# save dataframe as csv to results folder

variant_df = variant_df.fillna(".")

output_dir = pathlib.Path ("./results")
output_dir.mkdir (exist_ok = True)

variant_df.to_csv (
    pathlib.Path.joinpath (output_dir, f"annotated_{vcf_sample_name}_{date}.csv"), 
    index = False
)

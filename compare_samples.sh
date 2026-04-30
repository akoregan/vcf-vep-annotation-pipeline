#!/usr/bin/env bash

# Usage: ./compare_samples.sh

set -euo pipefail # error handling

VCF="input_vcf_data.vcf"

if [[ ! -f "$VCF" ]]; then
    echo "Error: file not found: $VCF" >&2
    exit 1
fi

if ! command -v bcftools &>/dev/null; then
    echo "Error: bcftools not found in PATH" >&2
    exit 1
fi

# FORMAT fields to compare across the two sample columns

FIELDS=(GT GQ DP DPR RO QR AO QA)

# Build a bcftools query format string that emits, per variant: <s1_GT>\t<s2_GT>\t<s1_GQ>\t<s2_GQ>\t...\n

QUERY=""
for f in "${FIELDS[@]}"; do
    QUERY+="[%${f}\t]"
done
QUERY="${QUERY%\\t}\n" # strip the final tab before new line

# run bcftools and pipe into awk

bcftools query -f "$QUERY" "$VCF" | awk -v fields="${FIELDS[*]}" '

BEGIN { n = split(fields, F, " ") } # field names in column order

{
    total++
    full_match = 1
    for (i = 1; i <= n; i++) {
        s1 = $((i - 1) * 2 + 1)
        s2 = $((i - 1) * 2 + 2)
        if (s1 == s2) {
            match_count[F[i]]++
        } else {
            full_match = 0
        }
    }
    if (full_match) full++
}

END { 
    printf "Total variants: %d\n\n", total
    printf "Samples with identical FORMAT fields: %d  (%.2f%%)\n\n", full, 100*full/total
    print  "Per-field agreement:"
    for (i = 1; i <= n; i++) {
        c = match_count[F[i]] + 0
        printf "  %-4s  %6d  (%.2f%%)\n", F[i], c, 100*c/total
    }
}

' # close awk script

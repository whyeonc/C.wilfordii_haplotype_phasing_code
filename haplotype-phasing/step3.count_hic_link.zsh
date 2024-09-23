#!/bin/bash
  
#count Hi-C links in 10 kb bins
samtools='/opt/Bio/samtools/1.16.1/bin/samtools'
bam='/filer-dg/agruppen/dg2/cho/cw/mapping/hic/hic.bam
  
{
$samtools view -q 10 -F 3332 $bam | cut -f -4 \
| awk 'old != $1 {old=$1; printf "\n"$0; next} {printf "\t"$0}' \
| awk -F '\t' 'NF == 8' | cut -f 3,4,7,8 \
| awk '{printf "%s\t%20d\t%s\t%20d\n", $1,1+($2 / 10000)*10000,$3,($4 / 10000)*10000}' \
| gzip > ${bam:r}_pairs.txt.gz &
}

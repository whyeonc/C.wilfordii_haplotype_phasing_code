#!/bin/zsh

#SBATCH --job-name=gmap
#SBATCH --auks=yes
#SBATCH --partition=cpu                                # possible values: cpu, gpu
#SBATCH --ntasks=1                                     # Number of tasks (default=1)
#SBATCH --cpus-per-task=15
#SBATCH --mem=50G
#SBATCH --nodes=1                                      # Ensure that all cores are on one machine
#SBATCH --output=job_%j.out                            # File to which standard out will be written
#SBATCH --error=job_%j.err

#projectdir="/filer-dg/agruppen/dg2/cho/chamomile/phased_assembly"

#Index construction

fasta='/filer-dg/agruppen/dg2/cho/cw/assembly/cw_hap_phased.hic.p_utg.fa'
gmap_build='/opt/Bio/gmap/2019-09-12/bin/gmap_build'
dir='/filer-dg/agruppen/dg2/cho/cw/assembly/gmap_index'
name='cw_hap_phased.hic.p_utg'
#$gmap_build $fasta -D $dir -d $name > ${name}_gmap_build.out  2> ${name}_gmap_build.err

#Alignment
gmap='/opt/Bio/gmap/2019-09-12/bin/gmap'
gmap_build='/opt/Bio/gmap/2019-09-12/bin/gmap_build'
#dir='$fasta:h'/gmap_index_v3
#name=${fasta:t:r}
threads=15
query='/filer-dg/agruppen/dg2/cho/cw/guide_map/cw_singlecopy_100bp.fasta'
prefix='cw_hap_phased'

$gmap -d $name -D $dir -t $threads -f 2 $query > ${prefix}.gff 2> ${prefix}.err  
grep mRNA $prefix.gff | cut -f 1,4,5,9 | tr ';' '\t' | cut -f 1-3,5,7-8 \
   | sed -e 's/coverage=//' -e 's/identity=//' -e 's/Name=//' > ${prefix}_table.txt 


#!/bin/bash

cd mapping

ref='/filer-dg/agruppen/dg7/cho/cw/assembly/cw_hap_phased.hic.p_utg.fa'
map='/filer-dg/agruppen/dg7/cho/cw/bitbucket/shell/run_hic_mapping_omni_tr.zsh'

$map --threads 20 --mem '600G' --ref $ref --tmp $TMPDIR hic

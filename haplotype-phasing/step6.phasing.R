#https://bitbucket.org/tritexassembly/tritexassembly.bitbucket.io/src/master/R/
source('/filer-dg/agruppen/seq_shared/mascher/code_repositories/triticeae.bitbucket.io/R/pseudomolecule_construction.R')

#read chromosome lengths of guide map
fread('/filer-dg/agruppen/dg2/cho/cw/guide_map/cw_final.fasta.fai', sel=1:2, col.names=c("chr", "len"))->fai

#read centromere positions
fread('/filer-dg/agruppen/dg2/cho/cw/cw_centromere_positions.tsv')->cen
setnames(cen, c("chr", "cen_pos"))

#read Hi-C mapping output (list of read pairs connecting RE fragments)
fread('/filer-dg/agruppen/dg2/cho/cw/mapping/hic/hic_fragment_pairs.tsv.gz')->f
setnames(f, c("ctg1", "pos1", "ctg2", "pos2"))

#read contig lengths of assebmbly
faif <- '/filer-dg/agruppen/dg2/cho/cw/assembly/cw_hap_phased.hic.p_utg.fa.fai'
fread(faif, sel=1:2, col.names=c("contig", "contig_length"))->fb

#read GMAP alignments of guide map genes
fread('/filer-dg/agruppen/dg2/cho/cw/assembly/gmap_index/cw_hap_phased_table.txt')->x
setnames(x, c("contig", "start", "end", "transcript", "alnlen", "id"))

#read position of genes in guide map assembly
fread('/filer-dg/agruppen/dg2/cho/cw/guide_map/cw_singlecopy_100bp.bed')->p
setnames(p, c("chr", "chr_start", "chr_end", "transcript"))

#read assembly object
readRDS('cw_assembly.Rds') -> assembly

##
# Positions contigs based on guide map
##

#keep only genes aligned for >= 80 % of their length with 90 % identity, allow up to two alignment (one per haplotype), modify for tetraploids
p[x, on="transcript"] -> px
px[alnlen >= 90 & id >= 97]->a
px[a[, .N, key=transcript][N <= 2]$transcript, on="transcript"]->aa

#convert original contig positions to corrected (assembly) positions 
assembly$info[, .(contig=orig_scaffold, start=orig_start, orig_start, scaffold)][aa, on=c("contig", "start"), roll=T] -> aa

#chromosome assignment
aa[, .N, key=.(chr, scaffold)][, p := N/sum(N), by=scaffold][order(-p)][!duplicated(scaffold)] -> cc

#keep contigs with at least 4 aligned genes, 75 % of aligned are from the major chromosome
cc[N >= 4 & p >= 0.75] -> cc

#check how much of the assembly can be assigned to chromosomes
assembly$info[, .(scaffold, scaffold_length=length)][cc, on="scaffold"] -> cc
cc[scaffold_length>=100000]->cc 

#get the approximate chromosome positions (median of alignment coordinates)
aa[cc[, .(scaffold, chr)], on=c("chr", "scaffold")][, .(pos=median(as.numeric(chr_start)), pos_mad=mad(as.numeric(chr_start))), key=scaffold][cc, on="scaffold"] -> cc
cc[, mr := pos_mad / scaffold_length]  
setorder(cc, chr, pos) 
cc[, chr_idx := 1:.N, by=chr]
cc[, agp_pos := c(0, cumsum(scaffold_length[-.N])), by=chr]

#save results
saveRDS(cc, file="cw_assembly_Hv_guide.Rds")

##
# Positioning additional contigs by Hi-C
## 

#load guide map positions
readRDS('cw_assembly_Hv_guide.Rds') -> cc
#get Hi-C links in the terminal 2 Mb of each scaffold
assembly$fpairs[, .(scaffold=scaffold1, pos=pos1, link=scaffold2)] -> ff
assembly$info[, .(scaffold, length)][ff, on="scaffold"] -> ff
ff[pos <= 2e6 | length - pos <= 2e6] -> ff
ff[scaffold != link] -> ff
ff[, .N, key=.(scaffold, link)] -> fa
#exclude scaffold-link paris with only a single Hi-C pair
fa[N > 1] -> fa
#add guide map positions
cc[, .(scaffold, scaffold_chr=chr, scaffold_pos=pos)][fa, on="scaffold"] -> fa
cc[, .(link=scaffold, link_chr=chr, link_pos=pos)][fa, on="link"] -> fa
#get approximate position based on Hi-C links
fa[!is.na(link_chr), .(n=sum(N), pos=weighted.mean(link_pos, N)), key=.(scaffold, scaffold_chr, scaffold_pos, link_chr)] -> fv
fv[, p := n/sum(n), by=scaffold]
assembly$info[, .(scaffold, length)][fv, on="scaffold"] -> fv
#get chromosome assignment for scaffolds without position in guide map
fv[is.na(scaffold_chr)][order(-p)][!duplicated(scaffold)][order(-length)] -> cc_lift0

#exclude contigs shorter than 100 kb
cc_lift0[length >= 1e5] -> cc_lift
#merge guide map and Hi-C lift tables; write output
rbind(cc[, .(scaffold, chr, pos)], cc_lift[, .(scaffold, chr=link_chr, pos)]) -> a
a[assembly_v2$info[, .(scaffold, length)], on="scaffold"] -> a
saveRDS(a, file="cw_assembly_Hv_guide+HiClift.Rds")


##
# Haplotype phasing
##

#read lengths of guide map chromosomes
fread('/filer-dg/agruppen/dg2/cho/cw/guide_map/cw_final.fasta.fai', sel=1:2, col.names=c("chr", "len"))->cwfai

#read centromere position in guide map
fread('/filer-dg/agruppen/dg2/cho/cw/cw_centromere_positions.tsv')->cen
setnames(cen, c("chr", "cen_pos"))

#read scaffold posiitions and add them to the Hi-C link table
readRDS(file="cw_assembly_Hv_guide.Rds") -> cc
assembly$fpairs[, .N, key=.(ctg1=scaffold1, ctg2=scaffold2)] -> v
cc[, .(ctg1=scaffold, chr1=chr, pos1=pos)][v, on="ctg1"] -> v
cc[, .(ctg2=scaffold, chr2=chr, pos2=pos)][v, on="ctg2"] -> v

#run a PCA on the intra-chromosomal matrices
rbindlist(mclapply(mc.cores=7, cwfai[1:11, chr], function(j){
 #fill in empty scaffold pairs with 0
 setnames(v[chr1 == chr2 & chr1 == j][, chr2 := NULL], "chr1", "chr") -> x
 dcast(x, ctg1 ~ ctg2, value.var="N", fill = 0) -> x
 melt(x, id="ctg1", measure=setdiff(names(x), "ctg1"), variable.factor=F, value.name="N", variable.name="ctg2") -> x
 x[, l := log10(0.1 + N)]
 cc[, .(ctg1=scaffold, chr, pos1=pos)][x, on="ctg1"] -> x
 cc[, .(ctg2=scaffold, pos2=pos)][x, on="ctg2"] -> x
 cwfai[x, on="chr"] -> x
 cen[x, on="chr"] -> x
 x[, end_dist1 := pmin(pos1, len - pos1)]
 x[, end_dist2 := pmin(pos2, len - pos2)]
 x[, cen_dist1 := abs(cen_pos - pos1)]
 x[, cen_dist2 := abs(cen_pos - pos2)]
 x[, ldist := abs(pos1 - pos2)]
 #get "normalized" Hi-C ounts by removing the factor linear distance between loci, distance from centromere and distance from chromosome end (all log scaled)
 x[, res := lm(l ~ log(1+ldist) * log(cen_dist1) * log(cen_dist2) * log(end_dist1) * log(end_dist2))$res]

 #convert to matrix
 dcast(x, ctg1 ~ ctg2, value.var="res", fill=0) -> y
 y[, ctg1 := NULL]
 #run PCA on correlation matrix
 prcomp(cor(y), scale=T, center=T)->pca
 #get first four eigenvector
 data.table(contig=rownames(pca$rotation), pca$rotation[, 1:4]) -> p
 setorder(cc[, .(contig=scaffold, chr, pos)][p, on="contig"], chr, pos) -> pp
 pp[, chr := j]
})) -> pp
assembly$info[, .(contig=scaffold, contig_length=length)][pp, on="contig"] -> pp
pp[, idx := 1:.N]
#save results
saveRDS(pp, file="cw_assembly_haplotype_separation_HiC.Rds")

#read coverage information and convert to correct assembly coordinates
fread(cmd="grep '^S' /filer-dg/agruppen/dg2/cho/cw/assembly/cw_hap_phased.hic.p_utg.gfa | cut -f 2,5 | tr ':' '\\t' | cut -f 1,4", head=F) -> cov
setnames(cov, c("contig", "cc"))
cov[, contig := sub('l$', '', sub("utg0*", "contig_", contig))]
assembly$info[, .(contig=orig_scaffold, scaffold)][cov, on=c("contig")] -> cov
setorder(cc[, .(scaffold, scaffold_length, chr, pos)][cov, on="scaffold"], chr, pos) -> cov
cov[, idx := 1:.N]
saveRDS(file="cw_assembly_cov.Rds", cov)

pp-> pq

#manually define cuts between haplotype for each chromosome
#2x contigs get "haplotype 3", i.e. present in both 1 and 2
cov[, .(contig=scaffold, cc)][pq, on="contig"] -> pq
pq[chr == "chr1" & PC1 > 0, hap := 1]
pq[chr == "chr1" & PC1 < 0, hap := 2]
pq[chr == "chr1" & cc >= 10, hap := 3]
pq[chr == "chr2" & PC1 > 0, hap := 1]
pq[chr == "chr2" & PC1 < 0, hap := 2]
pq[chr == "chr2" & cc >= 10, hap := 3]
pq[chr == "chr3" & PC1 > 0, hap := 1]
pq[chr == "chr3" & PC1 < 0, hap := 2]
pq[chr == "chr3" & cc >= 10, hap := 3]
pq[chr == "chr4" & PC1 > 0, hap := 1]
pq[chr == "chr4" & PC1 < 0, hap := 2]
pq[chr == "chr4" & cc >= 10, hap := 3]
pq[chr == "chr5" & PC1 > 0, hap := 1]
pq[chr == "chr5" & PC1 < 0, hap := 2]
pq[chr == "chr5" & cc >= 10, hap := 3]
pq[chr == "chr6" & PC1 > 0, hap := 1]
pq[chr == "chr6" & PC1 < 0, hap := 2]
pq[chr == "chr6" & cc >= 10, hap := 3]
pq[chr == "chr7" & PC1 > 0, hap := 1]
pq[chr == "chr7" & PC1 < 0, hap := 2]
pq[chr == "chr7" & cc >= 10, hap := 3]
pq[chr == "chr8" & PC1 > 0, hap := 1]
pq[chr == "chr8" & PC1 < 0, hap := 2]
pq[chr == "chr8" & cc >= 10, hap := 3]
pq[chr == "chr9" & PC1 > 0, hap := 1]
pq[chr == "chr9" & PC1 < 0, hap := 2]
pq[chr == "chr9" & cc >= 10, hap := 3]
pq[chr == "chr10" & PC1 > 0, hap := 1]
pq[chr == "chr10" & PC1 < 0, hap := 2]
pq[chr == "chr10" & cc >= 10, hap := 3]
pq[chr == "chr11" & PC1 > 0, hap := 1]
pq[chr == "chr11" & PC1 < 0, hap := 2]
pq[chr == "chr11" & cc >= 10, hap := 3]
pq[, col := "black"]
pq[hap == 1, col := "red"]
pq[hap == 2, col := "blue"]
pq[hap == 3, col := "purple"]

#plot results (PC1 score and coverage)
pdf("assembly_haplotype_separation_HiC.pdf", height=8, width=10)
par(mfrow=c(2, 1))
lapply(c("PC1"), function(j){
 lapply(cwfai[1:11, chr], function(i){
  pq[chr == i, plot(pos/1e6, las=1, bty='l', get(j), type='n', main=sub("chr", "", chr[1]), ylab="PC1",
        xlab="Hv syntenic position [Mb]", xlim=c(0, cwfai[i, len/1e6, on="chr"]))]
   pq[chr == i, lines(lwd=3, c(pos/1e6, (pos + contig_length)/1e6), c(PC1, PC1), col=col), by=idx]
  abline(v=c(0, cwfai[i, len/1e6, on="chr"]), col="blue")
  cov[chr == i, plot(pos/1e6, las=1, bty='l', cc, type='n', main=sub("chr", "", chr[1]), ylab="coverage",
        xlab="Hv syntenic position [Mb]", xlim=c(0, cwfai[i, len/1e6, on="chr"]))]
   cov[chr == i, lines(lwd=3, c(pos/1e6, (pos + scaffold_length)/1e6), c(cc, cc), col=1), by=idx]
 })
})

dev.off()

saveRDS(pq, file="cw_assembly_haplotype_separation_v0.Rds")


#Function to combine the Hi-C maps from two haplotypes
combine_hic <- function(hap1, hap2, assembly, species="cw_2X"){
 assembly <- assembly
 hic_map_v1_hap1 <- hap1
 hic_map_v1_hap2 <- hap2
 hic_map_v1_hap1$agp[agp_chr != "chrUn"] -> a1
 hic_map_v1_hap2$agp[agp_chr != "chrUn"] -> a2
 a1[, agp_chr := paste0(agp_chr, "_1")]
 a2[, agp_chr := paste0(agp_chr, "_2")]
 a1[, chr := NULL]
 a2[, chr := NULL]
 chrNames(agp=T, species)[, .(chr, agp_chr)][a1, on="agp_chr"] -> a1
 chrNames(agp=T, species)[, .(chr, agp_chr)][a2, on="agp_chr"] -> a2

 c(a1[scaffold != "gap"]$scaffold, a2[scaffold != "gap"]$scaffold) -> s
 s[duplicated(s)] -> s

 a1[s, on="scaffold", scaffold := paste0(scaffold, "_hap1")]
 a2[s, on="scaffold", scaffold := paste0(scaffold, "_hap2")]
 rbind(a1, a2) -> a
 
 hic_map_v1_hap1$chrlen[!is.na(chr)][, .(agp_chr=paste0(agp_chr, "_1"), length, truechr)] -> l1
 hic_map_v1_hap2$chrlen[!is.na(chr)][, .(agp_chr=paste0(agp_chr, "_2"), length, truechr)] -> l2
 rbind(l1, l2) -> l
 l[, offset := cumsum(c(0, length[1:(.N-1)]))]
 l[, plot_offset := cumsum(c(0, length[1:(.N-1)]+1e8))]
 chrNames(agp=T, species)[l, on="agp_chr"] -> l

 copy(assembly_v2$info) -> ai
 ai[!s, on="scaffold"] -> u
 ai[s, on="scaffold"][, scaffold := paste0(scaffold, "_hap1")] -> i1
 ai[s, on="scaffold"][, scaffold := paste0(scaffold, "_hap2")] -> i2
 rbind(u, i1, i2) -> i

 assembly$fpairs[, .(scaffold1, scaffold2, pos1, pos2)] -> f
 f[scaffold1 %in% s, scaffold1 := paste0(scaffold1, ifelse(runif(.N) > 0.5, "_hap1", "_hap2"))]
 f[scaffold2 %in% s, scaffold2 := paste0(scaffold2, ifelse(runif(.N) > 0.5, "_hap1", "_hap2"))]

 list(info=i, fpairs=f) -> assembly_hap
 list(agp=a, chrlen=l) -> hic_map
 list(assembly_hap=assembly_hap, hic_map=hic_map)
}

##
# Assign contigs that are not place in the guide map to haplotype using Hi-C
##

#read haplotype separation and guide map table
readRDS(file="cw_assembly_haplotype_separation_v0.Rds") -> pq
readRDS(file="cw_assembly_Hv_guide+HiClift.Rds") -> cc

readRDS('cw_assembly.Rds') -> assembly
readRDS('cw_assembly_cov.Rds') -> cov


#find and tabulate links between unplaced and placed con tigs
assembly$fpairs[, .(scaffold=scaffold1, pos=pos1, link=scaffold2)] -> ff
assembly$info[, .(scaffold, length)][ff, on="scaffold"] -> ff
ff[pos <= 2e6 | length - pos <= 2e6] -> ff
ff[scaffold != link] -> ff
ff[, .N, key=.(scaffold, link)] -> fa
fa[N > 1] -> fa
fa[scaffold %in% setdiff(cc$scaffold, pq$contig)] -> fa
fa[link %in% pq[hap %in% 1:2]$contig] -> fa
cc[, .(scaffold, scaffold_chr=chr, scaffold_pos=pos)][fa, on="scaffold"] -> fa
cc[, .(link=scaffold, link_chr=chr, link_pos=pos)][fa, on="link"] -> fa
pq[, .(link=contig, hap)][fa, on="link"] -> fa
fa[scaffold_chr == link_chr] -> fa
fa[, .(n=sum(N)), key=.(scaffold, chr=scaffold_chr, hap)] -> fv
fv[, p := n/sum(n), by=scaffold]
assembly$info[, .(scaffold, length)][fv, on="scaffold"] -> fv
fv[length >= 0][order(-p)][!duplicated(scaffold)][order(-length)] -> hap_lift0
cov[, .(scaffold, cc)][hap_lift0, on="scaffold"] -> hap_lift0

saveRDS(hap_lift0, file="cw_assembly_hap_lift0.Rds") 

#keep contigs unassigned to one haplotype OR contigs assigned to both haplotyped with double coverage
hap_lift0[p >= 0.8 | (p <= 0.55 & cc >= 36)] -> hap_lift

#keep onlt contigs >= 300 kb
hap_lift[length >= 3e5] -> hap_lift

#contigs assigned to both haplotype, get haplotype "3"
hap_lift[p <= 0.55, hap := 3]

#combine both haplotype tables
rbind(pq[, .(scaffold=contig, hap)],  hap_lift[, .(scaffold, hap)]) -> hh
hh[cc, on="scaffold"] -> hh
saveRDS(hh, file="cw_assembly_Hv_guide+HiClift+hap.Rds") 

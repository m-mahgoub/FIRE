library(tidyverse)
library(data.table)
library(scales)
library(ggforce)
library(cowplot)
library(dplyr)
#library(splitstackshape)
#library(ggridges)
#library(IRanges)
library(ggrepel)
#library(ggnewscale)
#library(ggside)
library(glue)
#library("tidylog", warn.conflicts = FALSE)
#library(patchwork)
#library(ggh4x)
library(tools)
#library(purrr)
#library(reticulate)
library(ggpubr)
#library(weights)
#library(karyoploteR)
#library(zoo)
library(scales)
library(ggplot2)
library(ggforce)
library(grid)

Red="#c1272d"
Indigo="#0000a7"
Yellow="#eecc16"
Teal="#008176"
Gray="#b3b3b3"
FONT_SIZE=8
MODEL_COLORS = c(PacBio=Indigo, 
    CNN=Red,  
    XGB=Yellow,
    GMM=Teal,
    IPD=Gray,
    SEMI="purple",
    Revio="#f41c90" # black
)

my_ggsave <- function(file, ...){
    file = glue(file)
    print(file)
    ext = file_ext(file)
    file_without_ext = tools::file_path_sans_ext(file)
    ggsave(glue("tmp.{ext}"), bg='transparent', ...)
    cmd = glue("cp tmp.{ext} {file}")
    fwrite(last_plot()$data, file=file_without_ext + ".tbl.gz", sep="\t")
    print(cmd)
    system(cmd)
}

my_grid = function(...){
    theme_minimal_grid(font_size=FONT_SIZE, ...)
} 

my_hgrid = function(...){
    theme_minimal_hgrid(font_size=FONT_SIZE, ...)
} 

my_vgrid = function(...){
    theme_minimal_vgrid(font_size=FONT_SIZE, ...)
} 

reverselog_trans <- function(base = exp(1)) {
    trans <- function(x) -log(x, base)
    inv <- function(x) base^(-x)
    trans_new(paste0("reverselog-", format(base)), trans, inv, 
              log_breaks(base = base), 
              domain = c(1e-100, Inf))
}

scientific_10 <- function(x) {
    is_one = as.numeric(x) == 1
    text = gsub("e", " %*% 10^", scales::scientific_format()(x))
    print(text)
    text = str_remove(text, "^1 %\\*% ") # remove leading one 
    print(text)
    text[is_one] = "10^0"
    rtn = parse(text=text)
    rtn
}

#
#
# SCRIPT
#
#
p_threshold=0.05
in_file=snakemake@input[[1]]
out_file_1=snakemake@output[[1]]
out_file_2=snakemake@output[[1]]
out_file_3=snakemake@output[[1]]

df=fread(in_file) %>%
    mutate_at(
        c("hap1_acc","hap2_acc","hap1_link","hap2_link","hap1_nuc","hap2_nuc"),
        as.numeric
    ) %>%
    data.table()
print(sapply(df, class))

# continue 
df$hap1_cov = df$hap1_acc + df$hap1_link + df$hap1_nuc
df$hap2_cov = df$hap2_acc + df$hap2_link + df$hap2_nuc
df$hap1_frac_acc = df$hap1_acc/df$hap1_cov
df$hap2_frac_acc = df$hap2_acc/df$hap2_cov
df$autosome = "Autosome"
df[`#ct` == "chrY"]$autosome = "chrY"
df[`#ct` == "chrX"]$autosome = "chrX"

print(head(df))

# filter by coverage
sd = 3
pdf = df %>%
    filter(hap1_cov > 0 & hap2_cov > 0) %>%
    mutate(
        id = seq(n()),
        min_cov = pmax(cov/2 - sd * sqrt(cov/2), 10),
        max_cov = cov/2 + sd * sqrt(cov/2),
    ) %>%
    filter(autosome != "chrY" ) %>%
    filter(hap1_cov > min_cov & hap2_cov > min_cov) %>%
    filter(hap1_cov < max_cov & hap2_cov < max_cov) %>%
    mutate(
        hap1_nacc = hap1_cov - hap1_acc,
        hap2_nacc = hap2_cov - hap2_acc,
    )

print(head(pdf))

pdf = pdf %>%
    rowwise() %>%
    mutate(
        p_value=fisher.test(matrix(c(hap1_acc, hap1_nacc, hap2_acc, hap2_nacc),nrow=2))$p.value
    ) %>%
    # group_by(sample) %>%
    mutate(
        p_adjust = p.adjust(p_value, method="BH"),
    ) %>%
    select(!starts_with("V")) %>%
    mutate(
        diff = hap1_frac_acc - hap2_frac_acc,
    ) %>%
    data.table()

print(head(pdf))

# make the plots
tdf = pdf 

tdf %>%
    ggplot(aes(x=hap1_frac_acc, y=hap2_frac_acc)) +
    stat_cor(size=2) +
    geom_hex(bins=75) +
    geom_abline(aes(intercept=0, slope=1), linetype="dashed")+
    scale_fill_distiller("", palette = "Spectral", trans="log10") +
    scale_x_continuous("Paternal accessibility", labels=percent) +
    scale_y_continuous("Maternal accessibility", labels=percent) +
    #annotation_logticks(sides="lb") +
    facet_wrap(~autosome, ncol=2)+
    my_grid()
my_ggsave(out_file_1, height=3, width=6)

cor_p_threshold = max(tdf[p_adjust <= p_threshold]$p_value)
y_lim = ceil( max(-log10(tdf$p_value)))
y_by = 1 
if(y_lim > 10){
    y_by = 2
}
# add p-value col, volcano plot
n=comma(nrow(tdf))
p = tdf %>%
    ggplot(aes(x=diff, y=p_value)) +
    geom_hex(bins=100) + scale_fill_distiller("", palette = "Spectral", trans="log10") +
    geom_hline(aes(yintercept=(p_threshold)), linetype="dashed", color="darkblue")+
    geom_hline(aes(yintercept=(cor_p_threshold)), linetype="dashed", color="darkred")+
    facet_wrap(~autosome, ncol=2)+
    scale_x_continuous("Difference between paternal and maternal accessibility", labels=percent) +
    scale_y_continuous(
        glue("p-value   (n = {n})"), 
        #labels=comma,
        breaks=10**(-seq(0, y_lim, y_by)),
        minor_breaks=10**(-seq(0, y_lim, 0.1)),
        trans=reverselog_trans(10),
        labels=scientific_10,
    ) + 
    my_grid()
my_ggsave(out_file_2, height=3, width=5)

# save the table 
fwrite(tdf, out_file_3, sep="\t")

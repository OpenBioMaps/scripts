#!/usr/bin/env Rscript
# Merge several csv files with non-identical headers
#
args = commandArgs(trailingOnly=TRUE)
form <- args[1]

files <- list.files(pattern = paste('form_',form,'_row_[0-9]+\\.csv',sep=''))

flist <- list()

n <- 1
for (i in files) {
    a <- read.csv2(i,sep=',',quote="'")
    if (n == 1) {
        df <- a
    } else {
        names.a <- colnames(a)
        names.df <- colnames(df)
        x <- setdiff(names.a, names.df)
        r <- setdiff(names.df, names.a)
        if (!identical(x, character(0))) {
            for (j in x) {
                df[j] <- ''
            }
        }
        if (!identical(r, character(0))) {
            for (j in r) {
                a[j] <- ''
            }
        }
        df <- rbind(df, a)
    }
    n <- n+1
}

write.csv(df,paste('form_',form,'.csv',sep=''))

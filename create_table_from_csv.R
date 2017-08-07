#!/usr/bin/env Rscript
# OpenBioMaps 
# an R script for creating SQL commands based on csv columns
# by Miki Bán, 2017 01 21
#
# Usage:
# Rscript --vanilla create_table_from_csv.R foo.csv
# ./create_table_from_csv.R --file foo.csv --sep , --quote \'

args = commandArgs(trailingOnly=TRUE)

if (length(args)==0) {
    stop("csv file name as argument must be supplied!", call.=FALSE)
} else if (length(args)==1) {
    # default output file
    csv.file <- args[1]
    csv.sep <- ','
    csv.quote <- '"'
} else if (length(args)>1) {
    csv.file <- args[1]
    csv.sep <- ','
    csv.quote <- '"'

    for (i in 1:length(args)) {
        if (args[i]=='-f' || args[i]=='--file') {
            csv.file <- args[i+1]
        }
        else if (args[i]=='-s' || args[i]=='--sep') {
            csv.sep <- args[i+1]
        }
        else if (args[i]=='-q' || args[i]=='--quote') {
            csv.quote <- args[i+1]
        }
    }
}

analyse <- function(col,counter,na.drop=T) {
    type <- class( col )
    flev <- length(levels(as.factor(col)))
    if (type == 'integer') {
        if (min(col,na.rm=T) == 0 && max(col,na.rm=T)==1) {
            type = 'boolen'
            return(type)
        } else {
            return('smallint')
        }
    } else if (type == 'numeric') {
        return('real')
    } else if (type == 'logical' && flev == 2 ) {
            type = 'boolen'
            return(type)
    } 
    
    if (type == 'factor' || type == 'logical') {
        # drop empty cells if na.action=''
        if (na.drop==T) {
            col <- droplevels(as.factor(col[col != ""]))
        }
        f.mod <- tryCatch({
            f.mod <- as.character(as.numeric(levels(col)))
        }, warning = function(war) {
            return(NA)
        })

        if (!anyNA(f.mod) && length(f.mod)) {
            f <- levels(col)
            if (all(tolower(f)==f.mod)) {
                # it is numeric
                y <- as.numeric(as.matrix(col))
                if (!isTRUE(all(y == floor(y)))) { 
                    type <- 'real'
                    return(type)
                } else {
                    type <- 'smallint'
                    return(type)
                }
            }
        } else {
            if ( flev == 2 ) {
                print(paste('Probably logical type at',i))
                print(levels(as.factor(col)))
            } else if (flev == 0) {
                print(paste('Empty column at',i))
                type <- 'text'
                return(type)
            } 
            #min(sapply(as.character(col),nchar))
            col.length <- tryCatch({
                col.length <- max(sapply(as.character(col),nchar),na.rm=T)
            }, error = function(err) {
                print(paste('STRING conversion error: ',err))
                return(256)

            })

            if (col.length<255) {
                type <- paste('character varying(',col.length,')',sep='')
                return(type)
            } else {
                type <- 'text'
                return(type)
            }
        }
    }
    return(type)
}



# RUN
cat ("",file="output.sql")

csv.data <- read.csv2(csv.file,header=T,sep=csv.sep,quote=csv.quote)

csv.sqlnames <- NULL
csv.names <- colnames(csv.data)
for (i in 1:ncol(csv.data)) {
    #csv.coltypes <- append(csv.coltypes,analyse( csv.data[,i],i ))
    sqltype <- analyse( csv.data[,i],i )
    name <- tolower(gsub("[^A-Za-z0-9]","_",csv.names[i]))
    csv.sqlnames <- append(csv.sqlnames,name)
    cat(paste('ALTER TABLE ',gsub("([A-Za-z0-9_]+).+",'\\1',csv.file),' ADD COLUMN ','"',name,'"',' ',sqltype,";\n",sep=""),file='output.sql',append=T)
}

if (length(unique(csv.sqlnames)) < length(csv.sqlnames)) {
    cat("\nWARNING! Non unique column names!")
    csv.sqlnames[duplicated(csv.sqlnames)]
}


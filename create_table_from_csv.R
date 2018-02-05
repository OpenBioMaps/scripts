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
    create_table <- F
    prefix <- ""
} else if (length(args)>1) {
    csv.file <- args[1]
    csv.sep <- ','
    csv.quote <- '"'
    create_table <- F
    prefix <- ""

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
        else if (args[i]=='-ct' || args[i]=='--create-table') {
            create_table <- T
        }
        else if (args[i]=='-p' || args[i]=='--prefix') {
            prefix <- args[i+1]
        }
    }
}

analyse <- function(col,cn,counter,na.drop=T) {
    type <- class( col )
    flev <- length(levels(as.factor(col)))
    if (type == 'integer') {
        if (min(col,na.rm=T) == 0 && max(col,na.rm=T)==1) {
            type = 'boolean'
            return(type)
        } else {
            return('smallint')
        }
    } else if (type == 'numeric') {
        return('real')
    } else if (type == 'logical' && flev == 2 ) {
            type = 'boolean'
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
            #if (all(tolower(f)==f.mod)) {
            #    # it is numeric
            #    y <- as.numeric(as.matrix(col))
            #    if (!isTRUE(all(y == floor(y)))) { 
            #        type <- 'real'
            #        return(type)
            #    } else {
            #        type <- 'smallint'
            #        return(type)
            #    }
            #} else {
                y <- as.numeric(as.matrix(col))
                if (!isTRUE(all(y == floor(y)))) { 
                    type <- 'real'
                    return(type)
                } else {
                    type <- 'smallint'
                    return(type)
                }

                # is not numeric, might be date
                isdate <- tryCatch({
                    isdate <- try(as.Date(col),silent=T)
                    if (!anyNA(isdate)){
                         isdate <- try(as.Date(col,format='%Y.%m.%d',silent=T))
                    }
                }, warning = function(w) {
                    return(NA)
                }, error = function(e){
                    return(NA)
                })

                if (!anyNA(isdate) && class(isdate)=='Date') {
                    type <- 'date'
                    return(type)
                }

                print(paste('Unrecognized factor column: ',cn,sep=''))
                return('text')
            #}
        } else {
            if ( flev == 2 && nchar(levels(as.factor(col))[1])<12 ) {
                print(paste('Probably logical type: ',cn,' (',levels(as.factor(col)),')',sep=''))
            } else if (flev == 0) {
                print(paste('Empty/unknown column: ',cn,sep=''))
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
                # might be date
                isdate <- tryCatch({
                    isdate <- try(as.Date(col),silent=T)
                    if (!anyNA(isdate)){
                         isdate <- try(as.Date(col,format='%Y.%m.%d',silent=T))
                    }
                }, warning = function(w) {
                    return(NA)
                }, error = function(e){
                    return(NA)
                })

                if (!anyNA(isdate) && class(isdate)=='Date') {
                    type <- 'date'
                    return(type)
                }
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
output_file <- gsub('\\.csv$','',csv.file)
if (prefix != '') {
    db <- prefix
    dbtable <- paste(prefix,output_file,sep='_')
} else {
    dbtable <- output_file
    db <- output_file
}

cat ("",file=paste(output_file,".sql",sep=''))

if (create_table) {
    cat(paste("--
-- OBM database create from csv
--

SET statement_timeout = 0;
SET lock_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;
SET search_path = public, pg_catalog;
SET default_tablespace = '';
SET default_with_oids = false;\n\n",sep=''),file=paste(output_file,".sql",sep=''),append=T)

    cat(paste('CREATE TABLE ',tolower(dbtable),"(\n",sep=""),file=paste(output_file,".sql",sep=''),append=T)

    cat(paste("    obm_id integer NOT NULL,
    obm_geometry geometry,
    obm_datum timestamp with time zone,
    obm_uploading_id integer,
    obm_validation numeric,
    obm_comments text[],
    obm_modifier_id integer,
    obm_files_id integer,
    CONSTRAINT enforce_dims_obm_geometry CHECK ((st_ndims(obm_geometry) = 2)),
    CONSTRAINT enforce_geotype_obm_geometry CHECK (((((geometrytype(obm_geometry) = 'POINT'::text) OR (geometrytype(obm_geometry) = 'LINE'::text)) OR (geometrytype(obm_geometry) = 'POLYGON'::text)) OR (obm_geometry IS NULL))),
    CONSTRAINT enforce_srid_obm_geometry CHECK ((st_srid(obm_geometry) = 4326))\n);\n"),file=paste(output_file,".sql",sep=''),append=T)


    cat(paste("
ALTER TABLE ",tolower(dbtable)," OWNER TO gisadmin;

--
-- Name: TABLE ",tolower(dbtable),"; Type: COMMENT; Schema: public; Owner: gisadmin
--

COMMENT ON TABLE ",tolower(dbtable)," IS 'user defined table:",Sys.info()['login'],"';

--
-- Name: ",tolower(dbtable),"_obm_id_seq; Type: SEQUENCE; Schema: public; Owner: gisadmin
--

CREATE SEQUENCE ",tolower(dbtable),"_obm_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER TABLE ",tolower(dbtable),"_obm_id_seq OWNER TO gisadmin;

--
-- Name: ",tolower(dbtable),"_obm_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: gisadmin
--

ALTER SEQUENCE ",tolower(dbtable),"_obm_id_seq OWNED BY ",tolower(dbtable),".obm_id;

--
-- Name: obm_id; Type: DEFAULT; Schema: public; Owner: gisadmin
--

ALTER TABLE ONLY ",tolower(dbtable)," ALTER COLUMN obm_id SET DEFAULT nextval('",tolower(dbtable),"_obm_id_seq'::regclass);

--
-- Name: ",tolower(dbtable),"_pkey; Type: CONSTRAINT; Schema: public; Owner: gisadmin; Tablespace: 
--

ALTER TABLE ONLY ",tolower(dbtable),"
    ADD CONSTRAINT ",tolower(dbtable),"_pkey PRIMARY KEY (obm_id);

--
-- Name: obm_uploading_id; Type: FK CONSTRAINT; Schema: public; Owner: gisadmin
--

ALTER TABLE ONLY ",tolower(dbtable),"
    ADD CONSTRAINT obm_uploading_id FOREIGN KEY (obm_uploading_id) REFERENCES uploadings(id);

--
-- Name: ",tolower(dbtable),"; Type: ACL; Schema: public; Owner: gisadmin
--

REVOKE ALL ON TABLE ",tolower(dbtable)," FROM PUBLIC;
REVOKE ALL ON TABLE ",tolower(dbtable)," FROM gisadmin;
GRANT ALL ON TABLE ",tolower(dbtable)," TO gisadmin;
GRANT ALL ON TABLE ",tolower(dbtable)," TO ",tolower(db),"_admin;

--
-- Name: ",tolower(dbtable),"_obm_id_seq; Type: ACL; Schema: public; Owner: gisadmin
--

REVOKE ALL ON SEQUENCE ",tolower(dbtable),"_obm_id_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE ",tolower(dbtable),"_obm_id_seq FROM gisadmin;
GRANT ALL ON SEQUENCE ",tolower(dbtable),"_obm_id_seq TO gisadmin;
GRANT SELECT,USAGE ON SEQUENCE ",tolower(dbtable),"_obm_id_seq TO ",tolower(db),"_admin;

--
-- OBM add processed columns
--    \n\n",sep=''),file=paste(output_file,".sql",sep=''),append=T)


}

csv.data <- read.csv2(csv.file,header=T,sep=csv.sep,quote=csv.quote)

csv.sqlnames <- NULL
csv.names <- colnames(csv.data)
for (i in 1:ncol(csv.data)) {
    #csv.coltypes <- append(csv.coltypes,analyse( csv.data[,i],i ))
    sqltype <- analyse( csv.data[,i],csv.names[i],i )
    name <- tolower(gsub("[^A-Za-z0-9]","_",csv.names[i]))
    csv.sqlnames <- append(csv.sqlnames,name)
    cat(paste('ALTER TABLE ',tolower(dbtable),' ADD COLUMN ','"',name,'"',' ',sqltype,";\n",sep=""),file=paste(output_file,".sql",sep=''),append=T)
}

if (length(unique(csv.sqlnames)) < length(csv.sqlnames)) {
    cat("\nWARNING! Non unique column names!")
    csv.sqlnames[duplicated(csv.sqlnames)]
}


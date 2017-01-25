# OpenBioMaps simplified api interface
# OAuth2 R client interface for OpenBioMaps PDS API
# By Miki Bán 2017.01.19
# banm@vocs.unideb.hu
# 
# PLEASE HELP:
# Is there anybody want to build a package from this? I have no time...
#
# Its done:
# https://github.com/OpenBioMaps/obm.r
# This version is deprecated

library(httr)
OBM <- new.env()

OBM_init <- function (project,domain='openbiomaps.org') {
    # set some default value
    OBM$token_url <- paste('http://',domain,'/oauth/token.php',sep='')
    OBM$pds_url <- paste('http://',domain,'/projects/',project,'/pds.php',sep='')
}

OBM_auth <- function (username='',password='',scope='get_form_data get_form_list get_profile get_data get_history',client_id='web',url=OBM$token_url,verbose=F) {
    if ( exists('token', envir=OBM) & exists('time', envir=OBM) & (username=='' & password=='')) {
        # auto refresh token 
        z <- Sys.time()
        timestamp <- unclass(z)
        e <- OBM$time + OBM$token$expires_in
        if (e < timestamp) {
            if (verbose) {
                print("Token expired, trying to refresh...")
            }
            # expired
            OBM_refresh_token(verbose=verbose)
        }
    } else {
        if (username=='' || password=='') {
            username <- readline(prompt="Enter username: ")
            password <- readline(prompt="Enter password: ")
        }
        h <- POST(url,body=list(grant_type='password',username=username,password=password,client_id=client_id,scope=scope))
        z <- Sys.time()
        j <- content(h, "parsed", "application/json")
        if (verbose) {
            print(j)
        }
        if (exists('access_token',j)) {
            OBM$token <- j
            OBM$time <- unclass(z)
        } else {
            if ( exists('token', envir=OBM) & !is.null(OBM$token) ) {
                rm(list=c('token'),envir=OBM)
            }
            if ( exists('time', envir=OBM)  & !is.null(OBM$time)) {
                rm(list=c('time'),envir=OBM)
            }
            print("Authentication failed.")
        }
    }
}

OBM_get <- function (scope='',condition='',token=OBM$token,url=OBM$pds_url) {
    if (scope=='' || condition == '') {
        return ("usage: OBM_get(scope,condition,...)")
    }
    if ( exists('token', envir=OBM) & exists('time', envir=OBM) ) {
        # auto refresh token 
        z <- Sys.time()
        timestamp <- unclass(z)
        e <- OBM$time + OBM$token$expires_in
        if (e < timestamp) {
            # expired
            OBM_refresh_token()
        }
    }
    h <- POST(url,body=list(access_token=token$access_token,scope=scope,value=condition),encode='form')
    h.list <- content(h, "parsed", "application/json")
    do.call("rbind", h.list)
}

OBM_refresh_token <- function(token=OBM$token,url=OBM$token_url,client_id='web',verbose=F) {
    h <- POST(url,body=list(grant_type='refresh_token',refresh_token=token$refresh_token,client_id=client_id))
    j <- content(h, "parsed", "application/json")
    if (exists('access_token',j)) {
        OBM$token <- j
        OBM$time <- unclass(z)
        if (verbose) {
            print(j)
        }
    } else {
        if ( exists('token', envir=OBM)  & !is.null(OBM$token)) {
            rm(list=c('token'),envir=OBM)
        }
        if ( exists('time', envir=OBM)  & !is.null(OBM$time)) {
            rm(list=c('time'),envir=OBM)
        }
        print("Authentication disconnected.")
        if (verbose) {
            print(j)
        }
    }
}


#### examples
# init dead_animals on openbiomaps.org
OBM_init('dead_animals')
# or init dead_animals on localhost
OBM_init('dead_animals','localhost/biomaps')

# authenticating - request token
token <- OBM_auth('ban.miklos@science.unideb.hu','secret123')
# or interactive authenticating
token <- OBM_auth()

# refresh token
# usually auto refreshed - not used
token <- OBM_refresh_token(token)

# get avilable forms from the default server
data <- OBM_get('get_form_list',0)

# other server
data <- OBM_get('get_form_list',0)
data <- OBM_get('get_form_data',13)

# get range of data from the main table 
data <- OBM_get('get_data','39980:39988')
# get data by query definition
data <- OBM_get('get_data','faj=Parus palustris')

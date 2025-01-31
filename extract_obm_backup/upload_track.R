
# obm R csomag telepítése

#library("devtools")
#install_github('OpenBioMaps/obm.r')

# inicializálás és authentikáció
library(obm)
obm_init('elc', 'https://milvus.openbiomaps.org')
obm_auth()

read.text <- function(pathname) {
    return (paste(readLines(pathname), collapse="\n"))
}

# adatfájl beolvasása
for (i in 0:4) {
    data <- read.text(paste0('./input/PaczaiOrs_obm_1675947869_',i))
    t <- obm_put(scope='tracklog', tracklog = data)
    print(t)
}




# ## INSTALL ANALYSIS PACKAGE
# library(devtools)
# install_github("bfatemi/isds")



## Set system environment variable to point to private key
Sys.setenv(USER_KEY = "~/.ssh/private.pk")

## LOAD PACKAGE AND RUN ANALYSIS
library(isds)
library(data.table)
library(stringr)
library(beanplot)

hID <- 10112

DT <- isds::getDataQTI(hosp_id = hID)[BMI > 0]


strat    <- c("PRIMARY_PROCEDURE", "BENIGN_MALIGNANT", "PATIENT_TYPE")
covars   <- c("BMI", "PATIENT_AGE", "CHARLSON_SCORE", "PATIENT_GENDER")
outcomes <- c("LOS_HOURS", "OR_TIME_MINS")


psmDT <- psm_data(DT, strat, covars, outcomes)
setkeyv(psmDT, c("CID"))


# rbindlist(lapply(split(psmDT, by = "CID"), function(i){
#   res <- get_stats(i, outcomes)
#   res[, .N, c("outcome", "CID", "T_STAT", "P_VAL", "C_INT_L", "C_INT_H")][, !"N"]
# }))

statDT <- isds::runPSM(hosp_id = hID)[P_VAL < .05]




dTable <- psmDT[, .N, .(CID, 
                      HOSPITAL_ID, 
                      PRIMARY_PROCEDURE, 
                      BENIGN_MALIGNANT, 
                      PATIENT_TYPE)]

setkeyv(dTable, "CID")
setkeyv(statDT, "CID")
statsumDT <- dTable[statDT][!is.na(HOSPITAL_ID)]
setkeyv(statsumDT, c("CID", "outcome", "MODALITY"))


cids <- as.integer(statDT[P_VAL < .1, .N, CID][, CID])
# pList <- split(pDT, by = "CID", drop = TRUE)


pI <- psmDT[ CID == cids[1] ]

# pI[, PRIMARY_PROCEDURE := "Nephroureterectomy"]
pI[, joined_labs := str_c(str_replace_all(PRIMARY_PROCEDURE, " ", "_"), " ", MODALITY)]
pI[, is_out := id_outliers(get(outcomes[1]), "prob") | id_outliers(get(outcomes[2]), "prob"), MODALITY]

# GET CONF INTERVAL AND PVAL
by <- c("CID", "HOSPITAL_ID", strat, "P_VAL", "T_STAT", "C_INT_L", "C_INT_H", "outcome", "PSM_COUNT")
ssRow <- statsumDT[CID == i, .N, by]

## ADD SUM STATS
for(o in outcomes){
  pI[, c(paste0(o, "_", "PVAL"))   := ssRow[outcome == o, P_VAL]]
  pI[, c(paste0(o, "_", "T_STAT")) := ssRow[outcome == o, T_STAT]]
  pI[, c(paste0(o, "_", "C_LOW"))  := ssRow[outcome == o, C_INT_L]]
  pI[, c(paste0(o, "_", "C_HIGH")) := ssRow[outcome == o, C_INT_H]]
}

plot_dat <- pI[is_out == FALSE]




# BEGIN PLOTTING DATA -----------------------------------------------------


plotBean <- function(data, o, add_legend = FALSE){
  
  modals <- str_to_title(data[, .N, MODALITY][, MODALITY])
  names(modals) <- c("x", "y")
  
  cols <- c("azure3", "royalblue1")
  
  f <- as.formula(rlang::parse_expr(paste0(o, " ~ joined_labs")))
  beanplot(f, 
           axes = FALSE,
           # ylim = c(100, 400),
           horizontal = FALSE, 
           xlab = o,
           data = data,
           ll = NA,
           method = "jitter",
           main = NULL, 
           side = "both", 
           innerborder = "black",
           border = NA, 
           col = as.list(cols), 
           log = "y")
  if(add_legend){
    legend("bottomleft",
           bty = "n",
           fill = cols,
           legend = modals)   
  }
}



# png(filename=paste0("R/development/plots/outrm_", ssRow[, unique(PRIMARY_PROCEDURE)], ".png"),
#     units="in",
#     width=12,
#     height=8,
#     pointsize=14,
#     res=100)

plot.new()
par(mfrow=c(1,2), oma = c(0, 2, 1, 2), mai = c(.5, .3, .05, .3))


labs <- substitute(
  paste0("\n\tN (patients)  : ",  ssRow[outcome == o, PSM_COUNT],
         "\nP Value        : ", ssRow[outcome == o, round(P_VAL, 5)],
         "\nT-Statistic    : ", ssRow[outcome == o, round(T_STAT, 4)],
         "\nConfidence  : [", 
         ssRow[outcome == o, paste0(round(C_INT_L), " , ", round(C_INT_H))], "]")
)

### LEFT HAND SIDE PLOT
###
o <- "LOS_HOURS"

plotBean(plot_dat, o, add_legend = TRUE)
axis(side = 2)
mtext(eval(labs), 3, adj = .1, line = -6)
title(xlab = o, line = .2)

### RIGHT HAND SIDE PLOT
###
o <- "OR_TIME_MINS"

plotBean(plot_dat, o)
axis(side = 4)
mtext(eval(labs), 3, adj = -.1, line = -6)
title(xlab = o, line = .2, xlim = c(500, 500))

## Add Title to Plot
title(main = ssRow[, unique(PRIMARY_PROCEDURE)], line = 0, outer = TRUE)


# dev.off()

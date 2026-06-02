# ==============================================================================
# MY457: Reappraisal Summative Assignment
# "Polity Size and Local Government Performance: Evidence from India"
# Narasimhan & Weaver (2024), American Economic Review, 114(11): 3385-3426
# ==============================================================================

# ==============================================================================
# 0. SETUP
# ==============================================================================

# ── Install packages (if required) ────────────────────────────────────────────
# install.packages("haven")
# install.packages("tidyverse")
# install.packages("rdrobust")
# install.packages("rddensity")
# install.packages("kableExtra")
# install.packages("ggplot2")


# ── Load packages ─────────────────────────────────────────────────────────────
library(haven)        # read .dta Stata files
library(tidyverse)    # data wrangling + ggplot2
library(rdrobust)     # RD estimation (rdrobust, rdplot, rddensity)
library(rddensity)
library(kableExtra)   # table formatting

# ── CHANGE THIS ONE PATH ──────────────────────────────────────────────────────
root <- "/Users/amolshailasuresh/Documents/GitHub/summative-reappraisal-LSE-61578-2526"
# root <- "."

file.exists(root)    # check if the file path exists
# ──────────────────────────────────────────────────────────────────────────────

# Derived paths (no changes needed below)
data_path   <- file.path(root, "data", "analysis_data")
main_fig    <- file.path(root, "main_exhibits", "figures")
main_tab    <- file.path(root, "main_exhibits", "tables")
app_fig     <- file.path(root, "appendix_exhibits", "figures")

# Create output folders if they don't already exist
dir.create(main_fig, recursive = TRUE, showWarnings = FALSE)
dir.create(main_tab, recursive = TRUE, showWarnings = FALSE)
dir.create(app_fig,  recursive = TRUE, showWarnings = FALSE)


# ── Section flags: set to TRUE to run, FALSE to skip ─────────────────────────
run_figure1        <- TRUE
run_figure2        <- TRUE
run_table1         <- TRUE
run_table2         <- TRUE
run_table3         <- TRUE


# Appendix
run_manipulation   <- TRUE   # McCrary density test (Appendix Fig A3)
run_balance_figs   <- TRUE   # Baseline balance plots (Appendix Figs A4-A5)
run_gp_size        <- TRUE   # GP size distribution (Appendix Fig A2)


# ==============================================================================
# 1. HELPER FUNCTIONS
# ==============================================================================

# ── 1a. run_rd() : thin wrapper around rdrobust() ─────────────────────────────
# Returns the rdrobust object so callers can extract whatever they need.
# We use kernel = "triangular" and bwselect = "mserd" (rdrobust defaults),
# which are used in throughout the paper.

run_rd <- function(y, x, cutoff = 1000, cluster = NULL,
                   subset = NULL, kernel = "triangular",
                   bwselect = "mserd") {
  
  if (!is.null(subset)) {
    y       <- y[subset]
    x       <- x[subset]
    cluster <- if (!is.null(cluster)) cluster[subset] else NULL
  }
  
  # Drop rows with missings in y or x
  keep <- !is.na(y) & !is.na(x) & (is.null(cluster) | !is.na(cluster))
  y       <- y[keep]
  x       <- x[keep]
  cluster <- if (!is.null(cluster)) cluster[keep] else NULL
  
  rdrobust(y = y, x = x, c = cutoff,
           cluster = cluster,
           kernel  = kernel,
           bwselect = bwselect,
           masspoints = "off")
}

# ── 1b. rd_coefs() : extract key scalars from an rdrobust object ──────────────

rd_coefs <- function(rdr, dep_mean = NA) {
  list(
    estimate = rdr$coef[1],              # conventional estimate
    se       = rdr$se[1],                # conventional clustered SE
    pval     = rdr$pv[3],                # robust p-value
    bw_l     = rdr$bws[1, 1],            # left bandwidth
    bw_r     = rdr$bws[1, 2],            # right bandwidth
    n_eff    = rdr$N_h[1] + rdr$N_h[2],  # effective obs in bandwidth
    dep_mean = dep_mean
  )
}

# ── 1c. rd_plot_gg() : ggplot2 RD plot ────────────────────────────────────────

rd_plot_gg <- function(df, y_var, x_var,
                         subset      = NULL,
                         cluster_var = NULL,
                         cutoff      = 1000,
                         binwidth    = 5,
                         xtitle      = "Village population",
                         ytitle      = "Outcome",
                         ylim        = NULL) {
  
  # Apply subset first, then build dataframe internally  
  if (!is.null(subset)) {
    y_var <- y_var[subset]
    x_var <- x_var[subset]
  }
  
  d <- data.frame(x = x_var, y = y_var)
  d <- d[!is.na(d$x) & !is.na(d$y), ]
  
#  d <- df[, c(x_var, y_var, if (!is.null(cluster_var)) cluster_var)]
#  names(d)[1:2] <- c("x", "y")
#  d <- d[!is.na(d$x) & !is.na(d$y), ]
  
  # Step 1: get MSE-optimal bandwidth from rdrobust (mirrors rdplot_custom)
  cl_vec <- if (!is.null(cluster_var)) d[[cluster_var]] else NULL
  rdr    <- rdrobust(y       = d$y,
                     x       = d$x,
                     c       = cutoff,
                     cluster = cl_vec,
                     kernel  = "triangular",
                     bwselect = "mserd")
  
  bw_l <- rdr$bws[1, 1]   # left bandwidth
  bw_r <- rdr$bws[1, 2]   # right bandwidth
  
  # Step 2: restrict data to bandwidth window
  d <- d[d$x >= (cutoff - bw_l) & d$x <= (cutoff + bw_r), ]
  
  # Step 3: bin the data into fixed-width bins within that window
  d$bin <- floor(d$x / binwidth) * binwidth + binwidth / 2
  
  bins_df <- d |>
    dplyr::group_by(bin) |>
    dplyr::summarise(mean_y = mean(y, na.rm = TRUE), .groups = "drop")
  
  # Step 4: fit separate OLS on raw data each side of cutoff
  left_data  <- d[d$x <  cutoff, ]
  right_data <- d[d$x >= cutoff, ]
  
  fit_left   <- lm(y ~ x, data = left_data)
  fit_right  <- lm(y ~ x, data = right_data)
  
  pred_left  <- data.frame(x = seq(cutoff - bw_l, cutoff - 0.01, length.out = 200))
  pred_left$y  <- predict(fit_left,  newdata = pred_left)
  
  pred_right <- data.frame(x = seq(cutoff, cutoff + bw_r, length.out = 200))
  pred_right$y <- predict(fit_right, newdata = pred_right)
  
  # Step 5: build the ggplot
  p <- ggplot() +
    geom_point(data = bins_df,
               aes(x = bin, y = mean_y),
               colour = "grey40", size = 1.8) +
    geom_line(data = pred_left,
              aes(x = x, y = y),
              colour = "royalblue", linewidth = 1) +
    geom_line(data = pred_right,
              aes(x = x, y = y),
              colour = "royalblue", linewidth = 1) +
    geom_vline(xintercept = cutoff,
               linetype = "solid", colour = "black", linewidth = 0.4) +
    labs(x = xtitle, y = ytitle) +
    theme_classic(base_size = 11) +
    theme(plot.background = element_rect(fill = "white", colour = NA))
  
  if (!is.null(ylim)) {
    p <- p + coord_cartesian(ylim = ylim)
  }
  
  return(p)
}

# ── 1d. build_rd_table() : produce a tidy tibble of RD results ────────────────
# Runs rdrobust on each variable in `vars`, returns a data frame suitable for
# kableExtra formatting.

build_rd_table <- function(df, vars, running, cutoff = 1000,
                           cluster_var = NULL, subset_expr = NULL) {
  
  mask <- if (!is.null(subset_expr)) eval(parse(text = subset_expr), envir = df) else rep(TRUE, nrow(df))
  mask <- mask & !is.na(df[[running]])
  
  results <- lapply(vars, function(v) {
    y_vec <- df[[v]]
    x_vec <- df[[running]]
    cl_vec <- if (!is.null(cluster_var)) df[[cluster_var]] else NULL
    
    
    tryCatch({
      rdr <- run_rd(y = y_vec, x = x_vec, cutoff = cutoff,
                    cluster = cl_vec, subset = mask)
      
      bw_l <- rdr$bws[1, 1]
      bw_rounded <- round(bw_l)
      
      valid <- mask & !is.na(y_vec) & !is.na(x_vec)
      if (!is.null(cluster_var)) valid <- valid & !is.na(df[[cluster_var]])
      
      dep_mean <- mean(y_vec[mask & x_vec >= (cutoff - bw_l) & x_vec < cutoff],
                       na.rm = TRUE)
      
      c_list <- rd_coefs(rdr, dep_mean)
      tibble(
        variable  = v,
        estimate  = c_list$estimate,
        se        = c_list$se,
        pval      = c_list$pval,
        dep_mean  = c_list$dep_mean,
        bandwidth = round(c_list$bw_l),
        n_eff     = c_list$n_eff
      )
    }, error = function(e) {
      message("RD failed for variable: ", v, " — ", e$message)
      tibble(variable = v, estimate = NA_real_, se = NA_real_,
             pval = NA_real_, dep_mean = NA_real_,
             bandwidth = NA_real_, n_eff = NA_real_)
    })
  })
  
  bind_rows(results)
}

# ── 1e. format_pval() : bracket p-values as in the paper ──────────────────────
format_pval <- function(p) {
  ifelse(is.na(p), "", sprintf("[%.3f]", p))
}

# ── 1f. add_stars() : add significance stars ──────────────────────────────────
add_stars <- function(est, p) {
  stars <- case_when(
    p < 0.01 ~ "***",
    p < 0.05 ~ "**",
    p < 0.10 ~ "*",
    TRUE      ~ ""
  )
  sprintf("%.3f%s", est, stars)
}


# ==============================================================================
# 2. FIGURE 1 — First Stage: Effect on GP Population (Figures 1a–1d)
# ==============================================================================

if (run_figure1) {
  message("--- Figure 1 ---")
  
  # Load main village directory
  vd <- read_dta(file.path(data_path, "villagedirectory", "village_analysis_cleaned.dta"))
  
  # ── Figure 1a : 1995 delimitation — GP population ───────────────────────────
  p1a <- rd_plot_gg(
    y_var       = vd[["pc91_gp_jj11"]],
    x_var       = vd$pc91_pca_tot_p,
    cluster_var = "gp_code_jj11_num",
    xtitle      = "Village population (1991 census)",
    ytitle      = "Gram panchayat population (1995)"
  )
  ggsave(file.path(main_fig, "figure1a.png"), p1a, width = 7, height = 5, dpi = 300)
  
  # ── Figure 1b : 2015 delimitation — GP population ───────────────────────────
  p1b <- rd_plot_gg(
    y_var       = vd[["pc11_gp_lgd21"]],
    x_var       = vd$pc11_pca_tot_p,
    cluster_var = "gp_code_lgd21_num",
    xtitle      = "Village population (2011 census)",
    ytitle      = "Gram panchayat population (2015)"
  )
  ggsave(file.path(main_fig, "figure1b.png"), p1b, width = 7, height = 5, dpi = 300)
  
  # ── Figure 1c : 1995 delimitation — Single village GP ───────────────────────
  p1c <- rd_plot_gg(
    y_var       = vd[["solo_gp95"]],
    x_var       = vd$pc91_pca_tot_p,
    cluster_var = "gp_code_jj11_num",
    xtitle      = "Village population (1991 census)",
    ytitle      = "Only one village in GP (=1)"
  )
  ggsave(file.path(main_fig, "figure1c.png"), p1c, width = 7, height = 5, dpi = 300)
  
  # ── Figure 1d : 2015 delimitation — Single village GP ───────────────────────
  p1d <- rd_plot_gg(
    y_var       = vd[["solo_gp15"]],
    x_var       = vd$pc11_pca_tot_p,
    cluster_var = "gp_code_lgd21_num",
    xtitle      = "Village population (2011 census)",
    ytitle      = "Only one village in GP (=1)"
  )
  ggsave(file.path(main_fig, "figure1d.png"), p1d, width = 7, height = 5, dpi = 300)
  
  message("Figure 1: saved to ", main_fig)
}


# ==============================================================================
# 3. FIGURE 2 — Main Outcome RD Plots (Figures 2a–2f)
# ==============================================================================

if (run_figure2) {
  message("--- Figure 2 ---")
  
  # ── Load datasets ───────────────────────────────────────────────────────────
  amen  <- read_dta(file.path(data_path, "amenities", "amenities_analysis.dta"))
  nregs <- read_dta(file.path(data_path, "nregs", "up_nregs.dta"))
  ma    <- read_dta(file.path(data_path, "mission_antyodaya", "village_ma_2019_cleaned.dta"))
  
  # Figure 2a: Education index (1991 census)
  p2a <- rd_plot_gg(
    y_var       = amen[["education_index"]],
    x_var       = amen$pc91_pca_tot_p,
    cluster_var = "gp_code_jj11_num",
    xtitle      = "Village population (1991 census)",
    ytitle      = "Education index"
  )
  #  ggsave(file.path(main_fig, "figure2a.png"), p2a, width = 7, height = 5, dpi = 300)
  
  # Figure 2b: Village amenities index (1991 census)
  p2b <- rd_plot_gg(
    y_var       = amen[["amenities_village_index"]],
    x_var       = amen$pc91_pca_tot_p,
    cluster_var = "gp_code_jj11_num",
    xtitle      = "Village population (1991 census)",
    ytitle      = "Village amenities index"
  )
  
  # Figure 2c: Household amenities index (1991 census)
  p2c <- rd_plot_gg(
    y_var       = amen[["amenities_hh_index"]],
    x_var       = amen$pc91_pca_tot_p,
    cluster_var = "gp_code_jj11_num",
    xtitle      = "Village population (1991 census)",
    ytitle      = "Household amenities index"
  )
  
  # Figure 2d: NREGS/Workfare index (2011 census)
  p2d <- rd_plot_gg(
    y_var       = nregs[["performance_z"]],
    x_var       = nregs$pc11_pca_tot_p,
    cluster_var = "gp_code_lgd21_num",
    xtitle      = "Village population (2011 census)",
    ytitle      = "Workfare index"
  )
  
  # Figure 2e: Mission Antyodaya services index (2011 census)
  p2e <- rd_plot_gg(
    y_var       = ma[["ma_index"]],
    x_var       = ma$pc11_pca_tot_p,
    cluster_var = "gp_code_lgd21_num",
    xtitle      = "Village population (2011 census)",
    ytitle      = "Services index"
  )
  
  
  # Figure 2f: Targeting — correlation between poverty and BPL ownership
  # Stata: for each 5-unit bin of pc11_pca_tot_p, compute correlation between
  # secc_pov_rate_rural and bpl_hhs_pp, then binscatter vs population.
  # We replicate this with dplyr group_by + cor().
  
  # Load SECC poverty data and merge
  vd2 <- read_dta(file.path(data_path, "villagedirectory", "village_analysis_cleaned.dta")) |>
    select(shrid, pc11_pca_tot_p)
  
  secc <- read_dta(file.path(data_path, "secc", "shrug_secc.dta")) |>
    select(shrid, secc_pov_rate_rural)
  
  ma_secc <- ma |>
    left_join(select(vd2, shrid, pc11_pca_tot_p_vd = pc11_pca_tot_p),
              by = "shrid") |>
    left_join(secc, by = "shrid") |>
    filter(pc11_pca_tot_p < 10000, !is.na(secc_pov_rate_rural), !is.na(bpl_hhs_pp))
  
  # Create 5-person bins and compute correlation within each
  targeting_corr <- ma_secc |>
    mutate(pop_bin = floor(pc11_pca_tot_p / 5) * 5) |>
    group_by(pop_bin) |>
    filter(n() > 50) |>
    summarise(
      corr = cor(secc_pov_rate_rural, bpl_hhs_pp, use = "complete.obs"),
      .groups = "drop"
    ) |>
    filter(between(pop_bin, 750, 1250))
  
  p2f <- ggplot(targeting_corr, aes(x = pop_bin, y = corr)) +
    geom_point(colour = "grey60", size = 1.5) +
    geom_smooth(method = "lm", se = FALSE, colour = "royalblue", linewidth = 0.9,
                data = targeting_corr[targeting_corr$pop_bin < 1000, ]) +
    geom_smooth(method = "lm", se = FALSE, colour = "royalblue", linewidth = 0.9,
                data = targeting_corr[targeting_corr$pop_bin >= 1000, ]) +
    geom_vline(xintercept = 1000, linetype = "dashed", colour = "grey40") +
    labs(x = "Village population (2011 census)",
         y = "Correlation of poverty and BPL ownership") +
    theme_classic(base_size = 11)
  
  # Save individual panels
  for (nm in c("2a","2b","2c","2d","2e","2f")) {
    obj <- get(paste0("p", nm))
    ggsave(file.path(main_fig, paste0("figure", nm, ".png")),
           obj, width = 7, height = 5, dpi = 300)
  }
  
  message("Figure 2: saved to ", main_fig)
}


# ==============================================================================
# 4. TABLE 1 — First Stage and Baseline Balance
# ==============================================================================
# Panel A: 1991 census / 1995 delimitation
# Panel B: 2011 census / 2015 delimitation
# Columns: GP population (first stage), then baseline covariates

if (run_table1) {
  
  message("--- Table 1 ---")
  
  amen <- read_dta(file.path(data_path, "amenities", "amenities_analysis.dta")) |>
    mutate(
      lit_prop91 = pc91_pca_p_lit / pc91_pca_tot_p,
      lit_prop11 = pc11_pca_p_lit / pc11_pca_tot_p
    )
  
  # Panel A: 1991 running variable
  varsA <- c("pc91_gp_jj11", "any_primary91", "any_middle91",
             "pc91_vd_tar_road", "pc91_vd_power_all", "sc_prop91", "lit_prop91")
  
  res1A <- build_rd_table(amen, varsA, "pc91_pca_tot_p",
                         cluster_var = "gp_code_lgd21_num")
  
  # Panel B: 2011 running variable
  varsB <- c("pc11_gp_lgd21", "any_primary11", "any_middle11",
             "pc11_vd_tar_road", "pc11_vd_power_all", "sc_prop11", "lit_prop11")
  
  res1B <- build_rd_table(amen, varsB, "pc11_pca_tot_p",
                         cluster_var = "gp_code_lgd21_num")
  
  # Format the table
  format_panel <- function(res, var_labels) {
    res |>
      mutate(
        Variable   = var_labels,
        Estimate   = add_stars(estimate, pval),
        SE         = ifelse(is.na(se), "", sprintf("(%.3f)", se)),
        `P-value`  = format_pval(pval),
        `Dep Mean` = ifelse(is.na(dep_mean), "", sprintf("%.3f", dep_mean)),
        Bandwidth  = ifelse(is.na(bandwidth), "", as.character(round(bandwidth))),
        `Eff. Obs` = ifelse(is.na(n_eff), "", as.character(n_eff))
      ) |>
      select(Variable, Estimate, SE, `P-value`, `Dep Mean`, Bandwidth, `Eff. Obs`)
  }
  
  labelsA <- c("GP population", "Primary school (=1)", "Middle school (=1)",
               "Paved road (=1)", "Electricity (=1)", "SC fraction", "Literate fraction")
  labelsB <- c("GP population", "Primary school (=1)", "Middle school (=1)",
               "Paved road (=1)", "Electricity (=1)", "SC fraction", "Literate fraction")
  
  tab1A <- format_panel(res1A, labelsA)
  tab1B <- format_panel(res1B, labelsB)
  
  # Write to CSV
  write_csv(tab1A, file.path(main_tab, "table1_panelA.csv"))
  write_csv(tab1B, file.path(main_tab, "table1_panelB.csv"))
  
  # Also save as kableExtra HTML for direct Quarto embedding
  bind_rows(
    tab1A |> mutate(Panel = "Panel A: 1991 census / 1995 delimitation"),
    tab1B |> mutate(Panel = "Panel B: 2011 census / 2015 delimitation")
  ) |>
    select(Panel, everything()) |>
    kbl(caption = "Table 1: First Stage and Baseline Balance",
        booktabs = TRUE, format = "html") |>
    kable_styling(full_width = FALSE) |>
    pack_rows("Panel A: 1991 census / 1995 delimitation", 1, nrow(tab1A)) |>
    pack_rows("Panel B: 2011 census / 2015 delimitation",
              nrow(tab1A) + 1, nrow(tab1A) + nrow(tab1B)) |>
    save_kable(file.path(main_tab, "table1.html"))
  
  message("Table 1: saved to ", main_tab)
}


# ==============================================================================
# 5. TABLE 2 — Effects on Village Amenities (1995 delimitation)
# ==============================================================================
# Panel A: Educational outcomes
# Panel B: Village-level infrastructure
# Panel C: Household-level infrastructure
#The running variable is the population of the village in the 1991 census.

if (run_table2) {
  
  message("--- Table 2 ---")
  
  amen <- read_dta(file.path(data_path, "amenities", "amenities_analysis.dta"))
  
  # Panel A
  varsA <- c("education_index", "any_primary01", "any_middle01",
             "any_primary11", "any_middle11", "education_aboveprimary", "education_ma19")
  
  res2A <- build_rd_table(amen, varsA, "pc91_pca_tot_p",
                         cluster_var = "gp_code_jj11_num")
  
  labelsA <- c("Education index", "Primary school (2001)", "Middle school (2001)",
               "Primary school (2011)", "Middle school (2011)",
               "Above primary educ. (2012)", "Education score (2019)")
  
  # Panel B
  varsB <- c("amenities_village_index", "pc01_vd_tar_road", "any_tap01",
             "pc11_vd_tar_road", "pds11", "community_centre11")
  
  res2B <- build_rd_table(amen, varsB, "pc91_pca_tot_p",
                         cluster_var = "gp_code_jj11_num")
  
  labelsB <- c("Village amenities index", "Paved road (2001)", "Tap water (2001)",
               "Paved road (2011)", "Fair price shop (2011)", "Community centre (2011)")
  
  # Panel C
  varsC <- c("amenities_hh_index", "housing_materials_z", "piped_water",
             "latrineperc", "nolatrine_open", "wastewater_closed")
  
  res2C <- build_rd_table(amen, varsC, "pc91_pca_tot_p",
                         cluster_var = "gp_code_jj11_num")
  
  labelsC <- c("HH amenities index", "House quality index", "Piped water",
               "Households with toilet", "Open defecation", "Closed drains")
  
  # Format and save
  fmt_panel <- function(res, labels) {
    res |>
      mutate(
        Variable  = labels,
        Estimate  = add_stars(estimate, pval),
        SE        = sprintf("(%.3f)", se),
        `P-value` = format_pval(pval),
        `Dep Mean` = sprintf("%.3f", dep_mean),
        BW        = round(bandwidth),
        `Eff. N`  = n_eff
      ) |>
      select(Variable, Estimate, SE, `P-value`, `Dep Mean`, BW, `Eff. N`)
  }
  
  tab2A <- fmt_panel(res2A, labelsA)
  tab2B <- fmt_panel(res2B, labelsB)
  tab2C <- fmt_panel(res2C, labelsC)
  
  write_csv(tab2A, file.path(main_tab, "table2_panelA.csv"))
  write_csv(tab2B, file.path(main_tab, "table2_panelB.csv"))
  write_csv(tab2C, file.path(main_tab, "table2_panelC.csv"))
  
  message("Table 2: saved to ", main_tab)
}


# ==============================================================================
# 6. TABLE 3 — Effect on Delivery of Services (2015 delimitation)
# ==============================================================================
# Panel A: Individual-level welfare programs (Mission Antyodaya, 2019)
# Panel B: NREGS workfare outcomes (2016–2020)
#The running variable is the population of the village in the 2011 census.

if (run_table3) {
  
  message("--- Table 3 ---")
  
  ma    <- read_dta(file.path(data_path, "mission_antyodaya", "village_ma_2019_cleaned.dta"))
  nregs <- read_dta(file.path(data_path, "nregs", "up_nregs.dta"))
  
  # Panel A: Individual-level programs
  varsA <- c("ma_index", "bpl_hhs", "health_insurance_hhs",
             "total_hhs_pensions", "electricity_saubhagya",
             "lpg_hhs", "housing_schemes_total", "pmmvy_received", "jandhan_hhs")
  
  res3A <- build_rd_table(ma, varsA, "pc11_pca_tot_p",
                         cluster_var = "gp_code_lgd21_num")
  
  labelsA <- c("Programs index", "BPL card", "Health insurance",
               "Pension", "Saubhagya", "LPG", "Housing benefits",
               "PMMVY", "Jan Dhan")
  
  # Panel B: NREGS
  varsB <- c("performance_z", "demand_p_pp", "persondays_pp",
             "expenditure_labor_pp", "expenditure_material_pp", "total_works_pp")
  
  res3B <- build_rd_table(nregs, varsB, "pc11_pca_tot_p",
                         cluster_var = "gp_code_lgd21_num")
  
  labelsB <- c("NREGS index", "Work demand", "Days worked",
               "Labor expenditure", "Material expenditure", "Total projects")
  
  # Format and save
  fmt_panel <- function(res, labels) {
    res |>
      mutate(
        Variable  = labels,
        Estimate  = add_stars(estimate, pval),
        SE        = sprintf("(%.3f)", se),
        `P-value` = format_pval(pval),
        `Dep Mean` = sprintf("%.3f", dep_mean),
        BW        = round(bandwidth),
        `Eff. N`  = n_eff
      ) |>
      select(Variable, Estimate, SE, `P-value`, `Dep Mean`, BW, `Eff. N`)
  }
  
  tab3A <- fmt_panel(res3A, labelsA)
  tab3B <- fmt_panel(res3B, labelsB)
  
  write_csv(tab3A, file.path(main_tab, "table3_panelA.csv"))
  write_csv(tab3B, file.path(main_tab, "table3_panelB.csv"))
  
  message("Table 3: saved to ", main_tab)
}


# ==============================================================================
# 7. APPENDIX — Manipulation (density) Test
# ==============================================================================
# Through manipulation test, we are testing one of the assumptions in the paper. 
# The test asks: did people bunch up suspiciously on one side of the cutoff?
# RD strategy rests on the assumption that villages just below and just above 
# 1,000 people are otherwise identical - continuity assumption.
# Can we trust that a village falling on either side of cutoff is effectively random?

if (run_manipulation) {
  
  message("--- Appendix: Manipulation Test ---")
  
  vd <- read_dta(file.path(data_path, "villagedirectory", "village_analysis_cleaned.dta"))
  
  # 1991 census
  x91 <- vd$pc91_pca_tot_p[vd$statename == "uttar pradesh" & !is.na(vd$pc91_pca_tot_p)]
  rdd91 <- rddensity(X = x91, c = 1000)
  message("  1991 density test p-value: ", round(rdd91$test$p_jk, 4))
  
  # Save the density plot using rdplotdensity
  png(file.path(app_fig, "manipulationtest_1991.png"),
      width = 800, height = 600, res = 120)
  rdplotdensity(rdd91, x91,
                title     = "",
                xlabel    = "Village population (1991 census)",
                CIuniform = TRUE)
  dev.off()
  
  # 2011 census
  x11 <- vd$pc11_pca_tot_p[vd$statename == "uttar pradesh" & !is.na(vd$pc11_pca_tot_p)]
  rdd11 <- rddensity(X = x11, c = 1000)
  message("  2011 density test p-value: ", round(rdd11$test$p_jk, 4))
  
  png(file.path(app_fig, "manipulationtest_2011.png"),
      width = 800, height = 600, res = 120)
  rdplotdensity(rdd11, x11,
                title  = "",
                xlabel = "Village population (2011 census)")
  dev.off()
  
  message("Manipulation tests: saved to ", app_fig)
}


# ==============================================================================
# 8. APPENDIX — Balance Figures (Appendix Figures A4–A5)
# ==============================================================================
# Plot each baseline covariate against the running variable to check balance.

if (run_balance_figs) {
  
  message("--- Appendix: Balance Figures ---")
  
  amen <- read_dta(file.path(data_path, "amenities", "amenities_analysis.dta")) |>
    mutate(
      lit_prop91 = pc91_pca_p_lit / pc91_pca_tot_p,
      lit_prop11 = pc11_pca_p_lit / pc11_pca_tot_p
    )
  
  # Panel A4: 1991 baseline covariates
  vars91 <- c("any_primary91", "any_middle91", "pc91_vd_power_all",
              "pc91_vd_tar_road", "sc_prop91", "lit_prop91")
  labs91 <- c("Primary school", "Middle school", "Electricity",
              "All-weather road", "SC population", "Literate population")
  
  for (i in seq_along(vars91)) {
    p <- rd_plot_gg(
      y_var      = amen[[vars91[i]]],
      x_var      = amen$pc91_pca_tot_p,
      subset = amen$pc91_pca_tot_p < 10000,
      xtitle = "Village population (1991 census)",
      ytitle = labs91[i]
    )
    ggsave(file.path(app_fig, paste0(vars91[i], "_balance.png")),
           p, width = 6, height = 4, dpi = 150)
  }
  
  # Panel A5: 2011 baseline covariates
  vars11 <- c("any_primary11", "any_middle11", "pc11_vd_power_all",
              "pc11_vd_tar_road", "sc_prop11", "lit_prop11")
  labs11 <- c("Primary school", "Middle school", "Electricity",
              "All-weather road", "SC population", "Literate population")
  
  for (i in seq_along(vars11)) {
    p <- rd_plot_gg(
      y_var       = amen[[vars11[i]]],
      x_var      = amen$pc11_pca_tot_p,
      subset = amen$pc11_pca_tot_p < 10000,
      xtitle = "Village population (2011 census)",
      ytitle = labs11[i]
    )
    ggsave(file.path(app_fig, paste0(vars11[i], "_balance.png")),
           p, width = 6, height = 4, dpi = 150)
  }
  
  message("Balance figures: saved to ", app_fig)
}


# ==============================================================================
# 9. APPENDIX — GP Size Distribution (Appendix Figure A2)
# ==============================================================================

if (run_gp_size) {
  
  message("--- Appendix: GP Size Distribution ---")
  
  # UP-specific GP population histograms
  vd <- read_dta(file.path(data_path, "villagedirectory", "village_analysis_cleaned.dta"))
  
  # 1991 GP population distribution
  p_up91 <- ggplot(filter(vd, pc91_gp_jj11 < 10000, !is.na(pc91_gp_jj11)),
                   aes(x = pc91_gp_jj11)) +
    geom_histogram(binwidth = 250, fill = "violetred2", colour = "black", linewidth = 0.3) +
    scale_x_continuous(breaks = seq(0, 10000, by = 2000)) + 
    labs(title = "Uttar Pradesh GP population distribution (1995-2015)",
         x = "Gram Panchayat population (1995–2015)",
         y = "Frequency") +
    theme_classic(base_size = 11)
  
  ggsave(file.path(app_fig, "gpsize_up_1991.png"), p_up91,
         width = 7, height = 5, dpi = 300)
  
  # 2015 GP population distribution
  p_up11 <- ggplot(filter(vd, pc11_gp_lgd21 < 10000, !is.na(pc11_gp_lgd21)),
                   aes(x = pc11_gp_lgd21)) +
    geom_histogram(binwidth = 250, fill = "violetred2", colour = "black", linewidth = 0.3) +
    scale_x_continuous(breaks = seq(0, 10000, by = 2000)) + 
    labs(title = "Uttar Pradesh GP population distribution (2015-2021)",
         x = "Gram Panchayat population (post-2015)",
         y = "Frequency") +
    theme_classic(base_size = 11)
  
  ggsave(file.path(app_fig, "gpsize_up_2021.png"), p_up11,
         width = 7, height = 5, dpi = 300)
  
  message("GP size figures: saved to ", app_fig)
}



# ==============================================================================
# Fuzzy RD analysis — Effect of Solo GP Status
# ==============================================================================

# ── Helper: Fuzzy RD runner ───────────────────────────────────────────────────
run_rd_fuzzy <- function(y, x, fuzzy, cutoff = 1000, cluster = NULL,
                         subset = NULL, kernel = "triangular",
                         bwselect = "mserd") {
  
  if (!is.null(subset)) {
    y       <- y[subset]
    x       <- x[subset]
    fuzzy   <- fuzzy[subset]
    cluster <- if (!is.null(cluster)) cluster[subset] else NULL
  }
  
  keep <- !is.na(y) & !is.na(x) & !is.na(fuzzy) &
    (is.null(cluster) | !is.na(cluster))
  y       <- y[keep]
  x       <- x[keep]
  fuzzy   <- fuzzy[keep]
  cluster <- if (!is.null(cluster)) cluster[keep] else NULL
  
  rdrobust(y = y, x = x, c = cutoff,
           fuzzy   = fuzzy,
           cluster = cluster,
           kernel  = kernel,
           bwselect = bwselect,
           masspoints = "off")
}

# ── Helper: Extract fuzzy RD coefficients ────────────────────────────────
fuzzy_rd_coefs <- function(rdr, dep_mean = NA) {
  list(
    estimate = rdr$coef[1],
    se       = rdr$se[1],
    pval     = rdr$pv[3],       # robust p-value
    bw_l     = rdr$bws[1, 1],
    n_eff    = rdr$N_h[1] + rdr$N_h[2],
    dep_mean = dep_mean
  )
}

# ── Helper: Build fuzzy RD table ─────────────────────────────────────────
build_fuzzy_table <- function(df, vars, running, fuzzy_var,
                              cutoff = 1000, cluster_var = NULL) {
  
  mask <- !is.na(df[[running]])
  
  results <- lapply(vars, function(v) {
    y_vec     <- df[[v]]
    x_vec     <- df[[running]]
    fuzzy_vec <- df[[fuzzy_var]]
    cl_vec    <- if (!is.null(cluster_var)) df[[cluster_var]] else NULL
    
    tryCatch({
      rdr <- run_rd_fuzzy(y = y_vec, x = x_vec, fuzzy = fuzzy_vec,
                          cutoff = cutoff, cluster = cl_vec, subset = mask)
      
      bw_rounded <- round(rdr$bws[1, 1])
      valid <- mask & !is.na(y_vec) & !is.na(x_vec) & !is.na(fuzzy_vec)
      if (!is.null(cluster_var)) valid <- valid & !is.na(df[[cluster_var]])
      dep_mean <- mean(y_vec[valid & x_vec >= (cutoff - bw_rounded) &
                               x_vec < cutoff], na.rm = TRUE)
      
      c_list <- fuzzy_rd_coefs(rdr, dep_mean)
      tibble(
        variable  = v,
        estimate  = c_list$estimate,
        se        = c_list$se,
        pval      = c_list$pval,
        dep_mean  = c_list$dep_mean,
        bandwidth = round(c_list$bw_l),
        n_eff     = c_list$n_eff
      )
    }, error = function(e) {
      message("Fuzzy RD failed for: ", v, " — ", e$message)
      tibble(variable = v, estimate = NA_real_, se = NA_real_,
             pval = NA_real_, dep_mean = NA_real_,
             bandwidth = NA_real_, n_eff = NA_real_)
    })
  })
  
  bind_rows(results)
}

# ══════════════════════════════════════════════════════════════════════════
# BLOCK 1: 1995 delimitation — Village amenities outcomes
# ══════════════════════════════════════════════════════════════════════════

# Merge solo_gp95 into village amenities data
fuzzy_amen <- amen |>
  left_join(select(vd, shrid, solo_gp95), by = "shrid")

fuzzy_vars_95 <- c("pc01_vd_tar_road", "any_tap01",
                   "latrineperc", "wastewater_closed")

fuzzy_labels_95 <- c("Paved road (2001)", "Tap water (2001)",
                     "Toilet (%)", "Closed drains (%)")

res_fuzzy_95 <- build_fuzzy_table(
  df          = fuzzy_amen,
  vars        = fuzzy_vars_95,
  running     = "pc91_pca_tot_p",
  fuzzy_var   = "solo_gp95",
  cluster_var = "gp_code_jj11_num"
)

# ══════════════════════════════════════════════════════════════════════════
# BLOCK 2: 2015 delimitation — NREGS outcomes
# ══════════════════════════════════════════════════════════════════════════

# Merge solo_gp15 into NREGS data
fuzzy_nregs <- nregs

fuzzy_vars_15 <- c("performance_z", "demand_p_pp", "persondays_pp",
                   "expenditure_labor_pp", "expenditure_material_pp",
                   "total_works_pp")

fuzzy_labels_15 <- c("NREGS index", "Work demand", "Days worked",
                     "Labor expenditure", "Material expenditure",
                     "Total projects")

res_fuzzy_15 <- build_fuzzy_table(
  df          = fuzzy_nregs,
  vars        = fuzzy_vars_15,
  running     = "pc11_pca_tot_p",
  fuzzy_var   = "solo_gp15",
  cluster_var = "gp_code_lgd21_num"
)

# ══════════════════════════════════════════════════════════════════════════
# FORMAT AND SAVE
# ══════════════════════════════════════════════════════════════════════════

fmt_fuzzy <- function(res, labels) {
  res |>
    mutate(
      Variable   = labels,
      Estimate   = add_stars(estimate, pval),
      SE         = sprintf("(%.3f)", se),
      `P-value`  = format_pval(pval),
      `Dep Mean` = sprintf("%.3f", dep_mean),
      BW         = round(bandwidth),
      `Eff. N`   = n_eff
    ) |>
    select(Variable, Estimate, SE, `P-value`, `Dep Mean`, BW, `Eff. N`)
}

tab_fuzzy_95 <- fmt_fuzzy(res_fuzzy_95, fuzzy_labels_95)
tab_fuzzy_15 <- fmt_fuzzy(res_fuzzy_15, fuzzy_labels_15)

write_csv(tab_fuzzy_95, file.path(main_tab, "fuzzy_rd_1995.csv"))
write_csv(tab_fuzzy_15, file.path(main_tab, "fuzzy_rd_2015.csv"))



# ==============================================================================
# END
# ==============================================================================
*==============================================================================*
* 11_power.do
*
* PURPOSE : Recompute minimum detectable effects from the REALISED samples and
*           variances, replacing the ex-ante figures in §10 of the analysis plan.
*           Implements §10.
*
* INPUT   : $clean/sc_analysis.dta, $clean/nonsc_analysis.dta,
*           $clean/conjoint_long.dta, $clean/alloc_did.dta
* OUTPUT  : $out/tab_power_realised.txt
*           $clean/power_sim_conjoint.dta
*
* WHY RECOMPUTE
*   The plan's MDE table was produced by simulating the INTENDED design at
*   n = 150 per instrument. Realised sample sizes will differ (non-response,
*   consent refusals, dropped records), and the realised variances of the
*   indices were unknown before data collection. An MDE table computed from the
*   realised data is what belongs in the methodology chapter.
*
* WHAT AN MDE IS, AND HOW TO USE IT HONESTLY
*   The minimum detectable effect is the smallest true effect the study would
*   detect with the stated power. It is NOT a threshold below which an estimate
*   is meaningless. Its correct use is CALIBRATION: stating the MDE before
*   presenting results lets a reader judge a modest estimate as informative
*   rather than as a failure. Stating it AFTER seeing the results, selectively,
*   is post-hoc rationalisation.
*
*   The plan recommends stating in the methodology chapter that the study is
*   powered to detect conjoint interaction effects of roughly 14 pp or larger, so
*   readers calibrate before seeing results. Do that, using the realised figure
*   this file produces.
*
* STANDARD FORMULAE USED
*   Two-sided alpha = 0.05, power = 0.80, so the multiplier is
*     z(1 - alpha/2) + z(power) = 1.959964 + 0.8416212 = 2.801585
*
*   Two-group comparison of means:
*     MDE = 2.801585 * sd * sqrt(1/n1 + 1/n2)
*   Two-group comparison of proportions (conservative, at p = 0.5):
*     MDE = 2.801585 * sqrt(p(1-p)) * sqrt(1/n1 + 1/n2)
*   Smallest detectable correlation (Fisher z approximation):
*     r_min such that 0.5*ln((1+r)/(1-r)) = 2.801585 / sqrt(n - 3)
*
*   These are asymptotic approximations. At n = 150 they are adequate for
*   calibration but should not be quoted to more than one decimal place.
*==============================================================================*

capture log close powerlog
log using "$out/tab_power_realised.txt", replace text name(powerlog)

* the standard multiplier for alpha = 0.05 two-sided, power = 0.80
local Z = invnormal(0.975) + invnormal(0.80)

display _n "=================================================================="
display    " REALISED MINIMUM DETECTABLE EFFECTS"
display    ""
display    " alpha = 0.05 two-sided, power = 0.80"
display    " Multiplier z(0.975) + z(0.80) = " %7.5f `Z'
display    ""
display    " These figures replace the ex-ante table in §10 of the analysis"
display    " plan. Report them in the methodology chapter BEFORE presenting"
display    " results, so readers calibrate their expectations. Quoting an MDE"
display    " selectively after seeing results is post-hoc rationalisation."
display    "=================================================================="


*==============================================================================*
* SECTION 1. SC SURVEY
*==============================================================================*
use "$clean/sc_analysis.dta", clear
quietly count
local n_sc = r(N)

display _n(2) "##################################################################"
display       "# 1. SC SURVEY   (realised n = `n_sc')"
display       "##################################################################"

*------------------------------------------------------------------------------*
* 1.1 Precision of a single prevalence estimate
*------------------------------------------------------------------------------*
display _n "--- 1.1 Confidence-interval half-width for a single prevalence ---"
display "Computed at several true prevalences, because precision is best in the"
display "tails and worst at p = 0.5."
foreach p in 0.05 0.10 0.25 0.50 {
    local hw = 1.959964 * sqrt(`p' * (1 - `p') / `n_sc')
    display "  at p = " %4.2f `p' ":  95% CI half-width = +/- " ///
        %5.1f 100*`hw' " pp"
}

display _n "  Realised half-widths on actual items (Wilson intervals):"
foreach v of global BL_BUREAU_F {
    capture confirm variable `v'
    if _rc continue
    quietly ci proportions `v', wilson
    local hw = 100 * (r(ub) - r(lb)) / 2
    display "    " %-16s "`v'" "  p = " %5.1f 100*r(proportion) ///
        "%   half-width = +/- " %4.1f `hw' " pp"
}

*------------------------------------------------------------------------------*
* 1.2 Two-group comparison within the SC sample
*
* Relevant for any subgroup split: by gender, by proxy status, by above- or
* below-median authority.
*------------------------------------------------------------------------------*
display _n "--- 1.2 Two-group comparisons within the SC sample ---"

display _n "  On a standardised index (SD = 1 by construction):"
foreach split in 0.50 0.35 0.20 {
    local n1 = `n_sc' * `split'
    local n2 = `n_sc' - `n1'
    local mde = `Z' * 1 * sqrt(1/`n1' + 1/`n2')
    display "    split " %4.2f `split' "/" %4.2f 1-`split' ///
        " (n = " %4.0f `n1' " vs " %4.0f `n2' "):  MDE = " %5.3f `mde' " SD"
}

display _n "  On a single binary item at p = 0.5:"
foreach split in 0.50 0.35 0.20 {
    local n1 = `n_sc' * `split'
    local n2 = `n_sc' - `n1'
    local mde = `Z' * sqrt(0.25) * sqrt(1/`n1' + 1/`n2')
    display "    split " %4.2f `split' ":  MDE = " %5.1f 100*`mde' " pp"
}
display _n "  This is why item-level hypothesis testing is not viable and the"
display    "  index-primary strategy is the right one. Item-level work is"
display    "  DESCRIPTION (05_desc_sc.do) and an FDR-adjusted exploratory"
display    "  appendix, not inference."

*--- realised splits actually used in the analysis ---*
display _n "  Realised subgroup sizes for the splits used:"
foreach v in mukh_sex_n proxy_resp lowqual {
    capture confirm variable `v'
    if _rc continue
    display "    `v':"
    quietly tab `v', matcell(freqs)
    quietly levelsof `v', local(lvls)
    local i = 1
    foreach l of local lvls {
        quietly count if `v' == `l'
        display "      level `l': n = " r(N)
        local ++i
    }
}

*------------------------------------------------------------------------------*
* 1.3 Smallest detectable correlation
*
* Directly relevant to the plan's Q3, on whether rights awareness proxies for
* independence. A weak-to-moderate true correlation would be invisible, so a
* null must be reported as "no DETECTABLE association".
*------------------------------------------------------------------------------*
display _n "--- 1.3 Smallest detectable correlation ---"
if `n_sc' > 3 {
    local z_crit = `Z' / sqrt(`n_sc' - 3)
    local r_min  = (exp(2 * `z_crit') - 1) / (exp(2 * `z_crit') + 1)
    display as result "  At n = `n_sc':  r_min = " %5.3f `r_min'
    display _n "  Consequence for the knowledge-authority correlation: a true"
    display    "  correlation below " %4.2f `r_min' " would not be detected."
    display    "  Report a null as 'no detectable association', never as 'no"
    display    "  association'."

    quietly correlate auth_idx kn_demo_idx
    display _n "  Realised r(auth_idx, kn_demo_idx) = " %5.3f r(rho) ///
        "   (n = " r(N) ")"
}

*------------------------------------------------------------------------------*
* 1.4 Regression MDE on the authority coefficient
*
* The bivariate formula understates precision when covariates explain variance
* and overstates it when they absorb variation in the regressor. The realised
* standard error is the honest figure, so it is reported directly.
*------------------------------------------------------------------------------*
display _n "--- 1.4 MDE from the realised standard errors ---"
display "  MDE = " %5.3f `Z' " x SE, using the SE from the full specification."
display "  This is the most honest version of the calculation, because it"
display "  incorporates the actual covariate structure rather than assuming a"
display "  bivariate comparison."
foreach y in ma_idx bl_bureau_idx bl_social_idx bl_symbol_idx vb_idx {
    capture confirm variable `y'
    if _rc continue
    quietly regress `y' auth_idx $X_DEMOG $X_PANCH $X_POLIT, vce(robust)
    local se = _se[auth_idx]
    local mde = `Z' * `se'
    display "    " %-16s "`y'" "  SE = " %6.4f `se' "   MDE = " %5.3f `mde' " SD"
}


*==============================================================================*
* SECTION 2. NON-SC SURVEY AND THE SC / NON-SC COMPARISON
*==============================================================================*
use "$clean/nonsc_analysis.dta", clear
quietly count
local n_ns = r(N)

display _n(2) "##################################################################"
display       "# 2. NON-SC SURVEY (realised n = `n_ns') AND THE COMPARISON"
display       "##################################################################"

display _n "--- 2.1 SC versus non-SC comparison ---"
local mde_idx = `Z' * 1 * sqrt(1/`n_sc' + 1/`n_ns')
local mde_bin = `Z' * sqrt(0.25) * sqrt(1/`n_sc' + 1/`n_ns')
display as result "  Continuous standardised index:  MDE = " %5.3f `mde_idx' " SD"
display as result "  Binary item at p = 0.5:         MDE = " %5.1f 100*`mde_bin' " pp"
display _n "  (Plan's ex-ante figures were 0.32 SD and 16.2 pp.)"

display _n "  From the realised standard errors, adjusted specification:"
use "$clean/pooled_analysis.dta", clear
local X3 i.educ_ord n_terms n_stood i.mukh_sex_n fam_any ///
         i.gp_scshare_ord ln_gp_pop revenue_villages i.gp_mainvill_n i.income_n i.party_n
foreach y in auth_idx auth_tasks eff_idx kn_demo_idx wb_idx {
    capture confirm variable `y'
    if _rc continue
    quietly regress `y' sc_sample `X3', vce(robust)
    quietly summarize `y'
    local sd = r(sd)
    if `sd' > 0 {
        display "    " %-14s "`y'" "  SE = " %6.4f _se[sc_sample] ///
            "   MDE = " %6.3f `Z'*_se[sc_sample]/`sd' " SD"
    }
}


*==============================================================================*
* SECTION 3. CONJOINT: SIMULATION-BASED MDE
*
* An analytical formula is not adequate here, because the design has clustered
* observations (10 profile rows per respondent), a forced-choice outcome, and
* unequal attribute probabilities. Simulation is the right tool.
*
* METHOD
*   Use the REALISED attribute assignments and cluster structure, so the
*   simulation inherits the actual design rather than an idealised version of it.
*   For a grid of true effect sizes, impose that effect on a simulated outcome,
*   estimate the model, and record whether the coefficient is significant. Power
*   is the rejection rate across replications; the MDE is the smallest effect
*   with power >= 0.80.
*
* REPRODUCIBILITY
*   The seed is set from $seed, and the data are SORTED ON A UNIQUE KEY before
*   any random draw. This is the same lesson as the sampling do-file: a
*   non-deterministic sort order before the RNG, not the seed, is what makes
*   results move between runs. Here the key is uid-task-profile.
*
* RUNTIME
*   Roughly reps x grid points regressions. With the defaults below that is
*   400 x 6 = 2,400 regressions on 1,500 rows, which takes a few minutes.
*   Reduce $bootreps-scaled reps below if you need it faster for a trial run.
*==============================================================================*
capture confirm file "$clean/conjoint_long.dta"
if _rc {
    display as error "conjoint_long.dta not found; run 07_conjoint_reshape.do first."
}
else {

use "$clean/conjoint_long.dta", clear

display _n(2) "##################################################################"
display       "# 3. CONJOINT: SIMULATION-BASED MDE"
display       "##################################################################"

quietly count
local n_rows = r(N)
quietly levelsof uid, local(uids)
local n_cj : word count `uids'
quietly summarize task
local n_tasks = r(max)

display _n "  Realised design:"
display "    respondents           = `n_cj'"
display "    tasks per respondent  = `n_tasks'"
display "    profile rows          = `n_rows'"

* baseline outcome mean, needed so the simulated probabilities stay in [0,1]
quietly summarize chosen_coop
local base = r(mean)
display "    baseline choice rate  = " %5.3f `base'

*--- simulation parameters ---*
local reps = 400          // replications per grid point
local grid "0.05 0.08 0.10 0.12 0.15 0.20"

display _n "  Simulation: `reps' replications per effect size."
display "  Grid of true effects (in probability units): `grid'"

* CRITICAL for reproducibility: sort on the unique key BEFORE seeding, so the
* RNG fills rows in a deterministic order on every run.
sort uid task profile
set seed $seed

tempfile simres
tempname sh
postfile `sh' str24 estimand double(true_effect power reps) using `simres', replace

*------------------------------------------------------------------------------*
* 3.1 Power for the SC main effect
*------------------------------------------------------------------------------*
display _n "--- 3.1 SC caste AMCE ---"
foreach eff of local grid {

    local rejects = 0

    forvalues r = 1/`reps' {

        * Simulate a forced-choice outcome consistent with the realised
        * attributes. Within each task, profile A's latent utility gets the
        * treatment effect applied to its SC indicator; the profile with the
        * higher simulated utility is chosen. This preserves the forced-choice
        * structure (exactly one profile chosen per task), which a simple
        * independent Bernoulli draw would not.
        quietly {
            capture drop _u _pick _sim
            gen double _u = `eff' * p_sc + rnormal(0, 0.5)
            bysort taskid: egen double _pick = max(_u)
            gen byte _sim = (_u == _pick)
            * Exact ties are impossible with continuous rnormal draws, so no
            * tie-break is needed. If you ever switch to a discrete error
            * distribution, add one here or some tasks will show two chosen
            * profiles and the outcome will no longer be forced-choice.
        }

        quietly regress _sim p_sc p_indep p_welloff p_educated, vce(cluster uid)
        quietly test p_sc
        if r(p) < 0.05 local ++rejects
    }

    local pow = `rejects' / `reps'
    display "    true effect " %5.3f `eff' "  ->  power = " %5.3f `pow'
    post `sh' ("SC AMCE") (`eff') (`pow') (`reps')
}

*------------------------------------------------------------------------------*
* 3.2 Power for the authority-style main effect
*------------------------------------------------------------------------------*
display _n "--- 3.2 Authority-style AMCE ---"
foreach eff of local grid {
    local rejects = 0
    forvalues r = 1/`reps' {
        quietly {
            capture drop _u _pick _sim
            gen double _u = `eff' * p_indep + rnormal(0, 0.5)
            bysort taskid: egen double _pick = max(_u)
            gen byte _sim = (_u == _pick)
        }
        quietly regress _sim p_sc p_indep p_welloff p_educated, vce(cluster uid)
        quietly test p_indep
        if r(p) < 0.05 local ++rejects
    }
    local pow = `rejects' / `reps'
    display "    true effect " %5.3f `eff' "  ->  power = " %5.3f `pow'
    post `sh' ("Authority AMCE") (`eff') (`pow') (`reps')
}

*------------------------------------------------------------------------------*
* 3.3 Power for the caste x authority INTERACTION
*
* This is the dissertation's central parameter and the least well-powered
* quantity in the study. The ex-ante figure was approximately 14.4 pp.
*------------------------------------------------------------------------------*
display _n "--- 3.3 THE CENTRAL TEST: caste x authority interaction ---"
local grid_int "0.08 0.10 0.12 0.14 0.16 0.20 0.25"
foreach eff of local grid_int {
    local rejects = 0
    forvalues r = 1/`reps' {
        quietly {
            capture drop _u _pick _sim
            * main effects held at a modest constant so the interaction is
            * estimated in a realistic setting rather than in isolation
            gen double _u = -0.05 * p_sc + 0.05 * p_indep ///
                            + `eff' * sc_x_indep + rnormal(0, 0.5)
            bysort taskid: egen double _pick = max(_u)
            gen byte _sim = (_u == _pick)
        }
        quietly regress _sim i.p_sc##i.p_indep p_welloff p_educated, vce(cluster uid)
        quietly test 1.p_sc#1.p_indep
        if r(p) < 0.05 local ++rejects
    }
    local pow = `rejects' / `reps'
    display "    true effect " %5.3f `eff' "  ->  power = " %5.3f `pow'
    post `sh' ("Caste x authority") (`eff') (`pow') (`reps')
}

*------------------------------------------------------------------------------*
* 3.4 Power for a subgroup difference in the interaction
*------------------------------------------------------------------------------*
display _n "--- 3.4 Interaction difference across two subgroups ---"
display "  Split on the prejudice index, which is the pre-specified moderator."
capture confirm variable prej_pc1
if !_rc {
    quietly summarize prej_pc1, detail
    local pmed = r(p50)
    capture drop hiprej
    quietly gen byte hiprej = (prej_pc1 > `pmed') if !missing(prej_pc1)

    local grid_sub "0.15 0.20 0.25 0.30 0.35"
    foreach eff of local grid_sub {
        local rejects = 0
        forvalues r = 1/`reps' {
            quietly {
                capture drop _u _pick _sim
                gen double _u = `eff' * sc_x_indep * hiprej + rnormal(0, 0.5)
                bysort taskid: egen double _pick = max(_u)
                gen byte _sim = (_u == _pick)
            }
            quietly regress _sim i.p_sc##i.p_indep##i.hiprej p_welloff p_educated, ///
                vce(cluster uid)
            capture quietly test 1.p_sc#1.p_indep#1.hiprej
            if !_rc {
                if r(p) < 0.05 local ++rejects
            }
        }
        local pow = `rejects' / `reps'
        display "    true difference " %5.3f `eff' "  ->  power = " %5.3f `pow'
        post `sh' ("Subgroup difference") (`eff') (`pow') (`reps')
    }
    capture drop hiprej
}
capture drop _u _pick _sim

postclose `sh'

*------------------------------------------------------------------------------*
* 3.5 Read the MDEs off the simulation
*------------------------------------------------------------------------------*
preserve
    use `simres', clear
    label var true_effect "True effect in probability units"
    label var power       "Simulated power"
    label var reps        "Replications"

    display _n "--- 3.5 REALISED MDEs FROM SIMULATION (power >= 0.80) ---"
    levelsof estimand, local(ests)
    foreach e of local ests {
        quietly summarize true_effect if estimand == "`e'" & power >= 0.80
        if r(N) > 0 {
            display as result "  " %-22s "`e'" "  MDE = " %5.1f 100*r(min) " pp"
        }
        else {
            quietly summarize true_effect if estimand == "`e'"
            display as result "  " %-22s "`e'" "  MDE exceeds " ///
                %5.1f 100*r(max) " pp (the top of the grid)"
        }
    }

    display _n "  Full power curves:"
    list estimand true_effect power, clean noobs sepby(estimand)

    save "$clean/power_sim_conjoint.dta", replace
    export excel using "$out/tab_power_conjoint_sim.xlsx", ///
        firstrow(variables) replace

    * power curve figure
    capture {
        gen double eff_pp = 100 * true_effect
        encode estimand, gen(est_n)
        twoway (connected power eff_pp if est_n == 1, msymbol(O)) ///
               (connected power eff_pp if est_n == 2, msymbol(S)) ///
               (connected power eff_pp if est_n == 3, msymbol(T)) ///
               (connected power eff_pp if est_n == 4, msymbol(D)) ///
            , yline(0.80, lcolor(red) lpattern(dash)) ///
              ytitle("Simulated power") xtitle("True effect (percentage points)") ///
              ylabel(0(0.2)1, format(%3.1f)) ///
              title("Realised power curves, conjoint experiment", size(medium)) ///
              note("Dashed line at 80% power. `reps' replications per point," ///
                   "using the realised attribute assignments and cluster" ///
                   "structure.", size(vsmall)) ///
              legend(order(1 "SC AMCE" 2 "Authority AMCE" ///
                           3 "Caste x authority" 4 "Subgroup difference") ///
                     size(small) rows(2)) ///
              graphregion(color(white))
        graph export "$out/fig_power_curves.png", replace width(2000)
    }
restore

*------------------------------------------------------------------------------*
* 3.6 Realised precision, which is the figure actually to report
*
* The simulation gives the design's power. The realised standard errors give the
* precision actually achieved, which is what the confidence intervals in the
* results chapter reflect. Report this alongside the simulation.
*------------------------------------------------------------------------------*
display _n "--- 3.6 Realised standard errors and implied MDEs ---"
quietly regress chosen_coop i.p_sc##i.p_indep p_welloff p_educated, vce(cluster uid)
display "  From the estimated model on the real outcome:"
capture {
    local se_int = _se[1.p_sc#1.p_indep]
    display as result "    interaction SE = " %6.4f `se_int' ///
        "   implied MDE = " %5.1f 100*`Z'*`se_int' " pp"
}
quietly regress chosen_coop p_sc p_indep p_welloff p_educated, vce(cluster uid)
display as result "    SC AMCE SE     = " %6.4f _se[p_sc] ///
    "   implied MDE = " %5.1f 100*`Z'*_se[p_sc] " pp"
display as result "    Authority SE   = " %6.4f _se[p_indep] ///
    "   implied MDE = " %5.1f 100*`Z'*_se[p_indep] " pp"

}   // end conjoint block


*==============================================================================*
* SECTION 4. ALLOCATION EXPERIMENT
*
* The within-subject design is the most efficient in the study, because
* differencing removes all between-respondent variance. The plan's ex-ante MDE
* was approximately 0.23 SD of the DiD. The rupee equivalent could not be
* computed before data collection because the SD of the within-respondent DiD
* was unknown; now it can be.
*==============================================================================*
capture confirm file "$clean/alloc_did.dta"
if _rc {
    display as error "alloc_did.dta not found; run 09_alloc.do first."
}
else {

use "$clean/alloc_did.dta", clear

display _n(2) "##################################################################"
display       "# 4. ALLOCATION EXPERIMENT"
display       "##################################################################"

quietly count if !missing(did)
local n_did = r(N)
quietly summarize did
local sd_did = r(sd)
local mean_did = r(mean)

display _n "  Respondents contributing a DiD: `n_did'"
display "  Realised SD of the within-respondent DiD: Rs " %9.0f `sd_did'
display "  Realised mean DiD:                        Rs " %9.0f `mean_did'

* One-sample test on the DiD, so the MDE formula is the one-sample version:
*   MDE = Z * sd / sqrt(n)
local mde_did_sd = `Z' / sqrt(`n_did')
local mde_did_rs = `Z' * `sd_did' / sqrt(`n_did')

display _n as result "  MDE in SD units:  " %5.3f `mde_did_sd' " SD"
display    as result "  MDE in rupees:    Rs " %9.0f `mde_did_rs'
display _n "  (Plan's ex-ante figure was approximately 0.23 SD.)"
display _n "  The SD-unit figure is assumption-free; the rupee figure depends"
display    "  on the realised SD and is the more useful one for prose."

display _n "  Realised precision from the estimated model:"
display "    (this is the honest number, since it incorporates the actual"
display "     covariate structure and clustering)"
preserve
    use "$clean/alloc_long.dta", clear
    capture which reghdfe
    if !_rc {
        quietly reghdfe al_amt i.a_sc##i.a_indep i.slot, absorb(uid) vce(cluster uid)
    }
    else {
        quietly areg al_amt i.a_sc##i.a_indep i.slot, absorb(uid) vce(cluster uid)
    }
    capture {
        local se_b3 = _se[1.a_sc#1.a_indep]
        display as result "    b3 SE = Rs " %9.0f `se_b3' ///
            "   implied MDE = Rs " %9.0f `Z'*`se_b3'
    }
restore

display _n "  ASSESSMENT. The within-subject allocation experiment is the most"
display    "  efficient design in the study, because differencing removes"
display    "  between-respondent variance entirely. Give it real weight in the"
display    "  argument rather than treating it as an appendix curiosity -- but"
display    "  remember the interpretation limits in §7.4: hypothetical stakes,"
display    "  and 'own caste' conflating anti-SC animus with in-group"
display    "  favouritism."

}   // end allocation block


*==============================================================================*
* SECTION 5. SUMMARY TABLE AND WHAT TO SAY IN THE METHODOLOGY CHAPTER
*==============================================================================*
display _n(2) "##################################################################"
display       "# 5. SUMMARY AND WRITE-UP GUIDANCE"
display       "##################################################################"

display _n "--- 5.1 Three honest observations for the limitations section ---"
display ""
display "  1. THE WITHIN-SUBJECT ALLOCATION EXPERIMENT IS THE MOST EFFICIENT"
display "     DESIGN in the study. Differencing removes between-respondent"
display "     variance, which is why its MDE is far smaller than anything in"
display "     the SC survey. Weight it accordingly in the argument."
display ""
display "  2. THE CONJOINT INTERACTION -- THE CENTRAL CAUSAL TEST -- IS THE"
display "     LEAST WELL-POWERED QUANTITY. Pre-specify it (done), report CIs"
display "     prominently (done in 08_conjoint_amce.do), and interpret"
display "     magnitude rather than significance. State the realised MDE in the"
display "     methodology chapter so readers calibrate before seeing results."
display ""
display "  3. ITEM-LEVEL HYPOTHESIS TESTING ON THE SC SURVEY IS NOT VIABLE at"
display "     these sample sizes. This is the strongest practical argument for"
display "     the index-primary strategy, and it should be made explicitly"
display "     rather than left for an examiner to raise."

display _n "--- 5.2 On adding conjoint tasks, if the design were still open ---"
display "  Conjoint power scales with TASKS as well as respondents, so a sixth"
display "  and seventh task would improve interaction precision at low marginal"
display "  cost in respondents. But your own instrument notes flag cognitive"
display "  burden as the binding constraint for a TELEPHONIC conjoint, and"
display "  q_conjoint_r measures how well respondents actually coped."
display "  Do not trade data quality for nominal power. If fieldwork is"
display "  complete this is moot; if a second wave is ever contemplated, check"
display "  the realised comprehension distribution first."

display _n "--- 5.3 Language to use, and to avoid ---"
display ""
display "  USE:    'The study is powered to detect interaction effects of"
display "          approximately X pp or larger. The estimated interaction is"
display "          Y pp with a 95% confidence interval from A to B, which is"
display "          consistent with effects ranging from A to B.'"
display ""
display "  AVOID:  'The interaction was not statistically significant,"
display "          suggesting no effect.' A CI spanning substantively"
display "          important values does not license that conclusion, and an"
display "          examiner will say so."
display ""
display "  AVOID:  quoting an MDE for the first time when explaining away an"
display "          imprecise result. State it in the methodology chapter,"
display "          before results, or it reads as rationalisation."

log close powerlog

display as result _n "=== 11_power.do complete ==="
display as txt "Realised MDEs:   $out/tab_power_realised.txt"
display as txt "Conjoint sim:    $out/tab_power_conjoint_sim.xlsx"
display as txt "Power curves:    $out/fig_power_curves.png"

*==============================================================================*
* END 11_power.do
*==============================================================================*

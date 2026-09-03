*==============================================================================*
* 06_assoc_sc.do
*
* PURPOSE : Association between de facto authority and backlash exposure.
*
* INPUT   : $clean/sc_analysis.dta
* OUTPUT  : $out/tab_assoc_ladder_*.rtf     -- specification ladders
*           $out/tab_assoc_reverse.rtf      -- the symmetric reverse spec
*           $out/tab_wellbeing.rtf
*           $out/tab_item_level_fdr.txt     -- exploratory, FDR-adjusted
*           $out/fig_assoc_coefplot.png
*==============================================================================*
* THE IDENTIFICATION PROBLEM
*
* If you regress backlash on independence and find a positive association, at
* least three readings are OBSERVATIONALLY EQUIVALENT in cross-section:
*
*   1. Independence provokes backlash.                    (the hypothesis)
*   2. Backlash suppresses independence.                  (also the hypothesis)
*   3. Both are driven by unobserved third factors: personal disposition,
*      family political capital, panchayat caste composition, land holdings.
*
* Reading (2) is not a nuisance to be waved away. It is PRECISELY WHAT THE
* QUALITATIVE FINDING SAYS: backlash reimposed the de jure / de facto gap. That
* makes independence and backlash SIMULTANEOUSLY DETERMINED, not sequentially
* related, and the reverse-causality channel is PREDICTED BY THE FRAMEWORK
* rather than merely admitted as possible.
*
* No cross-sectional specification can separate these. This file therefore does
* three things instead of pretending otherwise:
*   (a) reports the forward specification as ASSOCIATION, never as an effect;
*   (b) reports the REVERSE specification alongside it, to demonstrate that the
*       data cannot distinguish direction. Showing the symmetry is more honest
*       and more sophisticated than picking one direction and hoping no examiner
*       asks;
*   (c) defers the causal claim to the conjoint (08_conjoint_amce.do), where
*       random assignment of authority style breaks the simultaneity.
*==============================================================================*

use "$clean/sc_analysis.dta", clear

*------------------------------------------------------------------------------*
* 0. Estimation settings
*
* Clustering and fixed effects are conditional on the frame merge and on there
* being multiple panchayats per block. 04_qc_paradata.do reports the cluster
* counts; set the switches in 00_master.do from that output.
*------------------------------------------------------------------------------*
if $use_block_cluster == 1 {
    capture confirm variable block
    if _rc {
        display as error "use_block_cluster==1 but 'block' is absent."
        display as error "The frame merge did not deliver geography. Set it to 0."
        exit 111
    }
    encode block, gen(block_n)
    local vce "vce(cluster block_n)"
    display as txt "SEs clustered at block level."
}
else {
    local vce "vce(robust)"
    display as txt "Heteroskedasticity-robust SEs (no block/ district clustering)."
}

if $use_district_fe == 1 {
    capture confirm variable district
    if _rc {
        display as error "use_district_fe==1 but 'district' is absent."
        exit 111
    }
    encode district, gen(district_n)
    local fe "i.district_n"
    display as txt "District fixed effects included in the full specification."
}
else {
    local fe ""
    display as txt "No district fixed effects (frame geography unavailable or switched off)."
}

* The four PRIMARY outcomes, per §4.2 of the plan. Hypothesis tests run on
* these indices, not on individual items: at n = 150 a two-group comparison on
* a single binary item has an MDE near 23 pp, so item-level testing is simply
* underpowered. Item-level work is DESCRIPTION (05_desc_sc.do) and, where
* regressions are wanted, an FDR-adjusted appendix (section 4 below).
global PRIMARY_Y ma_idx bl_bureau_idx bl_social_idx bl_idx vb_idx

* Secondary outcomes, reported but not part of the Tier-1 test family.
global SECOND_Y  bl_symbol_idx bl_violent_idx bl_idx bl_bur_intens_idx ma_intens_idx


*==============================================================================*
* SECTION 1. THE SPECIFICATION LADDER
*==============================================================================*
capture log close ladderlog
log using "$out/tab_assoc_ladder.txt", replace text name(ladderlog)

display _n "=================================================================="
display    " AUTHORITY AND BACKLASH: SPECIFICATION LADDER"
display    ""
display    " All estimates are ASSOCIATIONS. See the header of 06_assoc_sc.do"
display    " for why no causal reading is available from these data, and"
display    " 08_conjoint_amce.do for the design that does license one."
display    ""
display    " Rung 1: bivariate"
display    " Rung 2: + demographics (education, tenure, gender, income)"
display    " Rung 3: + panchayat characteristics (SC share, population, villages)"
display    " Rung 4: + political background, knowledge index, proxy respondent"
display    " Rung 5: + district fixed effects (if available)"
display    "=================================================================="

foreach y of global PRIMARY_Y {

    local ylab : variable label `y'
    display _n(2) "### OUTCOME: `y'  (`ylab')"

    eststo clear

    * Rung 1: bivariate
    eststo r1: quietly regress `y' auth_idx, `vce'
    quietly test auth_idx
    display _n "  Rung 1 (bivariate):        b = " %7.4f _b[auth_idx] ///
        "  se = " %6.4f _se[auth_idx] "  p = " %6.4f r(p) "  n = " e(N)

    * Rung 2: + demographics
    eststo r2: quietly regress `y' auth_idx $X_DEMOG, `vce'
    quietly test auth_idx
    display "  Rung 2 (+ demographics):   b = " %7.4f _b[auth_idx] ///
        "  se = " %6.4f _se[auth_idx] "  p = " %6.4f r(p) "  n = " e(N)

    * Rung 3: + panchayat characteristics
    eststo r3: quietly regress `y' auth_idx $X_DEMOG $X_PANCH, `vce'
    quietly test auth_idx
    display "  Rung 3 (+ panchayat):      b = " %7.4f _b[auth_idx] ///
        "  se = " %6.4f _se[auth_idx] "  p = " %6.4f r(p) "  n = " e(N)

    * Rung 4: + political background, knowledge, proxy status
    * proxy_resp enters as a covariate because a proxy answering changes what
    * the experience items measure; kn_idx enters because knowledge is a
    * plausible capacity channel that should not be absorbed into auth_idx.
    eststo r4: quietly regress `y' auth_idx $X_DEMOG $X_PANCH $X_POLIT ///
        kn_idx proxy_resp, `vce'
    quietly test auth_idx
    display "  Rung 4 (+ politics, know): b = " %7.4f _b[auth_idx] ///
        "  se = " %6.4f _se[auth_idx] "  p = " %6.4f r(p) "  n = " e(N)

    * Rung 5: + district FE.
    * reghdfe is used when available because it absorbs the FE efficiently and
    * reports the correct degrees of freedom; areg or regress with i.district_n
    * are equivalent official-Stata fallbacks at this sample size.
    if "`fe'" != "" {
        capture which reghdfe
        if !_rc {
            if $use_block_cluster == 1 {
                eststo r5: quietly reghdfe `y' auth_idx $X_DEMOG $X_PANCH ///
                    $X_POLIT kn_idx proxy_resp, absorb(district_n) ///
                    vce(cluster block_n)
            }
            else {
                eststo r5: quietly reghdfe `y' auth_idx $X_DEMOG $X_PANCH ///
                    $X_POLIT kn_idx proxy_resp, absorb(district_n) vce(robust)
            }
        }
        else {
            display as txt "  (reghdfe not installed; using regress with i.district_n)"
            eststo r5: quietly regress `y' auth_idx $X_DEMOG $X_PANCH ///
                $X_POLIT kn_idx proxy_resp `fe', `vce'
        }
        quietly test auth_idx
        display "  Rung 5 (+ district FE):    b = " %7.4f _b[auth_idx] ///
            "  se = " %6.4f _se[auth_idx] "  p = " %6.4f r(p) "  n = " e(N)
    }

    * export the ladder. esttab is from the estout package (SSC).
    capture which esttab
    if !_rc {
        esttab r1 r2 r3 r4 r5 using "$out/tab_assoc_ladder_`y'.rtf", replace ///
            keep(auth_idx kn_idx proxy_resp) ///
            b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
            stats(N r2, fmt(0 3) labels("Observations" "R-squared")) ///
            mtitles("Bivariate" "+ Demog" "+ Panchayat" "+ Politics" "+ District FE") ///
            title("Association between de facto authority and `ylab'") ///
            addnotes("ASSOCIATION, not effect. See §5.3 and the identification" ///
                     "discussion in the methodology chapter." ///
                     "Standardised index outcomes; coefficients in SD units.") ///
            nonumbers label
    }
    else {
        display as error "  esttab not installed; ladder not exported to RTF."
        display as error "  ssc install estout"
    }
}


********************************************************************************
********************************************************************************


foreach y of global PRIMARY_Y {

    local ylab : variable label `y'
    display _n(2) "### OUTCOME: `y'  (`ylab')"

    eststo clear

    * Rung 1: bivariate
    eststo r1: quietly regress `y' eff_idx, `vce'
    quietly test eff_idx
    display _n "  Rung 1 (bivariate):        b = " %7.4f _b[eff_idx] ///
        "  se = " %6.4f _se[eff_idx] "  p = " %6.4f r(p) "  n = " e(N)

    * Rung 2: + demographics
    eststo r2: quietly regress `y' eff_idx $X_DEMOG, `vce'
    quietly test eff_idx
    display "  Rung 2 (+ demographics):   b = " %7.4f _b[eff_idx] ///
        "  se = " %6.4f _se[eff_idx] "  p = " %6.4f r(p) "  n = " e(N)

    * Rung 3: + panchayat characteristics
    eststo r3: quietly regress `y' eff_idx $X_DEMOG $X_PANCH, `vce'
    quietly test eff_idx
    display "  Rung 3 (+ panchayat):      b = " %7.4f _b[eff_idx] ///
        "  se = " %6.4f _se[eff_idx] "  p = " %6.4f r(p) "  n = " e(N)

    * Rung 4: + political background, knowledge, proxy status
    * proxy_resp enters as a covariate because a proxy answering changes what
    * the experience items measure; kn_idx enters because knowledge is a
    * plausible capacity channel that should not be absorbed into eff_idx.
    eststo r4: quietly regress `y' eff_idx $X_DEMOG $X_PANCH $X_POLIT ///
        kn_idx proxy_resp, `vce'
    quietly test eff_idx
    display "  Rung 4 (+ politics, know): b = " %7.4f _b[eff_idx] ///
        "  se = " %6.4f _se[eff_idx] "  p = " %6.4f r(p) "  n = " e(N)

    * Rung 5: + district FE.
    * reghdfe is used when available because it absorbs the FE efficiently and
    * reports the correct degrees of freedom; areg or regress with i.district_n
    * are equivalent official-Stata fallbacks at this sample size.
    if "`fe'" != "" {
        capture which reghdfe
        if !_rc {
            if $use_block_cluster == 1 {
                eststo r5: quietly reghdfe `y' eff_idx $X_DEMOG $X_PANCH ///
                    $X_POLIT kn_idx proxy_resp, absorb(district_n) ///
                    vce(cluster block_n)
            }
            else {
                eststo r5: quietly reghdfe `y' eff_idx $X_DEMOG $X_PANCH ///
                    $X_POLIT kn_idx proxy_resp, absorb(district_n) vce(robust)
            }
        }
        else {
            display as txt "  (reghdfe not installed; using regress with i.district_n)"
            eststo r5: quietly regress `y' eff_idx $X_DEMOG $X_PANCH ///
                $X_POLIT kn_idx proxy_resp `fe', `vce'
        }
        quietly test eff_idx
        display "  Rung 5 (+ district FE):    b = " %7.4f _b[eff_idx] ///
            "  se = " %6.4f _se[eff_idx] "  p = " %6.4f r(p) "  n = " e(N)
    }

    * export the ladder. esttab is from the estout package (SSC).
    capture which esttab
    if !_rc {
        esttab r1 r2 r3 r4 r5 using "$out/tab_assoc_ladder_`y'.rtf", replace ///
            keep(eff_idx kn_idx proxy_resp) ///
            b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
            stats(N r2, fmt(0 3) labels("Observations" "R-squared")) ///
            mtitles("Bivariate" "+ Demog" "+ Panchayat" "+ Politics" "+ District FE") ///
            title("Association between de facto authority and `ylab'") ///
            addnotes("ASSOCIATION, not effect. See §5.3 and the identification" ///
                     "discussion in the methodology chapter." ///
                     "Standardised index outcomes; coefficients in SD units.") ///
            nonumbers label
    }
    else {
        display as error "  esttab not installed; ladder not exported to RTF."
        display as error "  ssc install estout"
    }
}

********************************************************************************
********************************************************************************







display _n(2) "--- Secondary outcomes: full specification only ---"
foreach y of global SECOND_Y {
    local ylab : variable label `y'
    quietly regress `y' auth_idx $X_DEMOG $X_PANCH $X_POLIT kn_idx proxy_resp, `vce'
    quietly test auth_idx
    display "  " %-20s "`y'" "  b = " %7.4f _b[auth_idx] ///
        "  se = " %6.4f _se[auth_idx] "  p = " %6.4f r(p) "  n = " e(N)
}

display _n(2) "--- A NOTE ON COEFFICIENT STABILITY ---"
display "If beta barely moves across the ladder, the association is not being"
display "generated by the covariates that were added. That is reassuring but it"
display "is NOT proof of no confounding: stability across observed covariates"
display "says nothing about unobserved ones. State this explicitly rather than"
display "letting a stable coefficient do rhetorical work it cannot support."

log close ladderlog


*==============================================================================*
* SECTION 2. THE REVERSE SPECIFICATION
*
* Regress authority ON backlash, with the same covariates. The point is NOT to
* claim this direction is the right one. The point is that both specifications
* fit the data comparably, which DEMONSTRATES that cross-sectional data cannot
* settle direction.
*
* Reporting this is a strength. An examiner who asks "how do you know backlash
* does not cause the low authority rather than the reverse?" should find that
* you asked the question first and answered it honestly.
*==============================================================================*
capture log close revlog
log using "$out/tab_assoc_reverse.txt", replace text name(revlog)

display _n "=================================================================="
display    " THE SYMMETRIC REVERSE SPECIFICATION"
display    ""
display    " Forward: backlash = f(authority)   -- reported in section 1"
display    " Reverse: authority = f(backlash)   -- reported here"
display    ""
display    " Both are estimated on the same data with the same covariates. If"
display    " both fit comparably, the data cannot distinguish direction, which"
display    " is the honest conclusion and the motivation for the experimental"
display    " chapter."
display    ""
display    " NOTE: because both variables are standardised, the forward and"
display    " reverse bivariate coefficients are algebraically related through"
display    " the correlation. The ladder is where they diverge, because the"
display    " covariates do different work in each direction."
display    "=================================================================="

eststo clear
foreach x of global PRIMARY_Y {
    local xlab : variable label `x'
    display _n "### PREDICTOR: `x'  (`xlab')"

    quietly regress auth_idx `x', `vce'
    quietly test `x'
    display "  Bivariate:      b = " %7.4f _b[`x'] "  se = " %6.4f _se[`x'] ///
        "  p = " %6.4f r(p) "  R2 = " %5.3f e(r2)

    eststo rev_`x': quietly regress auth_idx `x' $X_DEMOG $X_PANCH $X_POLIT ///
        kn_idx proxy_resp, `vce'
    quietly test `x'
    display "  Full covariates: b = " %7.4f _b[`x'] "  se = " %6.4f _se[`x'] ///
        "  p = " %6.4f r(p) "  R2 = " %5.3f e(r2)

    * comparison of fit between the two directions
    quietly regress `x' auth_idx $X_DEMOG $X_PANCH $X_POLIT kn_idx proxy_resp, `vce'
    local r2_fwd = e(r2)
    quietly regress auth_idx `x' $X_DEMOG $X_PANCH $X_POLIT kn_idx proxy_resp, `vce'
    local r2_rev = e(r2)
    display "  Forward R2 = " %5.3f `r2_fwd' "   Reverse R2 = " %5.3f `r2_rev'
    display "  (These are not directly comparable as model selection criteria;"
    display "   they are reported to show neither direction fits obviously better.)"
}

capture which esttab
if !_rc {
    esttab rev_* using "$out/tab_assoc_reverse.rtf", replace ///
        keep(ma_idx bl_bureau_idx bl_social_idx vb_idx) ///
        b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
        stats(N r2, fmt(0 3) labels("Observations" "R-squared")) ///
        title("Reverse specification: de facto authority regressed on backlash") ///
        addnotes("Reported to demonstrate that cross-sectional data cannot" ///
                 "distinguish the direction of the relationship. Not a claim" ///
                 "that this direction is correct.") ///
        label
}

log close revlog


*==============================================================================*
* SECTION 3. WELLBEING   (§5.4)
*
* SCALE CAVEAT, which must appear in the dissertation text and not only here:
* the instrument uses FIVE-point 1-5 coding, whereas the validated WHO-5 uses
* SIX-point 0-5 coding with the transformation raw x 4 -> 0-100 and published
* cut-offs. Consequently the raw sum ranges 5-25 (not 0-25), the x4 rescaling
* gives 20-100 (not 0-100), and SCORES ARE NOT COMPARABLE TO PUBLISHED WHO-5
* NORMS OR CUT-OFFS. Report as a modified five-point wellbeing scale. Do not
* apply clinical thresholds.
*
* Both instruments use identical coding, so the SC vs non-SC comparison in
* 10_compare.do remains internally valid. That was the point of matching them:
* internal comparability was gained and external norm-referencing given up.
*
* INTERPRETATION LIMIT: this is cross-sectional, and reverse causation is
* entirely plausible -- poor wellbeing plausibly shapes recall and reporting of
* backlash, not only the other way round. Frame as association.
*==============================================================================*
capture log close wblog
log using "$out/tab_wellbeing.txt", replace text name(wblog)

display _n "=================================================================="
display    " WELLBEING AND BACKLASH EXPOSURE"
display    ""
display    " Modified five-point wellbeing scale, NOT the validated WHO-5."
display    " Raw sum ranges 5-25. Published WHO-5 cut-offs do NOT apply."
display    " Cross-sectional: reverse causation (poor wellbeing shaping recall"
display    " and reporting of backlash) is entirely plausible. Association only."
display    "=================================================================="

display _n "--- Distribution ---"
summarize wb_sum_chk wb_idx, detail
display _n "Item-level:"
foreach v of global WB {
    tab `v'_n, missing
}

display _n "--- Wellbeing regressed on each backlash channel separately ---"
eststo clear
foreach x of global PRIMARY_Y {
    local xlab : variable label `x'
    eststo wb_`x': quietly regress wb_idx `x' $X_DEMOG $X_PANCH $X_POLIT ///
        proxy_resp, `vce'
    quietly test `x'
    display "  " %-18s "`x'" "  b = " %7.4f _b[`x'] "  se = " %6.4f _se[`x'] ///
        "  p = " %6.4f r(p) "  n = " e(N)
}

display _n "--- All channels entered jointly ---"
display "Because the channels are correlated, the joint specification splits a"
display "shared association across them and individual coefficients shrink."
display "Report both the separate and joint estimates."
eststo wb_joint: quietly regress wb_idx $PRIMARY_Y $X_DEMOG $X_PANCH ///
    $X_POLIT proxy_resp, `vce'
quietly test $PRIMARY_Y
display "  Joint test of all four channels: F = " %6.2f r(F) "  p = " %6.4f r(p)
estimates replay wb_joint

capture which esttab
if !_rc {
    esttab wb_* using "$out/tab_wellbeing.rtf", replace ///
        keep($PRIMARY_Y) b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
        stats(N r2, fmt(0 3) labels("Observations" "R-squared")) ///
        title("Wellbeing and backlash exposure (modified 5-point scale)") ///
        addnotes("NOT the validated WHO-5: five-point coding, so published" ///
                 "norms and cut-offs do not apply." ///
                 "Cross-sectional association; reverse causation plausible.") ///
        label
}

log close wblog


*==============================================================================*
* SECTION 4. ITEM-LEVEL REGRESSIONS WITH FDR CONTROL  (Tier 3, exploratory)
*
* §9.1 of the plan assigns item-level regressions to Tier 3: exploratory,
* clearly labelled, FDR-adjusted. They belong in an appendix.
*
* Benjamini-Hochberg q-values are computed BY HAND below rather than with a
* user-written command, so there is no package dependency to verify and the
* arithmetic is inspectable. The procedure:
*   1. rank the m p-values ascending, i = 1..m
*   2. compute q_i = p_i * m / i
*   3. enforce monotonicity from the largest rank downwards:
*      q_i = min(q_i, q_{i+1})
*
* The plan also mentions the SHARPENED TWO-STAGE FDR procedure described by
* Anderson (2008), which is more powerful. That is a different and more involved
* algorithm; the standard BH procedure implemented here is the conservative
* choice. If you want the sharpened version, verify Anderson's exact algorithm
* against the paper before implementing it -- I am not going to code a procedure
* I cannot check against the source.
*==============================================================================*
use "$clean/sc_analysis.dta", clear

if $use_block_cluster == 1 {
    encode block, gen(block_n)
    local vce "vce(cluster block_n)"
}
else {
    local vce "vce(robust)"
}

capture log close fdrlog
log using "$out/tab_item_level_fdr.txt", replace text name(fdrlog)

display _n "=================================================================="
display    " ITEM-LEVEL REGRESSIONS: TIER 3 (EXPLORATORY)"
display    ""
display    " These are UNDERPOWERED BY DESIGN. At n = 150 a single binary item"
display    " has a 95% CI of roughly +/- 8 pp at p = 0.5, and a two-group"
display    " comparison on one item has an MDE near 23 pp. Item-level tests are"
display    " therefore not viable as hypothesis tests; they appear here as an"
display    " exploratory appendix with FDR-adjusted q-values."
display    ""
display    " Estimator: linear probability model (regress on a 0/1 outcome)."
display    " LPM is used because the coefficients read directly as percentage-"
display    " point changes, which is what you want for description. Logit is"
display    " reported as a robustness check where the fitted values stray"
display    " outside [0,1]."
display    ""
display    " Benjamini-Hochberg q-values computed manually; see the code."
display    "=================================================================="

* assemble the item list
local items "$MA_INSULT_F $MA_INVAL_F $MA_ASSAULT_F"
local items "`items' $BL_BUREAU_F $BL_INTERN_F $BL_COMMUN_F"
local items "`items' $BL_SYMBOL_F $BL_VIOLENT_F $VB_F"

* run each regression, collecting b, se and p
tempfile itemres
tempname ih
postfile `ih' str20 item str80 itemlab double(b se p n) using `itemres', replace

foreach v of local items {
    capture confirm variable `v'
    if _rc continue
    quietly count if !missing(`v')
    if r(N) < 20 {
        display as txt "  `v' skipped (fewer than 20 non-missing)."
        continue
    }
    quietly regress `v' auth_idx $X_DEMOG $X_PANCH, `vce'
    local b  = _b[auth_idx]
    local se = _se[auth_idx]
    quietly test auth_idx
    local p  = r(p)
    local n  = e(N)
    local lab : variable label `v'
    post `ih' ("`v'") ("`lab'") (`b') (`se') (`p') (`n')
}
postclose `ih'

* Benjamini-Hochberg adjustment
preserve
    use `itemres', clear
    count
    local m = r(N)
    display _n "Number of tests in the family: m = `m'"

    sort p
    gen int rank = _n
    gen double q_bh = p * `m' / rank

    * enforce monotonicity, working from the largest rank downwards
    gsort -rank
    gen double q = q_bh
    replace q = min(q_bh, q[_n-1]) if _n > 1
    replace q = 1 if q > 1

    sort p
    label var b    "Coefficient on auth_idx (percentage points)"
    label var se   "Standard error"
    label var p    "Unadjusted p-value"
    label var q    "Benjamini-Hochberg FDR q-value"
    label var rank "Rank of p-value"

    display _n "  item                b        se       p       q(BH)   n"
    display    "  ----------------------------------------------------------"
    forvalues i = 1/`m' {
        display "  " %-18s item[`i'] %8.4f b[`i'] %8.4f se[`i'] ///
            %8.4f p[`i'] %8.4f q[`i'] %6.0f n[`i']
    }

    display _n "Items surviving FDR at q < 0.10:"
    count if q < 0.10
    if r(N) == 0 {
        display "  None. Expected given the power constraint; report as such"
        display "  rather than searching for a subset that survives."
    }
    else {
        list item itemlab b se p q if q < 0.10, clean noobs
    }

    save "$clean/item_level_fdr.dta", replace
    export excel using "$out/tab_item_level_fdr.xlsx", ///
        firstrow(variables) replace
restore

log close fdrlog


*==============================================================================*
* SECTION 5. ROBUSTNESS
*==============================================================================*
use "$clean/sc_analysis.dta", clear

if $use_block_cluster == 1 {
    encode block, gen(block_n)
    local vce "vce(cluster block_n)"
}
else {
    local vce "vce(robust)"
}

capture log close roblog
log using "$out/tab_assoc_robustness.txt", replace text name(roblog)

display _n "=================================================================="
display    " ROBUSTNESS CHECKS ON THE ASSOCIATION ESTIMATES"
display    "=================================================================="

foreach y of global PRIMARY_Y {

    display _n(2) "### OUTCOME: `y'"

    * baseline for comparison
    quietly regress `y' auth_idx $X_DEMOG $X_PANCH $X_POLIT kn_idx proxy_resp, `vce'
    quietly test auth_idx
    display "  Baseline (full spec):          b = " %7.4f _b[auth_idx] ///
        "  p = " %6.4f r(p) "  n = " e(N)

    * (a) self-respondents only. Modules D, E, F ask about the respondent's OWN
    * experience, which a proxy cannot report. This is the check that matters
    * most for the experience-based outcomes.
    quietly regress `y' auth_idx $X_DEMOG $X_PANCH $X_POLIT kn_idx ///
        if self_resp == 1, `vce'
    quietly test auth_idx
    display "  (a) Self-respondents only:     b = " %7.4f _b[auth_idx] ///
        "  p = " %6.4f r(p) "  n = " e(N)

    * (b) excluding low-quality interviews
    quietly regress `y' auth_idx $X_DEMOG $X_PANCH $X_POLIT kn_idx proxy_resp ///
        if lowqual == 0, `vce'
    quietly test auth_idx
    display "  (b) Excl. low quality:         b = " %7.4f _b[auth_idx] ///
        "  p = " %6.4f r(p) "  n = " e(N)

    * (c) excluding speeders
    capture {
        quietly regress `y' auth_idx $X_DEMOG $X_PANCH $X_POLIT kn_idx ///
            proxy_resp if speeder == 0, `vce'
        quietly test auth_idx
        display "  (c) Excl. speeders:            b = " %7.4f _b[auth_idx] ///
            "  p = " %6.4f r(p) "  n = " e(N)
    }

    * (d) controlling for interview quality rather than excluding on it
    quietly regress `y' auth_idx $X_DEMOG $X_PANCH $X_POLIT kn_idx proxy_resp ///
        q_underst_r q_sincere_r, `vce'
    quietly test auth_idx
    display "  (d) + quality controls:        b = " %7.4f _b[auth_idx] ///
        "  p = " %6.4f r(p) "  n = " e(N)

    * (e) excluding observations whose index rests on fewer than half its items
    capture {
        quietly regress `y' auth_idx $X_DEMOG $X_PANCH $X_POLIT kn_idx ///
            proxy_resp if `y'_thin == 0, `vce'
        quietly test auth_idx
        display "  (e) Excl. thin indices:        b = " %7.4f _b[auth_idx] ///
            "  p = " %6.4f r(p) "  n = " e(N)
    }

    * (f) task-count instead of the standardised authority index. If the result
    * depends on which authority measure is used, that is worth knowing: the
    * z-scored index and the raw count weight the components differently.
    quietly regress `y' auth_tasks $X_DEMOG $X_PANCH $X_POLIT kn_idx proxy_resp, `vce'
    quietly test auth_tasks
    display "  (f) Task count as predictor:   b = " %7.4f _b[auth_tasks] ///
        "  p = " %6.4f r(p) "  n = " e(N)

    * (g) count outcome with Poisson, where the outcome has a count version.
    * Poisson is appropriate for the raw counts and is a check that the linear
    * model on the standardised index is not being driven by functional form.
    local cnt ""
    if "`y'" == "ma_idx"        local cnt "ma_cnt"
    if "`y'" == "bl_bureau_idx" local cnt "bl_bureau_cnt"
    if "`y'" == "bl_social_idx" local cnt "bl_social_cnt"
    if "`y'" == "vb_idx"        local cnt "vb_cnt"
    if "`cnt'" != "" {
        quietly poisson `cnt' auth_idx $X_DEMOG $X_PANCH $X_POLIT kn_idx ///
            proxy_resp, `vce' irr
        quietly test auth_idx
        display "  (g) Poisson on `cnt': IRR = " %7.4f exp(_b[auth_idx]) ///
            "  p = " %6.4f r(p) "  n = " e(N)
    }
}

display _n(2) "--- Multicollinearity diagnostic on the full covariate set ---"
display "High VIFs would make individual covariate coefficients unstable"
display "without affecting the auth_idx estimate much, but they are worth"
display "knowing about before interpreting any covariate."
quietly regress ma_idx auth_idx $X_DEMOG $X_PANCH $X_POLIT kn_idx proxy_resp
estat vif

display _n "--- Influence: are results driven by a handful of observations? ---"
display "At n = 150 a small number of high-leverage observations can move a"
display "coefficient noticeably. Cook's distance above 4/n is a conventional"
display "flag, though it is a rule of thumb rather than a test."
quietly regress ma_idx auth_idx $X_DEMOG $X_PANCH
predict double cooksd, cooksd
quietly count if cooksd > 4/e(N) & !missing(cooksd)
display "  Observations with Cook's D > 4/n: `r(N)'"
quietly regress ma_idx auth_idx $X_DEMOG $X_PANCH if cooksd <= 4/e(N)
display "  Excluding them: b = " %7.4f _b[auth_idx] "  n = " e(N)
drop cooksd

log close roblog


*==============================================================================*
* SECTION 6. COEFFICIENT PLOT
*==============================================================================*
use "$clean/sc_analysis.dta", clear
if $use_block_cluster == 1 {
    encode block, gen(block_n)
    local vce "vce(cluster block_n)"
}
else {
    local vce "vce(robust)"
}

* `foreach ... of global` accepts exactly one global name, so the extra
* outcomes are appended with `foreach ... in` and macro expansion instead.
eststo clear
foreach y in $PRIMARY_Y bl_symbol_idx bl_violent_idx {
    capture confirm variable `y'
    if _rc continue
    eststo m_`y': quietly regress `y' auth_idx $X_DEMOG $X_PANCH $X_POLIT ///
        kn_idx proxy_resp, `vce'
}

capture which coefplot
if !_rc {
    coefplot (m_ma_idx, label("Microaggression")) ///
             (m_bl_bureau_idx, label("Bureaucratic backlash")) ///
             (m_bl_social_idx, label("Social and elite backlash")) ///
             (m_bl_symbol_idx, label("Symbolic backlash")) ///
             (m_bl_violent_idx, label("Overt threat or violence")) ///
             (m_vb_idx, label("Victim-blaming exposure")) ///
        , keep(auth_idx) xline(0, lcolor(gs8) lpattern(dash)) ///
          levels(95 90) ciopts(recast(rcap)) ///
          xtitle("Coefficient on de facto authority index (SD units)") ///
          title("Authority and backlash exposure: associations", size(medium)) ///
          subtitle("Full specification; 90% and 95% intervals", size(small)) ///
          note("ASSOCIATIONS, not effects. Cross-sectional data cannot" ///
               "distinguish direction; see the reverse specification and" ///
               "the conjoint experiment.", size(vsmall)) ///
          graphregion(color(white)) legend(off)
    graph export "$out/fig_assoc_coefplot.png", replace width(2000)
}
else {
    display as error "coefplot not installed; figure skipped. ssc install coefplot"
}

display as result _n "=== 06_assoc_sc.do complete ==="
display as txt "Specification ladders: $out/tab_assoc_ladder.txt (+ per-outcome RTF)"
display as txt "Reverse specification: $out/tab_assoc_reverse.txt (+ .rtf)"
display as txt "Wellbeing:             $out/tab_wellbeing.txt (+ .rtf)"
display as txt "Item-level FDR:        $out/tab_item_level_fdr.txt (+ .xlsx)"
display as txt "Robustness:            $out/tab_assoc_robustness.txt"
display as txt "Figure:                $out/fig_assoc_coefplot.png"

*==============================================================================*
* END 06_assoc_sc.do
*==============================================================================*

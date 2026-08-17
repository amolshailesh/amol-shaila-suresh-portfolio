*==============================================================================*
* 09_alloc.do
*
* PURPOSE : Resource allocation experiment. Reshape, respondent fixed-effects
*           estimation, two-part model, rank-based test. Implements §7 of the
*           analysis plan.
*
* INPUT   : $clean/nonsc_analysis.dta
* OUTPUT  : $clean/alloc_long.dta
*           $out/tab_alloc_main.txt / .rtf
*           $out/tab_alloc_twopart.txt
*           $out/tab_alloc_robustness.txt
*           $out/fig_alloc_cells.png
*
*==============================================================================*
* A DESIGN FACT THAT DIFFERS FROM THE ANALYSIS PLAN'S DESCRIPTION
*
* Reading the deployed form directly: each e_alloc_slot* is an INDEPENDENT range
* question, 0 to 100,000 in steps of 5,000, with the constraint
* ". >= 0 and . <= 100000" applied SEPARATELY to each slot. There is no
* cross-slot constraint. The Hindi hint attached to every slot instructs the
* respondent explicitly not to subtract amounts already spent:
*   "हर सवाल में खर्च एक लाख रुपये में से ही पूछना है। पिछले सवाल में खर्च किये
*    पैसों को घटाना नहीं है।"
*
* So this is FOUR INDEPENDENT WILLINGNESS-TO-SPEND MEASURES, each out of a fresh
* Rs 1,00,000. It is NOT a single budget divided across four profiles. Three
* consequences:
*
*   1. The four amounts can legitimately sum to more than Rs 1,00,000, and
*      al_total in the cleaning file will show that they often do. That is not
*      an error.
*   2. Do NOT describe this as a "budget allocation", and do not compute or
*      report shares of a shared budget. The plan's §7.3 robustness check
*      "allocation as share of budget (0-1)" is implemented below as a simple
*      RESCALING of each independent measure by 100,000, which is legitimate,
*      but the language in the write-up must be "amount, rescaled" and not
*      "share of budget".
*   3. The within-respondent difference-in-differences (beta_3) is still cleanly
*      identified, because it differences across independently measured profiles
*      within the same respondent. The design's core estimand survives intact.
*
* Please confirm this reading against your own understanding of how the module
* was administered and how enumerators were briefed, since the briefing may have
* framed it as a shared budget even though the form does not enforce one.
*
* THE 2x2
*      profile   caste        authority style
*      P1        Scheduled Caste   acts independently
*      P2        Scheduled Caste   follows the elders
*      P3        own caste         acts independently
*      P4        own caste         follows the elders
*
* Presentation order was randomised via e_k1 to e_k4 and e_rank_p*, and the
* realised order is recorded in al_prof1 to al_prof4. The reshape keys on
* PROFILE IDENTITY (P1-P4), not slot position; slot position is retained as a
* control so an order effect can be tested rather than assumed away.
*==============================================================================*

use "$clean/nonsc_analysis.dta", clear

*------------------------------------------------------------------------------*
* 0. Keep what the long file needs
*------------------------------------------------------------------------------*
count
local n_resp = r(N)
display as result "Respondents entering the allocation reshape: `n_resp'"

local keepvars uid                                                    ///
               prej_pc1 prej_z at_res_idx at_stereo_idx at_poa_idx    ///
               at_vb_idx                                              ///
               caste_cat_n educ_ord educ_sec income_n party_n         ///
               mukh_sex_n n_terms n_stood                             ///
               gp_scshare_ord ln_gp_pop revenue_villages gp_mainvill_n fam_any  ///
               auth_idx auth_tasks eff_idx kn_demo_idx wb_idx         ///
               proxy_resp self_resp lowqual q_underst_r q_sincere_r   ///
               q_conjoint q_conjoint_r pns_rate al_total al_flat
foreach v in district block gp strata sample_group kobo_user dur_min speeder {
    capture confirm variable `v'
    if !_rc local keepvars "`keepvars' `v'"
}
foreach k in 1 2 3 4 {
    local keepvars "`keepvars' al_prof`k' al_amt`k'"
}
keep `keepvars'
isid uid

*------------------------------------------------------------------------------*
* 1. Reshape to respondent x slot
*
* This gives four rows per respondent, keyed on SLOT POSITION. The next step
* re-keys them on profile identity.
*------------------------------------------------------------------------------*
reshape long al_prof al_amt, i(uid) j(slot)

label var slot    "Presentation slot (1-4, order randomised)"
label var al_prof "Profile identity presented in this slot (P1-P4)"
label var al_amt  "Rupees the respondent would spend to block this profile"

count
local n_rows = r(N)
display as result "Rows after reshape: `n_rows'"
assert `n_rows' == `n_resp' * 4
display as result "  Assertion passed: `n_resp' respondents x 4 slots."

*------------------------------------------------------------------------------*
* 2. Re-key on profile identity and build the 2x2 factors
*
* al_prof holds "P1" to "P4". Each respondent should see each profile exactly
* once; the assertion below confirms the form's ranking logic worked.
*------------------------------------------------------------------------------*
gen byte prof_id = .
replace  prof_id = 1 if trim(upper(al_prof)) == "P1"
replace  prof_id = 2 if trim(upper(al_prof)) == "P2"
replace  prof_id = 3 if trim(upper(al_prof)) == "P3"
replace  prof_id = 4 if trim(upper(al_prof)) == "P4"
label define profid4 1 "P1: SC, independent" 2 "P2: SC, follows elders" ///
                     3 "P3: own caste, independent" ///
                     4 "P4: own caste, follows elders", replace
label values prof_id profid4
label var prof_id "Allocation profile identity"

quietly count if missing(prof_id)
if r(N) > 0 {
    display as error "`r(N)' rows have an unparseable al_prof value."
    tab al_prof if missing(prof_id)
    exit 459
}

* each respondent must see each of the four profiles exactly once
isid uid prof_id
display as result "  Assertion passed: each respondent saw each profile once."

*--- the two randomised dimensions ---*
gen byte a_sc = inlist(prof_id, 1, 2)
label var a_sc "Profile is Scheduled Caste (vs the respondent's own caste)"
label define ascl 0 "Own caste" 1 "Scheduled Caste", replace
label values a_sc ascl

gen byte a_indep = inlist(prof_id, 1, 3)
label var a_indep "Profile acts independently (vs follows the elders)"
label define aind 0 "Follows the elders" 1 "Acts independently", replace
label values a_indep aind

gen byte a_sc_x_indep = a_sc * a_indep
label var a_sc_x_indep "SC x acts independently (the amplification term)"

*--- outcome transformations ---*
* Primary: the rupee amount. Coefficients read directly in rupees, which is what
* you want for prose ("respondents would spend an additional Rs X to block an
* independently acting SC mukhiya").
label var al_amt "Amount in rupees"

* Rescaled to 0-1. This is a rescaling of an INDEPENDENT measure by its
* maximum, NOT a share of a shared budget. See the header.
gen double al_frac = al_amt / 100000
label var al_frac "Amount rescaled by the Rs 1,00,000 maximum (0-1)"

* extensive margin, for the two-part model
gen byte al_any = (al_amt > 0) if !missing(al_amt)
label var al_any "Would spend anything at all to block this profile"
label define anyl 0 "Nothing" 1 "Some amount", replace
label values al_any anyl

* log for a robustness specification. log(0) is undefined, so the log
* specification necessarily conditions on a positive amount; that is the
* intensive margin of the two-part model, and it is labelled as such rather
* than fudged with log(x+1), which would silently mix the two margins.
gen double ln_amt = ln(al_amt) if al_amt > 0
label var ln_amt "Log amount, conditional on a positive amount"

compress
save "$clean/alloc_long.dta", replace
display as result "Saved: $clean/alloc_long.dta  (`n_rows' rows)"


*==============================================================================*
* SECTION 3. DESCRIPTIVES
*==============================================================================*
capture log close alloclog
log using "$out/tab_alloc_main.txt", replace text name(alloclog)

display _n "=================================================================="
display    " RESOURCE ALLOCATION EXPERIMENT"
display    ""
display    " WHAT THIS MEASURES, AND WHAT IT DOES NOT"
display    ""
display    " 1. HYPOTHETICAL STAKES. This is a stated-preference measure."
display    "    Cullen et al. (2024) is the design ancestor, but their"
display    "    real-stakes costly-signal logic DOES NOT TRANSFER to a"
display    "    hypothetical allocation. Do not describe this as a costly"
display    "    behavioural measure or as 'money burning' in the real sense."
display    ""
display    " 2. 'OWN CASTE' IS RESPONDENT-SPECIFIC. P3 and P4 are defined"
display    "    relative to each respondent's own caste, so the SC-versus-own-"
display    "    caste contrast CONFLATES anti-SC animus with generic in-group"
display    "    favouritism. The conjoint, which uses NAMED castes (Yadav,"
display    "    Rajput), partially separates these -- which is a further reason"
display    "    to report the two experiments together. Use the conjoint to"
display    "    bound how much of the allocation gap is in-group preference"
display    "    rather than SC-specific hostility."
display    ""
display    " 3. DEMAND EFFECTS. The read-aloud script explicitly disclaims"
display    "    corruption and vote-buying, which is ethically right but may cue"
display    "    socially desirable responding. q_conjoint_r is used as a"
display    "    robustness stratifier."
display    ""
display    " 4. INDEPENDENT MEASURES, NOT A SHARED BUDGET. See the file header."
display    "=================================================================="

use "$clean/alloc_long.dta", clear

display _n "--- 3.1 Distribution by profile ---"
tabstat al_amt, by(prof_id) stat(mean sd p25 p50 p75 min max n) columns(statistics)

display _n "--- 3.2 The 2x2 of means ---"
display "Rows: caste of the profile. Columns: authority style."
table a_sc a_indep, statistic(mean al_amt) statistic(sd al_amt) ///
    statistic(frequency) nformat(%9.0f)

display _n "--- 3.3 Mass at zero, by profile ---"
display "Substantial clustering at zero is expected. It is the reason the"
display "two-part model is preferred to Tobit: a respondent choosing Rs 0 is"
display "expressing a genuine preference, not a censored negative one."
tab prof_id al_any, row

display _n "--- 3.4 Distribution of amounts, pooled ---"
tab al_amt, missing
display _n "Percentiles:"
summarize al_amt, detail

display _n "--- 3.5 Order effects: does slot position matter? ---"
display "Presentation order was randomised, so slot position should be"
display "unrelated to the amount. A relationship would indicate anchoring or"
display "fatigue across the four questions."
tabstat al_amt, by(slot) stat(mean sd n)
quietly regress al_amt i.slot, vce(cluster uid)
quietly testparm i.slot
display as result "  Joint test of slot dummies: F = " %6.2f r(F) "  p = " %6.4f r(p)

display _n "--- 3.6 Non-discriminating respondents ---"
display "Respondents who gave every profile the same amount contribute no"
display "within-respondent variation and are absorbed by the fixed effects."
display "A high share would suggest the task did not discriminate, which is a"
display "measurement limitation worth reporting."
preserve
    bysort uid: keep if _n == 1
    tab al_flat, missing
restore


*==============================================================================*
* SECTION 4. PRIMARY ESTIMATION
*
* Within-subject design, so respondent fixed effects are available and are the
* primary specification. They absorb every respondent-level determinant of
* generosity, scale use, and willingness to engage with the task, leaving only
* the randomised variation across profiles.
*
*   Alloc_ip = alpha_i + b1*SC_p + b2*Indep_p + b3*(SC_p x Indep_p)
*              + lambda*SlotPosition_ip + e_ip
*
* Estimands:
*   b1        caste penalty among COMPLIANT profiles
*   b1 + b3   caste penalty among INDEPENDENT profiles
*   b3        the AMPLIFICATION effect = (P1 - P3) - (P2 - P4), a clean
*             within-respondent difference-in-differences
*
* b3 is the stated-preference analogue of the conjoint interaction (§6.3).
* Convergence between the two is a strong triangulation claim; divergence needs
* explanation and should be reported honestly rather than resolved by choosing
* whichever came out better.
*==============================================================================*
display _n(2) "=================================================================="
display       " SECTION 4. PRIMARY ESTIMATION: RESPONDENT FIXED EFFECTS"
display       "=================================================================="

eststo clear

*--- 4.1 pooled OLS, no fixed effects (reported for comparison only) ---*
display _n "--- 4.1 Pooled OLS without fixed effects (comparison only) ---"
eststo a_pool: regress al_amt i.a_sc##i.a_indep i.slot, vce(cluster uid)

*--- 4.2 respondent fixed effects: THE PRIMARY SPECIFICATION ---*
display _n "--- 4.2 PRIMARY: respondent fixed effects ---"
capture which reghdfe
if !_rc {
    eststo a_fe: reghdfe al_amt i.a_sc##i.a_indep i.slot, ///
        absorb(uid) vce(cluster uid)
}
else {
    display as txt "reghdfe not installed; using areg (official Stata, equivalent here)."
    eststo a_fe: areg al_amt i.a_sc##i.a_indep i.slot, absorb(uid) vce(cluster uid)
}

*--- extract the three estimands with confidence intervals ---*
display _n as result "  === THE THREE ESTIMANDS ==="

quietly lincom 1.a_sc
display as result "  b1  caste penalty among COMPLIANT profiles:"
display as result "        Rs " %9.0f r(estimate) "   95% CI [Rs " ///
    %9.0f r(lb) ", Rs " %9.0f r(ub) "]   p = " %6.4f r(p)

quietly lincom 1.a_sc + 1.a_sc#1.a_indep
display as result "  b1+b3  caste penalty among INDEPENDENT profiles:"
display as result "        Rs " %9.0f r(estimate) "   95% CI [Rs " ///
    %9.0f r(lb) ", Rs " %9.0f r(ub) "]   p = " %6.4f r(p)

quietly lincom 1.a_sc#1.a_indep
display as result "  b3  THE AMPLIFICATION EFFECT (within-respondent DiD):"
display as result "        Rs " %9.0f r(estimate) "   95% CI [Rs " ///
    %9.0f r(lb) ", Rs " %9.0f r(ub) "]   p = " %6.4f r(p)
display _n "  b3 = (P1 - P3) - (P2 - P4). A POSITIVE b3 means respondents would"
display    "  spend more to block an SC mukhiya specifically when that mukhiya"
display    "  acts independently, which is the allocation analogue of the"
display    "  conjoint interaction."

*--- 4.3 the four cell means from the FE model ---*
display _n "--- 4.3 Predicted cell means ---"
quietly regress al_amt i.a_sc##i.a_indep i.slot i.uid, vce(cluster uid)
margins a_sc#a_indep
display _n "  Pairwise contrasts:"
margins a_sc#a_indep, pwcompare(effects)

*--- 4.4 rescaled outcome ---*
display _n "--- 4.4 Same specification on the rescaled outcome (0-1) ---"
display "A rescaling of the independent measure, NOT a share of a shared budget."
capture which reghdfe
if !_rc {
    eststo a_fe_frac: reghdfe al_frac i.a_sc##i.a_indep i.slot, ///
        absorb(uid) vce(cluster uid)
}
else {
    eststo a_fe_frac: areg al_frac i.a_sc##i.a_indep i.slot, ///
        absorb(uid) vce(cluster uid)
}
quietly lincom 1.a_sc#1.a_indep
display as result "  b3 on the 0-1 scale = " %7.4f r(estimate) ///
    "  [" %7.4f r(lb) ", " %7.4f r(ub) "]"

*--- 4.5 standardised, so the estimate is comparable to the plan's MDE ---*
* The plan's approximate MDE for this design is 0.23 SD of the DiD. Expressing
* b3 in SD units makes it directly comparable to that figure, and the SD-unit
* figure is assumption-free whereas the rupee equivalent depends on the realised
* SD, which was unknown before data collection.
display _n "--- 4.5 In SD units, for comparison with the design MDE ---"
quietly summarize al_amt
local sd_amt = r(sd)
display "  SD of the amount across all profile observations: Rs " %9.0f `sd_amt'

* the SD that matters for the DiD is the SD of the within-respondent DiD itself
preserve
    keep uid prof_id al_amt
    reshape wide al_amt, i(uid) j(prof_id)
    gen double did = (al_amt1 - al_amt3) - (al_amt2 - al_amt4)
    label var did "Within-respondent difference-in-differences, rupees"
    summarize did, detail
    local sd_did = r(sd)
    local mean_did = r(mean)
    display _n as result "  Mean within-respondent DiD  = Rs " %9.0f `mean_did'
    display    as result "  SD of within-respondent DiD = Rs " %9.0f `sd_did'
    if `sd_did' > 0 {
        display as result "  DiD in SD units             = " %6.3f `mean_did'/`sd_did'
        display _n "  The plan's approximate MDE was 0.23 SD of the DiD."
        display    "  At the realised SD of Rs " %9.0f `sd_did' " that is"
        display    "  approximately Rs " %9.0f 0.23*`sd_did' "."
    }

    * one-sample t-test on the DiD. This is algebraically the same estimand as
    * b3 from the FE regression and is reported because it makes the
    * within-respondent logic transparent: each respondent contributes exactly
    * one number, and the test asks whether its mean differs from zero.
    display _n "  One-sample t-test on the within-respondent DiD:"
    ttest did == 0

    save "$clean/alloc_did.dta", replace
restore

log close alloclog

capture which esttab
if !_rc {
    esttab a_pool a_fe a_fe_frac using "$out/tab_alloc_main.rtf", replace ///
        keep(1.a_sc 1.a_indep 1.a_sc#1.a_indep) ///
        b(0) se(0) star(* 0.10 ** 0.05 *** 0.01) ///
        stats(N r2, fmt(0 3) labels("Profile observations" "R-squared")) ///
        mtitles("Pooled OLS" "Respondent FE" "Respondent FE (0-1)") ///
        title("Resource allocation: amount spent to block each profile") ///
        addnotes("Respondent fixed effects is the primary specification." ///
                 "The interaction is a within-respondent difference-in-" ///
                 "differences: (P1-P3) - (P2-P4)." ///
                 "STATED PREFERENCE, hypothetical stakes. Not a costly" ///
                 "behavioural measure." ///
                 "Own caste is respondent-specific, so the caste contrast" ///
                 "conflates anti-SC animus with in-group favouritism.") ///
        label
}


*==============================================================================*
* SECTION 5. TWO-PART MODEL   (§7.3)
*
* WHY NOT TOBIT. Tobit assumes a latent continuous variable censored at zero.
* Here zero is a GENUINE PREFERRED ALLOCATION, not a censored value: a
* respondent choosing Rs 0 is expressing a real preference, not a suppressed
* negative one. The two-part model matches the data-generating process better
* and is much easier to defend in a viva.
*
* PART ONE   extensive margin: does the respondent spend anything at all?
* PART TWO   intensive margin: given a positive amount, how much?
*
* The two margins can move in opposite directions, and if they do that is a
* finding: it would mean the caste-authority combination changes WHO is willing
* to oppose the candidate at all, separately from HOW HARD those already willing
* would push.
*==============================================================================*
use "$clean/alloc_long.dta", clear

capture log close twopartlog
log using "$out/tab_alloc_twopart.txt", replace text name(twopartlog)

display _n "=================================================================="
display    " TWO-PART MODEL"
display    ""
display    " Tobit is deliberately avoided as the primary specification: zero"
display    " here is a genuine preferred allocation, not a censored value."
display    "=================================================================="

*------------------------------------------------------------------------------*
* 5.1 Extensive margin
*
* LPM with respondent fixed effects is the primary version because the
* coefficients read as percentage-point changes in the probability of spending
* anything. Conditional logit is reported alongside: it is the correct
* fixed-effects estimator for a binary outcome, but it drops respondents with no
* variation in the outcome, so its sample is smaller and its estimand is
* conditional on that subsample.
*------------------------------------------------------------------------------*
display _n "--- 5.1 EXTENSIVE MARGIN: any amount at all ---"
tab al_any, missing

display _n "  Linear probability model with respondent FE:"
capture which reghdfe
if !_rc {
    reghdfe al_any i.a_sc##i.a_indep i.slot, absorb(uid) vce(cluster uid)
}
else {
    areg al_any i.a_sc##i.a_indep i.slot, absorb(uid) vce(cluster uid)
}
quietly lincom 1.a_sc#1.a_indep
display as result "    b3 (extensive) = " %7.4f r(estimate) ///
    "  [" %7.4f r(lb) ", " %7.4f r(ub) "]  p = " %6.4f r(p)

display _n "  Conditional (fixed-effects) logit, for comparison:"
display    "  Note this drops respondents whose al_any does not vary across the"
display    "  four profiles, so the sample and the estimand both change."
capture noisily clogit al_any i.a_sc##i.a_indep i.slot, group(uid) vce(cluster uid)
if _rc {
    display as txt "    clogit did not converge or all groups lack variation."
}

*------------------------------------------------------------------------------*
* 5.2 Intensive margin
*------------------------------------------------------------------------------*
display _n "--- 5.2 INTENSIVE MARGIN: amount conditional on spending anything ---"
quietly count if al_any == 1
display "  Observations with a positive amount: `r(N)'"

display _n "  Level specification, respondent FE:"
capture which reghdfe
if !_rc {
    reghdfe al_amt i.a_sc##i.a_indep i.slot if al_any == 1, ///
        absorb(uid) vce(cluster uid)
}
else {
    areg al_amt i.a_sc##i.a_indep i.slot if al_any == 1, ///
        absorb(uid) vce(cluster uid)
}
quietly lincom 1.a_sc#1.a_indep
display as result "    b3 (intensive, rupees) = Rs " %9.0f r(estimate) ///
    "  [Rs " %9.0f r(lb) ", Rs " %9.0f r(ub) "]"

display _n "  Log specification, respondent FE (coefficients read as"
display    "  approximate proportional changes):"
capture which reghdfe
if !_rc {
    reghdfe ln_amt i.a_sc##i.a_indep i.slot, absorb(uid) vce(cluster uid)
}
else {
    areg ln_amt i.a_sc##i.a_indep i.slot, absorb(uid) vce(cluster uid)
}
quietly lincom 1.a_sc#1.a_indep
display as result "    b3 (intensive, log) = " %7.4f r(estimate) ///
    "  [" %7.4f r(lb) ", " %7.4f r(ub) "]"

display _n "--- 5.3 Reading the two margins together ---"
display "If the extensive and intensive margins point the same way, the"
display "interpretation is straightforward. If they diverge, that is itself a"
display "finding: the caste-authority combination would be changing WHO is"
display "willing to oppose the candidate at all, separately from HOW HARD those"
display "already willing would push. Report both rather than collapsing them."

*------------------------------------------------------------------------------*
* 5.4 Tobit, reported only because a reader may expect to see it
*------------------------------------------------------------------------------*
display _n "--- 5.4 Tobit (reported for completeness, NOT preferred) ---"
display "Included because a reader may ask. The assumption that zero is a"
display "censored latent negative value is not defensible here, so this is a"
display "comparison point, not an estimate to rely on."
capture noisily tobit al_amt i.a_sc##i.a_indep i.slot, ll(0) vce(cluster uid)
if !_rc {
    capture {
        quietly lincom 1.a_sc#1.a_indep
        display as result "    b3 (Tobit latent scale) = " %9.0f r(estimate)
        display as txt "    Note this is on the LATENT scale and is not"
        display as txt "    comparable to the FE estimates above without a"
        display as txt "    marginal-effects transformation."
    }
}

log close twopartlog


*==============================================================================*
* SECTION 6. RANK-BASED TEST   (§7.3)
*
* The Wilcoxon signed-rank test on the within-respondent contrast is robust to
* the discreteness of the 21-point response scale and to the floor clustering at
* zero. It makes no distributional assumption about the amounts, so it is the
* check to lean on if the amount distribution turns out to be badly behaved.
*==============================================================================*
use "$clean/alloc_long.dta", clear

capture log close ranklog
log using "$out/tab_alloc_ranktests.txt", replace text name(ranklog)

display _n "=================================================================="
display    " RANK-BASED WITHIN-RESPONDENT TESTS"
display    ""
display    " Robust to the 21-point discreteness and the mass at zero. No"
display    " distributional assumption on the amounts."
display    "=================================================================="

preserve
    keep uid prof_id al_amt
    reshape wide al_amt, i(uid) j(prof_id)
    rename al_amt1 amt_sc_indep
    rename al_amt2 amt_sc_compl
    rename al_amt3 amt_own_indep
    rename al_amt4 amt_own_compl
    label var amt_sc_indep  "P1: SC, independent"
    label var amt_sc_compl  "P2: SC, follows elders"
    label var amt_own_indep "P3: own caste, independent"
    label var amt_own_compl "P4: own caste, follows elders"

    display _n "--- 6.1 Means and medians of the four profiles ---"
    summarize amt_sc_indep amt_sc_compl amt_own_indep amt_own_compl, detail

    display _n "--- 6.2 P1 vs P3: the caste contrast among INDEPENDENT profiles ---"
    display "This is the plan's headline within-respondent contrast."
    signrank amt_sc_indep = amt_own_indep

    display _n "--- 6.3 P2 vs P4: the caste contrast among COMPLIANT profiles ---"
    signrank amt_sc_compl = amt_own_compl

    display _n "--- 6.4 P1 vs P2: the authority contrast among SC profiles ---"
    signrank amt_sc_indep = amt_sc_compl

    display _n "--- 6.5 P3 vs P4: the authority contrast among own-caste profiles ---"
    signrank amt_own_indep = amt_own_compl

    display _n "--- 6.6 The difference-in-differences, rank test ---"
    gen double did = (amt_sc_indep - amt_own_indep) - ///
                     (amt_sc_compl - amt_own_compl)
    label var did "Within-respondent DiD"
    summarize did, detail
    display _n "  Sign test that the DiD median is zero:"
    signrank did = 0

    display _n "--- 6.7 Direction of the individual DiDs ---"
    display "How many respondents show amplification, no change, or the"
    display "opposite? A finding that rests on a minority of respondents with"
    display "large values is different from one that reflects a broad shift, and"
    display "the mean alone cannot distinguish them."
    gen byte did_sign = 0
    replace did_sign = 1  if did > 0
    replace did_sign = -1 if did < 0
    label define dsign -1 "Opposite direction" 0 "No difference" ///
                        1 "Amplification" , replace
    label values did_sign dsign
    tab did_sign, missing
restore

log close ranklog

*--- FIGURE: the four cells ---*
use "$clean/alloc_long.dta", clear
capture which reghdfe
if !_rc {
    quietly reghdfe al_amt i.a_sc##i.a_indep i.slot, absorb(uid) vce(cluster uid)
}
else {
    quietly areg al_amt i.a_sc##i.a_indep i.slot, absorb(uid) vce(cluster uid)
}
quietly margins a_sc#a_indep, post
capture which coefplot
if !_rc {
    coefplot, vertical ciopts(recast(rcap)) ///
        ytitle("Rupees spent to reduce the profile's chances") ///
        title("Allocation experiment: the 2x2", size(medium)) ///
        subtitle("Respondent fixed effects, 95% confidence intervals", size(small)) ///
        note("Stated preference, hypothetical stakes. 'Own caste' is" ///
             "respondent-specific, so the caste contrast conflates anti-SC" ///
             "animus with in-group favouritism.", size(vsmall)) ///
        graphregion(color(white))
    graph export "$out/fig_alloc_cells.png", replace width(2000)
}


*==============================================================================*
* SECTION 7. ROBUSTNESS AND HETEROGENEITY
*==============================================================================*
use "$clean/alloc_long.dta", clear

capture log close allocroblog
log using "$out/tab_alloc_robustness.txt", replace text name(allocroblog)

display _n "=================================================================="
display    " ALLOCATION EXPERIMENT: ROBUSTNESS AND HETEROGENEITY"
display    "=================================================================="

*--- helper to report b3 under a restriction ---*
capture program drop b3under
program define b3under
    args restriction lbl
    capture which reghdfe
    if !_rc {
        quietly reghdfe al_amt i.a_sc##i.a_indep i.slot `restriction', ///
            absorb(uid) vce(cluster uid)
    }
    else {
        quietly areg al_amt i.a_sc##i.a_indep i.slot `restriction', ///
            absorb(uid) vce(cluster uid)
    }
    capture {
        quietly lincom 1.a_sc#1.a_indep
        display "  " %-32s "`lbl'" " b3 = Rs " %9.0f r(estimate) ///
            "  [Rs " %9.0f r(lb) ", Rs " %9.0f r(ub) "]  n = " e(N)
    }
end

display _n "--- 7.1 Sample restrictions ---"
b3under ""                          "Baseline (all respondents)"
b3under "if q_conjoint_r == 3"      "Understood the task well"
b3under "if q_conjoint_r >= 2"      "At most some difficulty"
b3under "if self_resp == 1"         "Self-respondents only"
b3under "if lowqual == 0"           "Excluding low-quality interviews"
b3under "if al_flat == 0"           "Excluding flat allocators"
capture b3under "if speeder == 0"   "Excluding speeders"

display _n "--- 7.2 Excluding respondents who allocated zero throughout ---"
display "These respondents contribute no within-respondent variation, so they"
display "are already absorbed by the fixed effects. Excluding them explicitly"
display "confirms they are not affecting the estimate through the SE."
bysort uid: egen double _maxamt = max(al_amt)
b3under "if _maxamt > 0"            "At least one positive allocation"
drop _maxamt

display _n "--- 7.3 Heterogeneity by prejudice ---"
display "As with the conjoint, this is exploratory: a within-respondent DiD"
display "split across two subgroups of roughly 75 is thinly powered."
capture {
    quietly summarize prej_pc1, detail
    local pmed = r(p50)
    gen byte high_prej = (prej_pc1 > `pmed') if !missing(prej_pc1)
    label var high_prej "Above-median prejudice index"
    b3under "if high_prej == 0"     "Below-median prejudice"
    b3under "if high_prej == 1"     "Above-median prejudice"

    display _n "  Continuous moderation (triple interaction):"
    capture which reghdfe
    if !_rc {
        quietly reghdfe al_amt i.a_sc##i.a_indep##c.prej_pc1 i.slot, ///
            absorb(uid) vce(cluster uid)
    }
    else {
        quietly areg al_amt i.a_sc##i.a_indep##c.prej_pc1 i.slot, ///
            absorb(uid) vce(cluster uid)
    }
    capture {
        quietly lincom 1.a_sc#1.a_indep#c.prej_pc1
        display "    triple interaction = " %9.0f r(estimate) ///
            "  [" %9.0f r(lb) ", " %9.0f r(ub) "]  p = " %6.4f r(p)
    }
}

display _n "--- 7.4 Heterogeneity by respondent's own caste category ---"
display "Because 'own caste' is respondent-specific, the P3/P4 profiles mean"
display "something different for a General respondent than for a BC-1 one. If"
display "b3 differs sharply across categories, that is informative about how"
display "much of the contrast is in-group preference."
capture {
    forvalues c = 1/3 {
        b3under "if caste_cat_n == `c'" "Own caste category = `c'"
    }
}

display _n "--- 7.5 Convergence with the conjoint ---"
display "The conjoint interaction (08_conjoint_amce.do) and this b3 are"
display "measuring the same construct through different designs and different"
display "response formats. Convergence is a strong triangulation claim."
display "Divergence needs explaining and should be reported honestly rather"
display "than resolved by preferring whichever came out better."
display ""
display "Note that the two are NOT on the same scale: the conjoint interaction"
display "is in probability units and b3 is in rupees. Compare the SIGN and the"
display "standardised magnitude, not the raw coefficients."
display ""
display "Two further reasons the two need not agree exactly:"
display "  1. The conjoint uses named castes (Yadav, Rajput) while the"
display "     allocation uses the respondent's own caste, so the comparison"
display "     groups differ."
display "  2. The conjoint outcome is a forced choice between two profiles;"
display "     the allocation outcome is an absolute amount per profile. These"
display "     elicit different things from a respondent."

log close allocroblog

display as result _n "=== 09_alloc.do complete ==="
display as txt "Long data:      $clean/alloc_long.dta"
display as txt "DiD by person:  $clean/alloc_did.dta"
display as txt "Main results:   $out/tab_alloc_main.txt (+ .rtf)"
display as txt "Two-part:       $out/tab_alloc_twopart.txt"
display as txt "Rank tests:     $out/tab_alloc_ranktests.txt"
display as txt "Robustness:     $out/tab_alloc_robustness.txt"
display as txt "Figure:         $out/fig_alloc_cells.png"

*==============================================================================*
* END 09_alloc.do
*==============================================================================*

*==============================================================================*
* 04_qc_paradata.do
*
* PURPOSE : Data-quality and paradata checks. Implements §1.4, §1.5, §9.2 and
*           §9.3 of the analysis plan.
*
* INPUT   : $clean/sc_analysis.dta, $clean/nonsc_analysis.dta,
*           $clean/sc_nonresponse.dta
* 			$clean/nonsc_nonresponse.dta
* OUTPUT  : $out/qc_report.txt              -- the readable QC report
*           $out/tab_refusal_rates.txt      -- item-level refusal, §9.2
*           $clean/sc_analysis.dta          -- updated with QC flags
*           $clean/nonsc_analysis.dta       -- updated with QC flags
*
* Run this BEFORE any estimation and read the report. Several of the decisions
* left open in 00_master.do (block clustering, speeding threshold) can only be
* settled from this output.
*==============================================================================*

capture log close qclog
log using "$out/qc_report.txt", replace text name(qclog)

display _n "=================================================================="
display    " DATA QUALITY AND PARADATA REPORT"
display    " Generated: $S_DATE $S_TIME"
display    "=================================================================="


*==============================================================================*
* PART A. SC SURVEY
*==============================================================================*
use "$clean/sc_analysis.dta", clear

display _n(2) "##################################################################"
display       "# A. SC SURVEY (n = " _N ")"
display       "##################################################################"

*------------------------------------------------------------------------------*
* A1. Sample composition and completeness
*------------------------------------------------------------------------------*
display _n "--- A1.1 Records by sample group (from the frame merge) ---"
capture tab sample_group, missing
if _rc display "sample_group not available; frame merge may not have run."

display _n "--- A1.2 Geographic coverage ---"
capture tab district, missing
capture {
    * Panchayats per block. This determines whether block-level clustering is
    * meaningful: with roughly one panchayat per block there is nothing to
    * cluster, and cluster-robust SEs with many singleton clusters can be
    * badly behaved. Set $use_block_cluster in 00_master.do from this output.
    preserve
        contract district block
        display _n "Distribution of panchayats per block:"
        summarize _freq, detail
        count if _freq == 1
        display "Blocks contributing exactly one panchayat: `r(N)' of " _N
    restore
}

display _n "--- A1.3 Sample purity ---"
tab caste_category, missing
capture tab sc_purity_flag, missing

display _n "--- A1.4 Proxy respondents (§1.5: these ARE data, not just noise) ---"
* In a study about proxy governance, a husband or father-in-law answering on
* behalf of an elected mukhiya is proxy governance enacted in the interview
* itself. Reported as an outcome here, used as a covariate in 06_assoc_sc.do,
* and used as a robustness exclusion for all experience-based items.
tab proxy_resp, missing
capture tab proxy_rel, missing
display _n "Proxy status by gender of the elected mukhiya:"
display    "(this is where the intersectional dimension becomes visible in the"
display    " quantitative arm, notwithstanding the male-only qualitative sample)"
capture tab mukh_sex_n proxy_resp, row chi2
display _n "Proxy status by self-reported final decision authority:"
capture tab auth_final_ord proxy_resp, row

*------------------------------------------------------------------------------*
* A2. Item-level missingness
*------------------------------------------------------------------------------*
display _n "--- A2 Missingness on analysis variables ---"
* misstable summarize lists only variables that HAVE missing values, which is
* what you want: a short list of problems rather than a long list of successes.
misstable summarize auth_idx auth_tasks eff_idx kn_demo_idx ma_idx ///
    bl_bureau_idx bl_social_idx bl_symbol_idx vb_idx wb_idx ///
    educ_ord gp_scshare_ord ln_gp_pop n_terms n_stood, all

display _n "Observations built on fewer than half an index's components:"
foreach ix in auth_idx eff_idx ma_idx bl_bureau_idx bl_social_idx ///
              bl_symbol_idx vb_idx wb_idx {
    capture {
        quietly count if `ix'_thin == 1
        display "  `ix': `r(N)'"
    }
}

*------------------------------------------------------------------------------*
* A3. "Prefer not to say" is not missing at random  (§9.2)
*
* Refusal on a sensitive backlash item is very unlikely to be independent of
* the answer. It may indicate concealment of experienced backlash, or
* reluctance to accuse a named actor, and THE DIRECTION IS NOT KNOWABLE A
* PRIORI. Three things follow, all implemented here or in 05_desc_sc.do:
*   1. Report the refusal rate per item. High-refusal items are substantively
*      informative about which topics are hardest to discuss.
*   2. Primary analysis treats refusal as missing (complete-case within index).
*   3. Manski bounds on every primary prevalence estimate (05_desc_sc.do).
* Plus: test whether refusal propensity correlates with the authority index.
*------------------------------------------------------------------------------*
display _n "--- A3.1 Item-level refusal rates ---"

* count refusal flags across all sensitive items
local pnsvars ""
foreach v of varlist *_pns {
    local pnsvars "`pnsvars' `v'"
}

capture confirm variable ma_surprise_pns
if !_rc {
    * respondent-level refusal propensity: how many sensitive items each
    * respondent declined. This is the variable to correlate with authority.
    egen byte pns_count = rowtotal(`pnsvars')
    label var pns_count "Number of sensitive items the respondent declined"

    egen byte pns_k = rownonmiss(`pnsvars')
    gen double pns_rate = pns_count / pns_k
    label var pns_rate "Share of sensitive items declined"

    summarize pns_count pns_rate, detail

    display _n "--- A3.2 Does refusal propensity correlate with key variables? ---"
    display    "If it does, the missingness is informative and the complete-case"
    display    "estimates are biased in a direction the bounds will reveal."
    correlate pns_rate auth_idx eff_idx kn_demo_idx educ_ord n_terms
    display _n "Refusal rate by proxy status:"
    tabstat pns_rate, by(proxy_resp) stat(mean sd n)
    display _n "Refusal rate by enumerator account:"
    capture tabstat pns_rate, by(kobo_user) stat(mean sd n)
}

*------------------------------------------------------------------------------*
* A4. Interview duration and speeding
*------------------------------------------------------------------------------*
display _n "--- A4 Interview duration ---"
capture {
    summarize dur_min, detail
    display _n "Duration percentiles inform the speeding threshold."
    display    "Current \$speed_min = $speed_min minutes."

    gen byte speeder = (dur_min < $speed_min) if !missing(dur_min)
    label var speeder "Interview shorter than \$speed_min minutes"
    tab speeder, missing

    display _n "Duration by enumerator account:"
    tabstat dur_min, by(kobo_user) stat(mean sd min p25 p50 p75 max n)

    display _n "Do speeders differ on the outcome indices?"
    display    "A systematic difference suggests the short interviews are"
    display    "producing lower-quality data rather than just efficient ones."
    tabstat auth_idx ma_idx bl_bureau_idx pns_rate, by(speeder) stat(mean sd n)
}

* NOTE ON THE KOBO AUDIT LOG
* Both forms enable the audit paradata log, which records per-question timing.
* That is the better source for speeding detection than end - start, because it
* catches respondents who were fast on the sensitive modules specifically while
* taking a normal total time. If you have exported audit.csv, the block below
* gives a starting point; it is commented out because the export format varies.
/*
    preserve
        import delimited using "$f_audit_sc", encoding("UTF-8") varnames(1) clear
        * Typical audit columns: event, node, start, end (epoch ms).
        * VERIFY the column names in your export before relying on this.
        keep if event == "question"
        gen double q_secs = (end - start) / 1000
        * node holds the XPath; extract the module from it
        gen str8 module = ""
        replace module = "D" if strpos(node, "mod_d") > 0
        replace module = "E" if strpos(node, "mod_e") > 0
        replace module = "F" if strpos(node, "mod_f") > 0
        collapse (sum) q_secs, by(instance_id module)
        * then reshape wide and merge on the survey's uuid
    restore
*/

*------------------------------------------------------------------------------*
* A5. Enumerator effects  (§1.2 -- a real gap in the instruments)
*
* NEITHER FORM CONTAINS AN enum_id FIELD. Both capture username, which records
* the DEVICE OR ACCOUNT, not the interviewer. If enumerators share accounts or
* devices, enumerator effects are unidentifiable. This is a genuine loss:
* interviewer effects on sensitive caste items are typically large and are a
* standard robustness concern for telephonic sensitive-topic surveys.
*
* RECOMMENDATION, if fieldwork has not finished: add a required enum_id
* (a select_one from the enumerator roster, not free text). If fieldwork is
* complete: ask CKSingh for a call-level enumerator assignment log keyed to uid
* and merge it in here.
*------------------------------------------------------------------------------*
display _n "--- A5 Enumerator / account effects ---"
display    "CAVEAT: kobo_user is the DEVICE OR ACCOUNT, not the interviewer."
display    "Treat what follows as an account-level variance decomposition, not"
display    "an enumerator analysis, unless you have merged an assignment log."

capture {
    tab kobo_user, missing

    * A one-way ANOVA of a sensitive index on the account gives an approximate
    * share of variance attributable to the account. A large share is a red
    * flag for interviewer effects on sensitive reporting.
    display _n "Variance decomposition of sensitive indices by account:"
    foreach y in ma_idx bl_bureau_idx bl_social_idx vb_idx pns_rate {
        display _n "  Outcome: `y'"
        capture anova `y' kobo_user
        if !_rc {
            display "    R-squared (share of variance across accounts) = " %5.3f e(r2)
        }
    }
}

* If an enumerator assignment log becomes available, merge it here:
/*
    merge 1:1 uid using "$raw/enum_assignment.dta", keepusing(enum_id) gen(_menum)
    tab _menum
    drop if _menum == 2
    drop _menum
    encode enum_id, gen(enum_n)
    label var enum_n "Enumerator (from CKSingh assignment log)"
*/

*------------------------------------------------------------------------------*
* A6. Enumerator judgement vs self-report
*
* q_indep is the enumerator's own assessment of whether the respondent was an
* independently acting mukhiya. It is a useful triangulation of the self-
* reported authority index. If they diverge sharply, that is worth discussing
* rather than hiding: it speaks to the difficulty of measuring independence at
* all, which is itself a methodological finding.
*------------------------------------------------------------------------------*
display _n "--- A6 Enumerator judgement of independence vs self-report ---"
capture {
    tab q_indep, missing
    display _n "Authority index by enumerator judgement:"
    tabstat auth_idx auth_tasks auth_final_ord, by(q_indep_b) stat(mean sd n)

    display _n "Cross-tabulation with the self-described proxy indicator:"
    tab auth_proxy_self q_indep_b, row col

    * Simple agreement statistic. kap gives Cohen's kappa for two raters on the
    * same units; here the "raters" are the respondent's self-report (recoded to
    * a binary) and the enumerator's judgement.
    gen byte self_indep_b = 1 - auth_proxy_self
    label var self_indep_b "Self-report: makes final decisions (not a proxy)"
    display _n "Agreement between self-report and enumerator judgement:"
    capture kap self_indep_b q_indep_b
    if _rc display "kap failed (likely because one variable has no variation)."
}

*------------------------------------------------------------------------------*
* A7. Interview quality
*------------------------------------------------------------------------------*
display _n "--- A7 Interview quality (enumerator assessment, reversed so 4 = best) ---"
tab q_underst_r, missing
tab q_sincere_r, missing
tab lowqual, missing

display _n "Do low-quality interviews differ on the outcomes?"
tabstat auth_idx ma_idx bl_bureau_idx wb_idx, by(lowqual) stat(mean sd n)

*------------------------------------------------------------------------------*
* A8. Open-text fields
*
* Open text from a 150-respondent survey is a genuine analytical resource for
* interpreting anomalies, not a courtesy field. Read it. Export it so it can be
* read alongside the qualitative corpus.
*------------------------------------------------------------------------------*
display _n "--- A8 Open-text availability ---"
capture {
    gen byte has_open = (!missing(open_txt) & trim(open_txt) != "")
    gen byte has_notes = (!missing(q_notes) & trim(q_notes) != "")
    tab has_open
    tab has_notes

    preserve
        keep if has_open == 1 | has_notes == 1
        keep uid open_txt q_notes q_indep auth_idx bl_cnt
        export excel using "$out/qc_open_text_sc.xlsx", ///
            firstrow(variables) replace
    restore
    display "Exported to $out/qc_open_text_sc.xlsx for qualitative reading."
}

*------------------------------------------------------------------------------*
* A9. Save with QC flags
*------------------------------------------------------------------------------*
compress
save "$clean/sc_analysis.dta", replace


*==============================================================================*
* PART B. NON-SC SURVEY
*==============================================================================*
use "$clean/nonsc_analysis.dta", clear

display _n(2) "##################################################################"
display       "# B. NON-SC SURVEY (n = " _N ")"
display       "##################################################################"

display _n "--- B1 Sample composition ---"
capture tab sample_group, missing
capture tab district, missing
tab caste_cat_n, missing
capture tab ns_purity_flag, missing

display _n "--- B2 Proxy respondents ---"
tab proxy_resp, missing
capture tab mukh_sex_n proxy_resp, row

display _n "--- B3 Missingness ---"
misstable summarize auth_idx eff_idx kn_demo_idx prej_pc1 wb_idx ///
    educ_ord gp_scshare_ord ln_gp_pop, all

display _n "--- B4 Attitude battery refusal rates (likert_agree_pns) ---"
local atpns att_res_bad_pns att_res_miss_pns att_res_incapable_pns att_res_hamlets_pns 	///
			att_stereo_help_pns att_stereo_officials_pns att_stereo_nocaste_pns			///
            att_poa_unjust_pns att_poa_fake_pns att_vb_cooperate_pns att_vb_misuse_pns
egen byte pns_count = rowtotal(`atpns')
label var pns_count "Number of attitude items declined"
egen byte pns_k = rownonmiss(`atpns')
gen double pns_rate = pns_count / pns_k
label var pns_rate "Share of attitude items declined"
summarize pns_count pns_rate, detail

display _n "Refusal by item (mean of the flag = refusal rate):"
summarize `atpns'

display _n "Does refusal propensity correlate with measured prejudice?"
display    "It plausibly does: a respondent unwilling to state a prejudicial"
display    "view may hold one. If so, prej_pc1 is attenuated among refusers"
display    "and the heterogeneity analysis is conservative."
correlate pns_rate prej_pc1 educ_ord auth_idx

display _n "--- B5 Duration and speeding ---"
capture {
    summarize dur_min, detail
    gen byte speeder = (dur_min < $speed_min) if !missing(dur_min)
    label var speeder "Interview shorter than \$speed_min minutes"
    tab speeder, missing
    tabstat dur_min, by(kobo_user) stat(mean sd p50 n)
}

display _n "--- B6 Conjoint and allocation comprehension ---"
display    "q_conjoint_r is the enumerator's assessment, reversed so 3 = best."
display    "Used as a robustness stratifier in 08 and 09: if the estimates are"
display    "driven by respondents who did not grasp the task, that matters."
tab q_conjoint_r, missing

display _n "Does comprehension vary by education or account?"
capture tabstat q_conjoint_r, by(educ_ord) stat(mean n)
capture tabstat q_conjoint_r, by(kobo_user) stat(mean n)

display _n "--- B7 Conjoint randomisation diagnostics (wide form) ---"
display    "Expected: profile A caste marginals 0.50 sc / 0.25 yadav /"
display    "0.25 rajput; other attributes 0.50/0.50. Profile B departs slightly"
display    "from these because of the flip guard. Full diagnostics on the"
display    "reshaped long data are in 08_conjoint_amce.do."
foreach t in 1 2 3 4 5 {
    display _n "  Task `t':"
    tab cj_caste_a`t' cj_caste_b`t'
}

display _n "Flip-guard firing rate by task:"
display    "Design expectation: 0.375 x 0.5^3 = approximately 4.7% of tasks."
foreach t in 1 2 3 4 5 {
    quietly count if cj_flip`t' == 1
    local fired = r(N)
    quietly count if !missing(cj_flip`t')
    display "  task `t': `fired' of `r(N)' tasks"
}

display _n "--- B8 Allocation experiment sanity ---"
summarize al_amt1 al_amt2 al_amt3 al_amt4 al_total, detail
display _n "Slot-to-profile assignment (presentation order was randomised):"
foreach k in 1 2 3 4 {
    tab al_prof`k'
}
display _n "Respondents allocating zero to every profile:"
count if al_amt1 == 0 & al_amt2 == 0 & al_amt3 == 0 & al_amt4 == 0
display "  `r(N)' respondents. These contribute no within-respondent variation"
display "  and will be absorbed by the respondent fixed effects in 09_alloc.do."

display _n "Respondents allocating the SAME amount to every profile:"
gen byte al_flat = (al_amt1 == al_amt2 & al_amt2 == al_amt3 & al_amt3 == al_amt4) ///
                   if !missing(al_amt1, al_amt2, al_amt3, al_amt4)
label var al_flat "Allocated an identical amount to all four profiles"
tab al_flat, missing
display "  Flat allocators also contribute no within-respondent variation."
display "  A high share would suggest the task was not discriminating and is"
display "  worth reporting as a measurement limitation."

display _n "--- B9 Open text ---"
capture {
    gen byte has_open = (!missing(open_txt) & trim(open_txt) != "")
    gen byte has_notes = (!missing(q_notes) & trim(q_notes) != "")
    tab has_open
    tab has_notes
    preserve
        keep if has_open == 1 | has_notes == 1
        keep uid open_txt q_notes prej_pc1 q_conjoint_r
        export excel using "$out/qc_open_text_nonsc.xlsx", ///
            firstrow(variables) replace
    restore
}

compress
save "$clean/nonsc_analysis.dta", replace


*==============================================================================*
* PART C. NON-RESPONSE ANALYSIS
*
* Requires the frame merge (01_import_merge.do part C), which saved the frame
* records with no matching survey. Non-response is only analysable because the
* frame carries characteristics for units that were never interviewed.
*
* WHAT THIS CAN AND CANNOT DO. The frame holds district, block, gp and stratum,
* so you can test whether response rates differ across those. It does not hold
* attitudes or authority, so you cannot test whether non-responders differ on
* the outcomes. Differential response by geography or stratum is nonetheless
* worth reporting: it bears directly on whether the realised sample is
* representative of the frame.
*==============================================================================*
display _n(2) "##################################################################"
display       "# C. NON-RESPONSE"
display       "##################################################################"

foreach s in sc nonsc {
    capture confirm file "$clean/`s'_nonresponse.dta"
    if _rc {
        display _n "No non-response file for `s'. Either the frame merge did not"
        display    "run, or every sampled unit responded (implausible)."
        continue
    }

    display _n "--- `s': response by stratum and district ---"
    preserve
        * stack respondents and non-respondents to compute response rates
        use "$clean/`s'_analysis.dta", clear
        keep uid
        gen byte responded = 1
        tempfile resp
        save `resp'

        use "$clean/`s'_nonresponse.dta", clear
        gen byte responded = 0
        append using `resp'

        * frame characteristics only exist on the non-response rows unless we
        * re-merge; do that so the crosstabs are complete.
        capture merge m:1 uid using "$f_frame", ///
            keepusing(strata district block sample_group) update gen(_mf)
        capture drop _mf

        display _n "Overall response rate:"
        tab responded

        display _n "Response rate by stratum:"
        capture tab strata responded, row

        display _n "Response rate by sample group (pilot / main / reserve):"
        capture tab sample_group responded, row

        display _n "Response rate by district:"
        capture tab district responded, row chi2
        display "A significant chi-squared here means response propensity"
        display "varies geographically, which should be reported and, if"
        display "severe, addressed with district fixed effects or weights."
    restore
}


*==============================================================================*
* PART D. ITEM-LEVEL REFUSAL TABLE  (§9.2, exported separately)
*
* High-refusal items are substantively informative about which topics are
* hardest to discuss, so this deserves to be a table in the dissertation rather
* than only a diagnostic.
*==============================================================================*
capture log close refuselog
log using "$out/tab_refusal_rates.txt", replace text name(refuselog)

display _n "=================================================================="
display    " ITEM-LEVEL REFUSAL RATES ('prefer not to say')"
display    ""
display    " Refusal on a sensitive item is very unlikely to be independent of"
display    " the answer, and the direction is not knowable a priori. These"
display    " rates are reported as substantive findings about which topics are"
display    " hardest to discuss, and they determine which prevalence estimates"
display    " need Manski bounds (see 05_desc_sc.do)."
display    "=================================================================="

use "$clean/sc_analysis.dta", clear

display _n "--- SC survey ---"
display _n "Microaggression items:"
foreach v of global MA_INSULT {
    quietly summarize `v'_pns
    display "  " %-18s "`v'" "  refusal rate = " %5.1f 100*r(mean) "%   (n = " r(N) ")"
}
foreach v in ma_bypass ma_slur ma_ignored ma_food ma_wait {
    quietly summarize `v'_pns
    display "  " %-18s "`v'" "  refusal rate = " %5.1f 100*r(mean) "%   (n = " r(N) ")"
}

display _n "Backlash items:"
foreach v of global BL_BUREAU {
    quietly summarize `v'_pns
    display "  " %-18s "`v'" "  refusal rate = " %5.1f 100*r(mean) "%   (n = " r(N) ")"
}
foreach v of global BL_INTERN {
    quietly summarize `v'_pns
    display "  " %-18s "`v'" "  refusal rate = " %5.1f 100*r(mean) "%   (n = " r(N) ")"
}
foreach v of global BL_COMMUN {
    quietly summarize `v'_pns
    display "  " %-18s "`v'" "  refusal rate = " %5.1f 100*r(mean) "%   (n = " r(N) ")"
}
foreach v of global BL_SYMBOL {
    quietly summarize `v'_pns
    display "  " %-18s "`v'" "  refusal rate = " %5.1f 100*r(mean) "%   (n = " r(N) ")"
}
foreach v of global BL_VIOLENT {
    quietly summarize `v'_pns
    display "  " %-18s "`v'" "  refusal rate = " %5.1f 100*r(mean) "%   (n = " r(N) ")"
}

display _n "Victim-blaming items:"
foreach v of global VB {
    quietly summarize `v'_pns
    display "  " %-18s "`v'" "  refusal rate = " %5.1f 100*r(mean) "%   (n = " r(N) ")"
}

display _n "Module B pressure items:"
foreach v in withdraw_asked bribe_offer elec_threat {
    quietly summarize `v'_pns
    display "  " %-18s "`v'" "  refusal rate = " %5.1f 100*r(mean) "%   (n = " r(N) ")"
}

use "$clean/nonsc_analysis.dta", clear
display _n "--- Non-SC survey: attitude battery ---"

foreach v in att_res_bad att_res_miss att_res_incapable att_res_hamlets 	///
			 att_stereo_help att_stereo_officials att_stereo_nocaste			///
             att_poa_unjust att_poa_fake att_vb_cooperate att_vb_misuse {
    quietly summarize `v'_pns
    display "  " %-18s "`v'" "  refusal rate = " %5.1f 100*r(mean) "%   (n = " r(N) ")"
}

log close refuselog
log close qclog

display as result _n "=== 04_qc_paradata.do complete ==="
display as txt    "QC report:     $out/qc_report.txt"
display as txt    "Refusal rates: $out/tab_refusal_rates.txt"
display as error  "Before continuing, use the QC report to set in 00_master.do:"
display as error  "  \$use_block_cluster  (from A1.2 panchayats per block)"
display as error  "  \$speed_min          (from A4 duration distribution)"
display as error  "  \$use_district_fe    (from A1.2 district coverage)"

*==============================================================================*
* END 04_qc_paradata.do
*==============================================================================*

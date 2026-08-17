*==============================================================================*
* 10_compare.do
*
* PURPOSE : SC versus non-SC comparison on the identically worded modules, plus
*           the stereotype-refutation argument and the mixed-methods joint
*           display. Implements §8 and §11 of the analysis plan.
*
* INPUT   : $clean/sc_analysis.dta, $clean/nonsc_analysis.dta
* OUTPUT  : $clean/pooled_analysis.dta
*           $out/tab_compare_main.txt / .rtf
*           $out/tab_compare_balance.txt
*           $out/tab_stereotype_refutation.txt
*           $out/tab_joint_display.txt
*           $out/fig_compare_authority.png
*
*==============================================================================*
* WHAT CAN AND CANNOT BE CLAIMED FROM THIS COMPARISON
*
* This is the part of the analysis where over-claiming is most tempting, so it
* deserves the most precision.
*
* LEGITIMATE CLAIMS
*   1. A CASTE-PATTERNED AUTHORITY GAP. If SC mukhiyas exercise less de facto
*      authority than non-SC mukhiyas CONDITIONAL ON education, tenure, family
*      political background and panchayat characteristics, that is meaningful
*      evidence that the de jure / de facto gap is structured by caste rather
*      than by individual capacity. This is the strongest use of the comparison.
*   2. REFUTATION OF THE CAPABILITY STEREOTYPE. If SC and non-SC mukhiyas score
*      comparably on rights awareness and self-efficacy while differing on de
*      facto authority, the gap is not explained by knowledge or confidence
*      deficits. Since the non-SC instrument independently measures the BELIEF
*      that SC mukhiyas are less capable (at_resincap, at_needhelp), you can
*      juxtapose the stereotype with the measured reality. This closes a loop
*      between the two samples and is the analytical move worth building a
*      chapter section around.
*   3. A WELLBEING DIFFERENTIAL, as a descriptive baseline comparison.
*   4. BENCHMARKING. Non-SC values are a reference distribution for interpreting
*      SC values.
*
* WHAT CANNOT BE CLAIMED
*   NO CAUSAL INTERPRETATION. Caste is not randomly assigned. Every difference
*   is a descriptive contrast between two non-equivalent groups. Use "adjusted
*   difference", NEVER "effect of caste".
*
*   THE RESERVATION CONFOUND, which is structural and specific to this design.
*   SC mukhiyas occupy seats reserved for SCs, and in Bihar seat reservation is
*   allocated as a function of SC population share in the panchayat. The SC and
*   non-SC samples therefore come from SYSTEMATICALLY DIFFERENT PANCHAYATS --
*   SC-reserved seats sit in higher-SC-share panchayats close to by construction.
*   Three consequences:
*     (a) The comparison is BETWEEN-panchayat, not within. No panchayat
*         contributes both an SC and a non-SC mukhiya, so there is no overlap.
*     (b) gp_scshare is NOT a neutral control: it is partly a DETERMINANT OF
*         TREATMENT ASSIGNMENT. Control for it, but recognise that conditioning
*         on a variable that determines selection changes the estimand.
*     (c) Unobserved panchayat characteristics correlated with SC share (local
*         political economy, land distribution, historical mobilisation) are
*         confounded with the caste of the mukhiya.
*
*   Also cannot claim that a wellbeing gap is CAUSED by backlash: income, land,
*   status and household circumstances differ systematically between the samples
*   and are plausible alternative explanations.
*
* APPROXIMATE MDE for this comparison: 0.32 SD on a continuous index, 16 pp on a
* binary at p ~ 0.5. Moderate. Interpret accordingly.
*==============================================================================*

*==============================================================================*
* SECTION 1. BUILD THE POOLED DATASET
*
* The rename scheme gave the shared modules IDENTICAL names in both files, which
* is what makes a direct append possible. Section 9 of the rename reference lists
* the 61 harmonised variables.
*==============================================================================*
use "$clean/sc_analysis.dta", clear

* keep only the harmonised variables plus the derived measures that were built
* identically in both files. Anything SC-only or non-SC-only is excluded here,
* because a pooled file with half its columns systematically missing invites
* mistakes at the estimation stage.
local shared uid sc_sample                                            ///
             resp_type proxy_resp self_resp mukh_sex_n                 ///
             caste_cat educ educ_ord educ_sec income income_n          ///
             party party_n n_stood n_terms fam_any                     ///
             revenue_villages gp_pop ln_gp_pop sc_pop_share gp_scshare_ord        ///
             gp_scshare_ns gp_mainvill_n gp_domcaste                   ///
             auth_idx auth_tasks auth_tasks_k auth_final_ord           ///
             auth_proxy_self                                           ///
             eff_idx eff_mean                                          ///
             kn_demo_idx kn_claim_idx kn_all_idx kn_ns_rate kn_idx     ///
             wb_idx wb_sum_chk wb_scaled                               ///
             q_underst_r q_sincere_r lowqual                           ///
             kobo_user survey_date

* per-task authority ordinals and self-execution dummies, also built identically
foreach v of global AUTHTASKS {
    local shared "`shared' `v'_ord `v'_self"
}
* efficacy and knowledge items
foreach v of global EFF {
    local shared "`shared' `v'_n"
}
foreach v in kn_15fc_c kn_cert_c kn_pmayg_c kn_commit_c kn_gs_claim kn_gpdp_claim {
    local shared "`shared' `v'"
}
* wellbeing items
foreach v of global WB {
    local shared "`shared' `v'_n"
}
* geography from the frame merge, if present
foreach v in district block gp strata sample_group dur_min {
    capture confirm variable `v'
    if !_rc local shared "`shared' `v'"
}

* keep only those that actually exist, so a single absent variable does not abort
local keeplist ""
foreach v of local shared {
    capture confirm variable `v'
    if !_rc local keeplist "`keeplist' `v'"
}
keep `keeplist'
tempfile scpart
save `scpart'

use "$clean/nonsc_analysis.dta", clear
local keeplist2 ""
foreach v of local shared {
    capture confirm variable `v'
    if !_rc local keeplist2 "`keeplist2' `v'"
}
keep `keeplist2'

append using `scpart'

label var sc_sample "Respondent is an SC mukhiya (1) or non-SC (0)"
label define scsamp 0 "Non-SC mukhiya" 1 "SC mukhiya", replace
label values sc_sample scsamp

* uid must remain unique across the pooled file. The two samples were drawn from
* the same frame with the same uid scheme, so a collision would mean the same
* seat appears in both files, which is impossible by construction and would
* indicate a data problem.
duplicates report uid
duplicates tag uid, gen(_dup)
quietly count if _dup > 0
if r(N) > 0 {
    display as error "`r(N)' uid values appear in BOTH samples. Investigate:"
    list uid sc_sample if _dup > 0, clean noobs
}
drop _dup

tab sc_sample, missing

compress
save "$clean/pooled_analysis.dta", replace
display as result "Saved: $clean/pooled_analysis.dta"


*==============================================================================*
* SECTION 2. BALANCE AND THE RESERVATION CONFOUND
*
* This is not a randomised comparison, so "balance" here is not a diagnostic of
* successful randomisation. It is a description of HOW DIFFERENT the two groups
* are, which tells the reader how much work the covariate adjustment is being
* asked to do and how much residual confounding to expect.
*==============================================================================*
use "$clean/pooled_analysis.dta", clear

capture log close ballog
log using "$out/tab_compare_balance.txt", replace text name(ballog)

display _n "=================================================================="
display    " SC VERSUS NON-SC: GROUP CHARACTERISTICS"
display    ""
display    " This is NOT a randomisation balance check. Caste is not assigned."
display    " These tables describe how different the two groups are, so the"
display    " reader can judge how much the covariate adjustment is being asked"
display    " to do and how much residual confounding to expect."
display    "=================================================================="

display _n "--- 2.1 Sample sizes ---"
tab sc_sample, missing

display _n "--- 2.2 Demographic and panchayat characteristics ---"
foreach v in educ_ord educ_sec n_terms n_stood fam_any revenue_villages ln_gp_pop ///
             gp_scshare_ord gp_mainvill_n proxy_resp {
    capture confirm variable `v'
    if _rc continue
    quietly ttest `v', by(sc_sample)
    display "  " %-18s "`v'" "  non-SC = " %8.3f r(mu_1) ///
        "   SC = " %8.3f r(mu_2) "   diff = " %8.3f r(mu_2)-r(mu_1) ///
        "   p = " %6.4f r(p)
}

display _n "  Categorical variables:"
foreach v in mukh_sex_n income_n party_n {
    capture confirm variable `v'
    if _rc continue
    display _n "    `v':"
    tab `v' sc_sample, col chi2
}

*------------------------------------------------------------------------------*
* 2.3 The reservation confound, made visible
*------------------------------------------------------------------------------*
display _n(2) "--- 2.3 THE RESERVATION CONFOUND ---"
display "In Bihar, seat reservation is allocated as a function of the SC"
display "population share of the panchayat. SC mukhiyas therefore sit"
display "disproportionately in high-SC-share panchayats close to BY"
display "CONSTRUCTION. The distributions below show how severe the imbalance is."
display ""
display "gp_scshare_ord: 1 = under 10%, 2 = 10-15%, 3 = 15-20%, 4 = over 20%"

tab gp_scshare_ord sc_sample, col chi2

display _n "  Region of overlap in SC share:"
display "  Any category containing BOTH SC and non-SC mukhiyas supports a"
display "  comparison. Categories containing only one group do not, and"
display "  including them means the adjusted difference is partly"
display "  extrapolation rather than comparison."
tab gp_scshare_ord sc_sample

* identify overlapping strata programmatically
levelsof gp_scshare_ord, local(shares)
local overlap ""
foreach s of local shares {
    quietly count if gp_scshare_ord == `s' & sc_sample == 1
    local n1 = r(N)
    quietly count if gp_scshare_ord == `s' & sc_sample == 0
    local n0 = r(N)
    if `n1' > 0 & `n0' > 0 {
        local overlap "`overlap' `s'"
        display "    category `s': `n1' SC and `n0' non-SC -- OVERLAPS"
    }
    else {
        display "    category `s': `n1' SC and `n0' non-SC -- NO OVERLAP"
    }
}
global OVERLAP_SHARES "`overlap'"
display _n "  Overlapping SC-share categories: $OVERLAP_SHARES"
display "  Section 3.4 reports the comparison restricted to these."

display _n "  Frame-recorded seat reservation, if available:"
display "  This is preferable to self-reported gp_scshare because it is"
display "  measured independently of the survey and is the actual assignment"
display "  variable rather than a respondent's estimate of it."
capture tab strata sc_sample, col
capture confirm variable seat_resv
if !_rc {
    tab seat_resv sc_sample, col
}
else {
    display "  (seat_resv is not in the merged data. If your frame holds the"
    display "   seat reservation category, add it to the keeplist in"
    display "   01_import_merge.do part C1 -- it is a better control than the"
    display "   self-reported SC share.)"
}

display _n "--- 2.4 Geographic overlap ---"
display "Whether the two samples come from the same districts matters: if they"
display "do not, district fixed effects cannot help and the comparison is"
display "partly geographic."
capture {
    tab district sc_sample
    preserve
        contract district sc_sample
        reshape wide _freq, i(district) j(sc_sample)
        gen byte both = (_freq0 > 0 & _freq1 > 0) & !missing(_freq0, _freq1)
        quietly count
        local ndist = r(N)
        quietly count if both == 1
        display _n "  Districts containing both SC and non-SC respondents: " ///
            "`r(N)' of `ndist'"
    restore
}

log close ballog


*==============================================================================*
* SECTION 3. THE ADJUSTED COMPARISON
*
* Four specifications in ascending order of ambition, exactly as §8.3 sets out.
* None of them makes the comparison causal, and the output says so.
*==============================================================================*
use "$clean/pooled_analysis.dta", clear

capture log close complog
log using "$out/tab_compare_main.txt", replace text name(complog)

display _n "=================================================================="
display    " SC VERSUS NON-SC: ADJUSTED DIFFERENCES"
display    ""
display    " Every estimate below is an ADJUSTED DIFFERENCE, not an effect of"
display    " caste. Caste is not assigned; the two samples come from"
display    " systematically different panchayats because seat reservation"
display    " depends on SC population share. No specification here makes the"
display    " comparison causal."
display    ""
display    " Approximate MDE: 0.32 SD on a continuous index, 16 pp on a binary."
display    "=================================================================="

* covariate sets for the ladder
local X1 ""
local X2 i.educ_ord n_terms n_stood i.mukh_sex_n fam_any
local X3 i.educ_ord n_terms n_stood i.mukh_sex_n fam_any ///
         i.gp_scshare_ord ln_gp_pop revenue_villages i.gp_mainvill_n i.income_n i.party_n

capture confirm variable district
if !_rc {
    encode district, gen(district_n)
    local X4 "`X3' i.district_n"
}
else {
    local X4 "`X3'"
    display as txt "No district variable; specification 4 equals specification 3."
}

* outcomes: the identically worded modules only
global COMPARE_Y auth_idx auth_tasks auth_final_ord eff_idx eff_mean ///
                 kn_demo_idx kn_claim_idx kn_all_idx wb_idx wb_sum_chk

foreach y of global COMPARE_Y {

    capture confirm variable `y'
    if _rc continue

    local ylab : variable label `y'
    display _n(2) "### OUTCOME: `y'  (`ylab')"

    display _n "  Unadjusted means:"
    quietly ttest `y', by(sc_sample)
    display "    non-SC = " %8.3f r(mu_1) "   SC = " %8.3f r(mu_2) ///
        "   raw difference = " %8.3f r(mu_2)-r(mu_1) "   p = " %6.4f r(p)

    display _n "  Adjusted differences (coefficient on sc_sample):"
    quietly regress `y' sc_sample, vce(robust)
    display "    (1) unadjusted:        " %8.3f _b[sc_sample] ///
        "  se " %6.3f _se[sc_sample] "  n = " e(N)
    quietly regress `y' sc_sample `X2', vce(robust)
    display "    (2) + demographics:    " %8.3f _b[sc_sample] ///
        "  se " %6.3f _se[sc_sample] "  n = " e(N)
    quietly regress `y' sc_sample `X3', vce(robust)
    display "    (3) + panchayat:       " %8.3f _b[sc_sample] ///
        "  se " %6.3f _se[sc_sample] "  n = " e(N)
    quietly regress `y' sc_sample `X4', vce(robust)
    display "    (4) + district FE:     " %8.3f _b[sc_sample] ///
        "  se " %6.3f _se[sc_sample] "  n = " e(N)

    * restricted to the region of overlap in SC share
    if "$OVERLAP_SHARES" != "" {
        local ovcond ""
        foreach s in $OVERLAP_SHARES {
            if "`ovcond'" == "" local ovcond "gp_scshare_ord == `s'"
            else local ovcond "`ovcond' | gp_scshare_ord == `s'"
        }
        quietly regress `y' sc_sample `X3' if `ovcond', vce(robust)
        display "    (5) overlap only:      " %8.3f _b[sc_sample] ///
            "  se " %6.3f _se[sc_sample] "  n = " e(N)
        display "        (restricted to SC-share categories containing both groups)"
    }
}

*------------------------------------------------------------------------------*
* 3.1 Item-level authority comparison
*------------------------------------------------------------------------------*
display _n(2) "--- 3.1 Task-by-task self-execution, SC vs non-SC ---"
display "This is the most concrete form of the authority gap and the most"
display "quotable: which specific functions do SC mukhiyas perform less often?"
foreach v of global AUTHTASKS {
    local lab : variable label `v'_self
    quietly ttest `v'_self, by(sc_sample)
    display "  " %-16s "`v'" "  non-SC " %5.1f 100*r(mu_1) "%   SC " ///
        %5.1f 100*r(mu_2) "%   diff " %6.1f 100*(r(mu_2)-r(mu_1)) ///
        " pp   p = " %6.4f r(p)
}

display _n "  Adjusted (specification 3), same items:"
foreach v of global AUTHTASKS {
    quietly regress `v'_self sc_sample `X3', vce(robust)
    display "  " %-16s "`v'" "  adjusted diff = " %6.1f 100*_b[sc_sample] ///
        " pp   se " %5.1f 100*_se[sc_sample]
}

*------------------------------------------------------------------------------*
* 3.2 Export
*------------------------------------------------------------------------------*
eststo clear
foreach y in auth_idx auth_tasks eff_idx kn_demo_idx wb_idx {
    capture confirm variable `y'
    if _rc continue
    eststo c_`y': quietly regress `y' sc_sample `X3', vce(robust)
}
capture which esttab
if !_rc {
    esttab c_* using "$out/tab_compare_main.rtf", replace ///
        keep(sc_sample) b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
        stats(N r2, fmt(0 3) labels("Observations" "R-squared")) ///
        title("SC versus non-SC mukhiyas: adjusted differences") ///
        addnotes("ADJUSTED DIFFERENCES, not effects of caste. Caste is not" ///
                 "randomly assigned, and because Bihar allocates seat" ///
                 "reservation by SC population share the two samples come from" ///
                 "systematically different panchayats. Controls: education," ///
                 "terms, times stood, gender, family office, SC share, log" ///
                 "population, revenue villages, main village, income, party." ///
                 "Approximate MDE 0.32 SD.") ///
        label
}

log close complog

*--- FIGURE: authority comparison ---*
capture which coefplot
if !_rc {
    eststo clear
    foreach v of global AUTHTASKS {
        eststo t_`v': quietly regress `v'_self sc_sample `X3', vce(robust)
    }
    coefplot t_*, keep(sc_sample) ///
        xline(0, lcolor(gs8) lpattern(dash)) ///
        levels(95) ciopts(recast(rcap)) ///
        xtitle("Adjusted SC minus non-SC difference in self-execution") ///
        title("Which functions do SC mukhiyas perform less often?", size(medium)) ///
        subtitle("Adjusted differences, 95% intervals", size(small)) ///
        note("Adjusted differences, not effects of caste. See §8.3 on the" ///
             "reservation confound.", size(vsmall)) ///
        graphregion(color(white))
    graph export "$out/fig_compare_authority.png", replace width(2000)
}


*==============================================================================*
* SECTION 4. THE STEREOTYPE-REFUTATION ARGUMENT
*
* The analytical loop worth building a chapter section around.
*
* The non-SC instrument measures the BELIEF that SC mukhiyas are less capable
* (at_resincap: "SC mukhiyas elected through reservation are usually not
* capable"; at_needhelp: "SC mukhiyas need more help running the panchayat").
* The SC instrument measures ACTUAL functional knowledge and self-efficacy with
* identically worded items.
*
* If SC and non-SC mukhiyas score comparably on knowledge and efficacy while
* differing on de facto authority, you can REFUTE WITH YOUR OWN DATA the
* stereotype your other instrument measures as an attitude. That closes a loop
* between the two samples and is precisely the kind of integration that
* distinguishes a strong dissertation.
*
* CAUTION ON THE LOGIC. "No detectable difference" is not "no difference". At
* these sample sizes the MDE on a continuous index is roughly 0.32 SD, so a
* genuine small gap in knowledge would be invisible. The honest claim is that
* the DATA PROVIDE NO EVIDENCE OF A CAPACITY DEFICIT LARGE ENOUGH TO EXPLAIN THE
* AUTHORITY GAP -- which is still a strong claim, because the authority gap
* itself is being estimated on the same data with the same precision. If the
* authority gap is detectable and the knowledge gap is not, the asymmetry is
* informative even though neither estimate is precise in absolute terms.
*==============================================================================*
use "$clean/pooled_analysis.dta", clear

capture log close stereolog
log using "$out/tab_stereotype_refutation.txt", replace text name(stereolog)

display _n "=================================================================="
display    " THE STEREOTYPE AND THE MEASURED REALITY"
display    ""
display    " Non-SC respondents were asked whether SC mukhiyas elected through"
display    " reservation are usually not capable, and whether they need more"
display    " help running the panchayat. Both instruments then measured actual"
display    " functional knowledge and self-efficacy with IDENTICAL items."
display    ""
display    " CAUTION: 'no detectable difference' is not 'no difference'. The MDE"
display    " here is roughly 0.32 SD. The defensible claim is that the data"
display    " provide no evidence of a capacity deficit LARGE ENOUGH TO EXPLAIN"
display    " the authority gap. If the authority gap is detectable on these same"
display    " data and the capacity gap is not, that ASYMMETRY is the finding."
display    "=================================================================="

local X3 i.educ_ord n_terms n_stood i.mukh_sex_n fam_any ///
         i.gp_scshare_ord ln_gp_pop revenue_villages i.gp_mainvill_n i.income_n i.party_n

display _n "--- 4.1 Capacity measures: is there a gap? ---"
foreach y in kn_demo_idx kn_claim_idx kn_all_idx eff_idx eff_mean {
    capture confirm variable `y'
    if _rc continue
    local ylab : variable label `y'
    quietly ttest `y', by(sc_sample)
    local raw = r(mu_2) - r(mu_1)
    local praw = r(p)
    quietly regress `y' sc_sample `X3', vce(robust)
    display "  " %-14s "`y'" "  raw diff " %7.3f `raw' " (p " %5.3f `praw' ")" ///
        "   adjusted " %7.3f _b[sc_sample] " (se " %5.3f _se[sc_sample] ")"
}

display _n "  Item-level knowledge comparison:"
foreach v in kn_15fc_c kn_cert_c kn_pmayg_c kn_commit_c kn_gs_claim kn_gpdp_claim {
    capture confirm variable `v'
    if _rc continue
    quietly ttest `v', by(sc_sample)
    display "  " %-16s "`v'" "  non-SC " %5.1f 100*r(mu_1) "%   SC " ///
        %5.1f 100*r(mu_2) "%   diff " %6.1f 100*(r(mu_2)-r(mu_1)) " pp"
}

display _n "  Item-level self-efficacy comparison:"
foreach v of global EFF {
    quietly ttest `v'_n, by(sc_sample)
    display "  " %-16s "`v'" "  non-SC " %5.2f r(mu_1) "   SC " %5.2f r(mu_2) ///
        "   diff " %6.3f r(mu_2)-r(mu_1) "   p = " %6.4f r(p)
}

display _n "--- 4.2 The authority gap on the same data, for comparison ---"
display "The point of the juxtaposition: if the authority gap is detectable"
display "here and the capacity gap is not, the gap is not a capacity story."
foreach y in auth_idx auth_tasks auth_final_ord {
    quietly ttest `y', by(sc_sample)
    local raw = r(mu_2) - r(mu_1)
    quietly regress `y' sc_sample `X3', vce(robust)
    display "  " %-16s "`y'" "  raw diff " %7.3f `raw' ///
        "   adjusted " %7.3f _b[sc_sample] " (se " %5.3f _se[sc_sample] ")"
}

display _n "--- 4.3 Standardised comparison of the two gaps ---"
display "Expressed in SD units of the pooled distribution so the authority gap"
display "and the capacity gap are on the same scale."
foreach y in auth_idx kn_demo_idx eff_idx {
    capture confirm variable `y'
    if _rc continue
    quietly summarize `y'
    local sd = r(sd)
    quietly regress `y' sc_sample `X3', vce(robust)
    if `sd' > 0 {
        display "  " %-14s "`y'" "  adjusted difference = " ///
            %6.3f _b[sc_sample]/`sd' " SD   (se " %5.3f _se[sc_sample]/`sd' ")"
    }
}

display _n "--- 4.4 The stereotype itself, measured on the non-SC sample ---"
display "Reported here so the two halves of the argument sit side by side in"
display "one table. Item means are on the 1-5 agreement scale."
preserve
    use "$clean/nonsc_analysis.dta", clear
    foreach v in at_resincap at_needhelp at_hardoffic at_resmiss {
        capture confirm variable `v'_n
        if _rc continue
        local lab : variable label `v'
        quietly summarize `v'_n
        display "  " %-14s "`v'" "  mean " %5.2f r(mean) "  (n " r(N) ")   `lab'"
        quietly gen byte _agree = (`v'_n >= 4) if !missing(`v'_n)
        quietly ci proportions _agree, wilson
        display "                    agree or strongly agree: " ///
            %5.1f 100*r(proportion) "%  [" %5.1f 100*r(lb) ", " %5.1f 100*r(ub) "]"
        drop _agree
    }
restore

display _n "--- 4.5 How to phrase the conclusion ---"
display "DEFENSIBLE:  'A substantial share of non-SC mukhiyas endorse the view"
display "             that SC mukhiyas are less capable. On identically worded"
display "             measures of functional knowledge and self-efficacy, the"
display "             two groups differ by X SD (se Y) -- an estimate too small"
display "             and too imprecise to support the stereotype -- while the"
display "             de facto authority gap is Z SD.'"
display ""
display "NOT DEFENSIBLE: 'SC and non-SC mukhiyas are equally capable, therefore"
display "                 the stereotype is false.' That treats an imprecise"
display "                 null as a demonstrated equivalence."

log close stereolog


*==============================================================================*
* SECTION 5. VICTIM-BLAMING: EXPOSURE VERSUS ENDORSEMENT
*
* A genuine strength of the design: the same construct measured as EXPERIENCE on
* one side and as ATTITUDE on the other. A joint display comparing exposure
* prevalence with endorsement prevalence is one of the most rhetorically
* effective tables available.
*
* CAUTION ON THE COMPARISON. These are not the same items on the same scale.
* Exposure is binary and asks about specific things said to the respondent;
* endorsement is Likert and asks whether the respondent holds a general view.
* The comparison is a JUXTAPOSITION, not a difference to be tested. Presenting
* it as a statistical comparison would be a category error.
*==============================================================================*
capture log close vblog
log using "$out/tab_vb_juxtaposition.txt", replace text name(vblog)

display _n "=================================================================="
display    " VICTIM-BLAMING: EXPOSURE (SC) AND ENDORSEMENT (NON-SC)"
display    ""
display    " The same construct from both sides. NOTE these are not the same"
display    " items on the same scale: exposure is binary and specific,"
display    " endorsement is Likert and general. This is a JUXTAPOSITION, not a"
display    " difference to be tested."
display    "=================================================================="

display _n "--- 5.1 SC side: exposure to external victim-blaming ---"
use "$clean/sc_analysis.dta", clear
foreach v of global VB {
    local lab : variable label `v'
    quietly ci proportions `v'_b, wilson
    display "  " %-16s "`v'" %6.1f 100*r(proportion) "%  [" ///
        %5.1f 100*r(lb) ", " %5.1f 100*r(ub) "]   `lab'"
}
display _n "  Count of victim-blaming forms experienced:"
tab vb_cnt, missing
quietly summarize vb_cnt, detail
display as result "    median = " r(p50) "   mean = " %4.2f r(mean)

quietly ci proportions vb_assert_b, wilson
display _n "  Any exposure at all:"
quietly gen byte vb_any = (vb_cnt > 0) if !missing(vb_cnt)
quietly ci proportions vb_any, wilson
display as result "    " %5.1f 100*r(proportion) "%  [" %5.1f 100*r(lb) ", " ///
    %5.1f 100*r(ub) "]"

display _n "--- 5.2 Non-SC side: endorsement of victim-blaming attitudes ---"
use "$clean/nonsc_analysis.dta", clear
foreach v in att_vb_cooperate att_vb_misuse {
    local lab : variable label `v'
    quietly summarize `v'_n
    display "  " %-16s "`v'" "  mean " %5.2f r(mean) "   `lab'"
    quietly gen byte _agree = (`v'_n >= 4) if !missing(`v'_n)
    quietly ci proportions _agree, wilson
    display "                    agree or strongly agree: " ///
        %5.1f 100*r(proportion) "%  [" %5.1f 100*r(lb) ", " %5.1f 100*r(ub) "]"
    drop _agree
    quietly summarize `v'_pns
    display "                    declined to answer: " %5.1f 100*r(mean) "%"
}

display _n "--- 5.3 Reading the two sides together ---"
display "The victim-blaming construct is measured as something DONE TO SC"
display "mukhiyas and as something BELIEVED BY non-SC mukhiyas. If exposure is"
display "widespread and endorsement is common, the two are mutually"
display "corroborating: the attitude exists in the population that would"
display "express it, and the expression is experienced by the population that"
display "would receive it. Neither alone establishes that, which is the"
display "argument for having collected both."

log close vblog


*==============================================================================*
* SECTION 6. THE MIXED-METHODS JOINT DISPLAY   (§11)
*
* A table mapping each qualitative theme to its quantitative counterpart. This
* is the integration artefact reviewers of mixed-methods work look for.
*
* Following Creswell and Plano Clark's typology, the design is best described as
* an EXPLORATORY SEQUENTIAL DESIGN (qual -> QUAN) with the qualitative phase
* informing instrument development, plus a CONVERGENT element at the
* interpretation stage. Name the design and give the notation; reviewers expect
* it. (Verify the edition of Creswell and Plano Clark you cite; the typology is
* stable across editions but page references are not.)
*
* REPORT CONVERGENCE AND DIVERGENCE ALIKE. Where the survey does not corroborate
* an interview theme, that is a finding about PREVALENCE VERSUS SALIENCE:
* mechanisms that loom large in three in-depth interviews may be uncommon in the
* population, and vice versa. Three interviews cannot establish prevalence, and
* 150 surveys cannot establish meaning. Saying this plainly is a strength.
*==============================================================================*
use "$clean/sc_analysis.dta", clear

capture log close jointlog
log using "$out/tab_joint_display.txt", replace text name(jointlog)

display _n "=================================================================="
display    " MIXED-METHODS JOINT DISPLAY"
display    ""
display    " Global theme: Undermining Substantive Democracy Through Everyday"
display    " Exclusion"
display    ""
display    " Design: exploratory sequential, qual -> QUAN, with a convergent"
display    " element at interpretation."
display    "=================================================================="

display _n(2) "##################################################################"
display       "# THEME 1: BUREAUCRATIC ROADBLOCKS AND INSTITUTIONAL GATEKEEPING"
display       "##################################################################"
display _n "Quantitative counterpart: the e1_* items, e1_comparison, and the"
display    "bureaucratic backlash index."
display _n "Item prevalence:"
foreach v of global BL_BUREAU_F {
    local lab : variable label `v'
    quietly ci proportions `v', wilson
    display "  " %-16s "`v'" %6.1f 100*r(proportion) "%  [" ///
        %5.1f 100*r(lb) ", " %5.1f 100*r(ub) "]   `lab'"
}
display _n "Share reporting worse treatment than upper-caste mukhiyas:"
quietly ci proportions bl_worse, wilson
display as result "  " %5.1f 100*r(proportion) "%  [" %5.1f 100*r(lb) ", " ///
    %5.1f 100*r(ub) "]"
display _n "Association with the authority index:"
quietly regress bl_bureau_idx auth_idx $X_DEMOG $X_PANCH, vce(robust)
quietly test auth_idx
display "  b = " %7.4f _b[auth_idx] "  se = " %6.4f _se[auth_idx] ///
    "  p = " %6.4f r(p)

display _n(2) "##################################################################"
display       "# THEME 2: SOCIAL MICROAGGRESSIONS AND SYMBOLIC DELEGITIMISATION"
display       "##################################################################"
display _n "Quantitative counterpart: d1_*, d2_*, d3_*, d4_common, organised by"
display    "Sue et al. subtype."
display _n "Prevalence by subtype:"
display "  Microinsults:"
foreach v of global MA_INSULT_F {
    quietly ci proportions `v', wilson
    display "    " %-16s "`v'" %6.1f 100*r(proportion) "%  [" ///
        %5.1f 100*r(lb) ", " %5.1f 100*r(ub) "]"
}
display "  Microinvalidations:"
foreach v of global MA_INVAL_F {
    quietly ci proportions `v', wilson
    display "    " %-16s "`v'" %6.1f 100*r(proportion) "%  [" ///
        %5.1f 100*r(lb) ", " %5.1f 100*r(ub) "]"
}
display "  Microassaults:"
foreach v of global MA_ASSAULT_F {
    quietly ci proportions `v', wilson
    display "    " %-16s "`v'" %6.1f 100*r(proportion) "%  [" ///
        %5.1f 100*r(lb) ", " %5.1f 100*r(ub) "]"
}
display _n "Perception-experience gap:"
quietly summarize ma_gap
display "  mean gap (perceived general prevalence minus own experience) = " ///
    %6.3f r(mean)

display _n(2) "##################################################################"
display       "# THEME 3: ELITE STRATEGIES TO MAINTAIN CONTROL"
display       "##################################################################"
display _n "Quantitative counterparts, and this theme has the richest set:"
display "  (a) displacement of tasks to former_mukhiya / up_mukhiya (c1_*)"
display "  (b) panchayat-internal and community backlash (e2_*, e3_*)"
display "  (c) pre-office pressure (withdraw_asked, benefit_offered)"
display "  (d) THE CONJOINT AUTHORITY-STYLE AMCE, which is the experimental"
display "      counterpart and the only causal evidence in the dissertation."
display _n "(a) Actor composition of displacement:"
preserve
    keep uid auth_gs_who auth_bdo_who auth_block_who auth_works_who auth_griev_who
    rename auth_*_who who_*
    reshape long who_, i(uid) j(taskname) string
    rename who_ actor
    quietly count if !inlist(actor, "self", "self_family_help", ///
        "family_member_for_me")
    local ndisp = r(N)
    quietly count if inlist(actor, "former_mukhiya", "up_mukhiya")
    display "  Displaced tasks going to the ex-mukhiya or deputy: " ///
        r(N) " of `ndisp'"
    tab actor if !inlist(actor, "self", "self_family_help", "family_member_for_me")
restore
display _n "(b) Panchayat-internal and community items:"
foreach v of global BL_INTERN_F {
    quietly ci proportions `v', wilson
    display "    " %-16s "`v'" %6.1f 100*r(proportion) "%  [" ///
        %5.1f 100*r(lb) ", " %5.1f 100*r(ub) "]"
}
foreach v of global BL_COMMUN_F {
    quietly ci proportions `v', wilson
    display "    " %-16s "`v'" %6.1f 100*r(proportion) "%  [" ///
        %5.1f 100*r(lb) ", " %5.1f 100*r(ub) "]"
}
display _n "(c) Pre-office pressure:"
foreach v in wd_asked_b bribe_offer_b elec_threat_b {
    capture confirm variable `v'
    if _rc continue
    quietly ci proportions `v', wilson
    display "    " %-16s "`v'" %6.1f 100*r(proportion) "%  [" ///
        %5.1f 100*r(lb) ", " %5.1f 100*r(ub) "]"
}
display _n "(d) The conjoint interaction is in tab_amce_interaction.txt."
display "    Cross-reference it here in the write-up: the qualitative theme"
display "    describes elites installing compliant candidates, and the conjoint"
display "    tests experimentally whether non-SC mukhiyas penalise SC profiles"
display "    specifically for NOT being compliant. That is the tightest"
display "    qual-quant linkage in the dissertation."

display _n(2) "##################################################################"
display       "# THEME 4: RESISTANCE TO AMBEDKAR SYMBOLS AND RIGHTS ASSERTION"
display       "##################################################################"
display _n "Quantitative counterpart: e4_symbols_damaged, e4_rights_opposition."
display    "Thin coverage -- two items -- which is why §12 of the plan advises"
display    "against building a whole chapter on this theme."
foreach v of global BL_SYMBOL_F {
    local lab : variable label `v'
    quietly ci proportions `v', wilson
    display "  " %-16s "`v'" %6.1f 100*r(proportion) "%  [" ///
        %5.1f 100*r(lb) ", " %5.1f 100*r(ub) "]   `lab'"
}
display _n "Association with the authority index:"
quietly regress bl_symbol_idx auth_idx $X_DEMOG $X_PANCH, vce(robust)
quietly test auth_idx
display "  b = " %7.4f _b[auth_idx] "  se = " %6.4f _se[auth_idx] ///
    "  p = " %6.4f r(p)

display _n(2) "--- ON REPORTING DIVERGENCE ---"
display "Where the survey does not corroborate an interview theme, that is a"
display "finding about prevalence versus salience, not a failure of either"
display "method. Three interviews cannot establish prevalence, and 150 surveys"
display "cannot establish meaning. Where a theme that dominated the interviews"
display "turns out to be uncommon in the survey, say so and explain why both"
display "results can be true: an experience can be rare and still be the most"
display "significant thing that happened to the person who had it."

log close jointlog

display as result _n "=== 10_compare.do complete ==="
display as txt "Pooled data:      $clean/pooled_analysis.dta"
display as txt "Balance:          $out/tab_compare_balance.txt"
display as txt "Main comparison:  $out/tab_compare_main.txt (+ .rtf)"
display as txt "Stereotype loop:  $out/tab_stereotype_refutation.txt"
display as txt "Victim-blaming:   $out/tab_vb_juxtaposition.txt"
display as txt "Joint display:    $out/tab_joint_display.txt"
display as txt "Figure:           $out/fig_compare_authority.png"

*==============================================================================*
* END 10_compare.do
*==============================================================================*

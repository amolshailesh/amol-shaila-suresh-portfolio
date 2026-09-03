*==============================================================================*
* 05_desc_sc.do
*
* PURPOSE : SC survey descriptive core (establishing the de jure / de facto gap)
*			and (backlash and microaggression prevalence)
*
* INPUT   : $clean/sc_analysis.dta
* OUTPUT  : $out/tab_authority_gap.txt
*           $out/tab_prevalence_full.txt      -- the full item table
*           $out/tab_manski_bounds.txt        -- refusal bounds
*           $out/fig_task_self_exec.png       -- ranked task figure
*           $out/fig_prevalence.png           -- ranked prevalence figure
*           $out/prevalence_estimates.dta     -- machine-readable
*
* CONFIDENCE INTERVALS
*   Wilson intervals throughout, not the normal approximation. Several items
*   will have prevalence near 0 or 1, where the normal approximation
*   misbehaves badly (it can produce bounds outside [0,1]). Wilson is
*   well-behaved in the tails.
*   Syntax: ci proportions varname, wilson
*==============================================================================*

use "$clean/sc_analysis.dta", clear


*==============================================================================*
* HELPER: prevalence with Wilson CI, accumulated into a dataset for later use
*==============================================================================*
capture program drop prevrow
program define prevrow
    * Appends one row to a growing postfile of prevalence estimates.
    * Usage: prevrow <varname> <theme-label>
    args v theme

    quietly count if !missing(`v')
    local n = r(N)
    if `n' == 0 {
        display as error "  `v' has no non-missing observations; skipped."
        exit
    }

    quietly ci proportions `v', wilson
    local p  = r(proportion)
    local lo = r(lb)
    local hi = r(ub)

    local lab : variable label `v'
    display "  " %-16s "`v'" %6.1f 100*`p' "%  [" %5.1f 100*`lo' ", " ///
        %5.1f 100*`hi' "]  n=" %4.0f `n' "   `lab'"

    * Push to the postfile opened by the caller. The handle is passed via the
    * GLOBAL $r_handle rather than a local, because a local defined in the
    * calling script is not visible inside a programme's own scope.
    post $r_handle ("`v'") ("`theme'") ("`lab'") (`p') (`lo') (`hi') (`n')
end


*==============================================================================*
* SECTION 1. THE DE JURE / DE FACTO GAP
*==============================================================================*
capture log close authlog
log using "$out/tab_authority_gap.txt", replace text name(authlog)

display _n "=================================================================="
display    " SC SURVEY: THE DE JURE / DE FACTO AUTHORITY GAP"
display    ""
display    " Every SC mukhiya in this sample holds de jure authority: they were"
display    " elected to the office. This section measures how much of it they"
display    " actually exercise. The gap between the two is the object of study."
display    "=================================================================="

*------------------------------------------------------------------------------*
* 1.1 Distribution of the authority measures
*------------------------------------------------------------------------------*
display _n "--- 1.1 De facto authority index and task count ---"
summarize auth_idx auth_tasks, detail

display _n "Task-count distribution (number of the 5 core functions self-executed):"
tab auth_tasks, missing
display _n "The median is the figure to quote in prose: 'the median SC mukhiya"
display    "personally performs X of 5 core functions' is far more legible to a"
display    "reader than a z-score."
quietly summarize auth_tasks, detail
display as result "  Median = " r(p50) "   Mean = " %4.2f r(mean) ///
    "   IQR = " r(p25) " to " r(p75)

*------------------------------------------------------------------------------*
* 1.2 Share self-executing each of the five functions, ranked
*------------------------------------------------------------------------------*
display _n "--- 1.2 Self-execution rate by function, with Wilson 95% CIs ---"

tempfile taskprev
tempname th
postfile `th' str20 task str80 tasklab double(p lo hi n) using `taskprev', replace

foreach v of global AUTHTASKS {
    quietly count if !missing(`v'_self)
    local n = r(N)
    quietly ci proportions `v'_self, wilson
    local p = r(proportion)
    local lo = r(lb)
    local hi = r(ub)
    local lab : variable label `v'
    display "  " %-14s "`v'" %6.1f 100*`p' "%  [" %5.1f 100*`lo' ", " ///
        %5.1f 100*`hi' "]   `lab'"
    post `th' ("`v'") ("`lab'") (`p') (`lo') (`hi') (`n')
}
postclose `th'

*------------------------------------------------------------------------------*
* 1.3 Final decision authority, and self-described proxy status
*------------------------------------------------------------------------------*
display _n "--- 1.3 Who makes the final call (5 = fully independent) ---"
tab auth_final_ord, missing

display _n "Share reporting that OTHERS decide (formalise or entirely):"
display    "These respondents are describing proxy status in their own words."
quietly ci proportions auth_proxy_self, wilson
display as result "  " %5.1f 100*r(proportion) "%   95% CI [" ///
    %5.1f 100*r(lb) ", " %5.1f 100*r(ub) "]"

*------------------------------------------------------------------------------*
* 1.4 Actor composition of displacement
*
* WHO does the work when the mukhiya does not is a finding in its own right,
* not merely an index input. former_mukhiya and up_mukhiya are exactly the
* actors qualitative Theme 3 (elite strategies to maintain control) identifies.
*------------------------------------------------------------------------------*
display _n "--- 1.4 When the mukhiya does not do the task, who does? ---"
foreach v of global AUTHTASKS {
    local lab : variable label `v'
    display _n "  `lab'"
    tab `v'_who if `v'_ord < 2, missing
}

display _n "Pooled displacement composition across all five tasks:"
* reshape long over the five actor variables so the pooled distribution can be
* tabulated in one pass. preserve/restore keeps the analysis file intact.
preserve
    keep uid auth_gs_who auth_bdo_who auth_block_who auth_works_who auth_griev_who
    rename auth_*_who who_*
    reshape long who_, i(uid) j(taskname) string
    rename who_ actor
    display _n "All task-mukhiya observations, by actor:"
    tab actor, missing
    display _n "Restricted to displaced tasks only (excluding self and assisted):"
    tab actor if !inlist(actor, "self", "self_family_help", "family_member_for_me")
    display _n "Share of DISPLACED tasks going to the former mukhiya or deputy:"
    gen byte elite_actor = inlist(actor, "former_mukhiya", "up_mukhiya")
    quietly count if !inlist(actor, "self", "self_family_help", "family_member_for_me")
    local ndisp = r(N)
    quietly count if elite_actor == 1
    display as result "  " r(N) " of `ndisp' displaced tasks"
restore

*------------------------------------------------------------------------------*
* 1.5 Validation of the independence construct against enumerator judgement
*------------------------------------------------------------------------------*
display _n "--- 1.5 Self-reported authority vs enumerator judgement ---"
capture {
    tabstat auth_idx auth_tasks, by(q_indep_b) stat(mean sd n)
    tab auth_proxy_self q_indep_b, row col
    display _n "Agreement statistic:"
    capture kap self_indep_b q_indep_b
    display _n "If these diverge sharply, discuss it rather than hiding it: it"
    display    "speaks to the difficulty of measuring independence at all,"
    display    "which is a methodological finding in its own right."
}

*------------------------------------------------------------------------------*
* 1.6 Separating authority, efficacy and knowledge
*
* These three are conceptually distinct and the plan is explicit that they must
* not be collapsed. If they were near-perfectly correlated, that decision would
* be hard to defend; the correlations below are the evidence for it.
*------------------------------------------------------------------------------*
display _n "--- 1.6 Are authority, efficacy and knowledge distinct? ---"
correlate auth_idx eff_idx kn_demo_idx kn_claim_idx
display _n "Moderate correlations support treating these as separate constructs."
display    "Near-unity would suggest they are measuring one thing and the"
display    "three-way separation would need rethinking."

log close authlog

*--- FIGURE: ranked self-execution rates with CIs ---*
preserve
    use `taskprev', clear
    gsort p
    gen byte order = _n
    * shorten labels for the axis
    gen str32 shortlab = ""
    replace shortlab = "Cheques and finance"       if task == "auth_cheq"
    replace shortlab = "Beneficiary lists"         if task == "auth_benef"
    replace shortlab = "Chairs Gram Sabha"         if task == "auth_gs"
    replace shortlab = "Meets the BDO"             if task == "auth_bdo"
    replace shortlab = "Block-level meetings"      if task == "auth_block"
    replace shortlab = "Development priorities"    if task == "auth_works"
    replace shortlab = "Villagers' grievances"     if task == "auth_griev"

    levelsof order, local(ords)
    local ylab ""
    foreach o of local ords {
        local l = shortlab[`o']
        local ylab `"`ylab' `o' "`l'""'
    }

    twoway (rcap lo hi order, horizontal lcolor(gs8)) ///
           (scatter order p, msymbol(O) mcolor(navy)) ///
        , ylabel(`ylab', angle(0) labsize(small)) ///
          ytitle("") xtitle("Share self-executing the task") ///
          xlabel(0(0.2)1, format(%3.1f)) ///
          title("Which functions does the SC mukhiya personally perform?", ///
                size(medium)) ///
          note("Wilson 95% confidence intervals. Source: SC mukhiya survey.", ///
               size(vsmall)) ///
          legend(off) graphregion(color(white))
    graph export "$out/fig_task_self_exec.png", replace width(2000)
restore


*==============================================================================*
* SECTION 2. PREVALENCE OF MICROAGGRESSION AND BACKLASH
*
* The full item-level prevalence table. Item-level DESCRIPTION is where the
* empirical richness lives and is what connects the quantitative results to
* the four qualitative themes. Item-level TESTING is a different matter and
* is not viable at n = 150 (MDE near 23 pp for a two-group comparison), which
* is why hypothesis tests run on indices in 06_assoc_sc.do.
*==============================================================================*
use "$clean/sc_analysis.dta", clear

capture log close prevlog
log using "$out/tab_prevalence_full.txt", replace text name(prevlog)

display _n "=================================================================="
display    " SC SURVEY: FULL ITEM-LEVEL PREVALENCE"
display    ""
display    " Every binary item with its point estimate and Wilson 95% CI,"
display    " grouped by the qualitative theme. Manski bounds are in"
display    " tab_manski_bounds.txt."
display    ""
display    " Format: variable | prevalence % [95% CI] | n | question"
display    "=================================================================="

tempfile prevfile
tempname ph
postfile `ph' str20 item str24 theme str80 itemlab double(p lo hi n) ///
    using `prevfile', replace
global r_handle "`ph'"

display _n(2) "### THEME 2: SOCIAL MICROAGGRESSIONS AND SYMBOLIC DELEGITIMISATION"
display "    (Sue et al. taxonomy applied)"

display _n "-- Microinsults --"
foreach v of global MA_INSULT_F {
    prevrow `v' "MA: microinsult"
}

display _n "-- Microinvalidations --"
foreach v of global MA_INVAL_F {
    prevrow `v' "MA: microinvalidation"
}

display _n "-- Microassaults --"
if $slur_as_assault == 1 {
    display "   NOTE: ma_slur is included here, not in the microinvalidation"
    display "   block where the instrument placed it. A caste slur is overt,"
    display "   conscious and explicitly derogatory, which is a microassault in"
    display "   Sue et al.'s taxonomy, not a dismissal or denial. Footnote the"
    display "   instrument's block placement in the write-up."
}
foreach v of global MA_ASSAULT_F {
    prevrow `v' "MA: microassault"
}

display _n(2) "### THEME 1: BUREAUCRATIC ROADBLOCKS AND INSTITUTIONAL GATEKEEPING"
foreach v of global BL_BUREAU_F {
    prevrow `v' "BL: bureaucratic"
}

display _n(2) "### THEME 3: ELITE STRATEGIES TO MAINTAIN CONTROL"
display _n "-- Panchayat-internal --"
foreach v of global BL_INTERN_F {
    prevrow `v' "BL: panchayat-internal"
}
display _n "-- Community and elite --"
foreach v of global BL_COMMUN_F {
    prevrow `v' "BL: community/elite"
}
display _n "-- Pre-office pressure (Module B) --"
foreach v in withdraw_asked_b bribe_offer_b elec_threat_b {
    prevrow `v' "BL: entry pressure"
}

display _n(2) "### THEME 4: RESISTANCE TO AMBEDKAR SYMBOLS AND RIGHTS ASSERTION"
foreach v of global BL_SYMBOL_F {
    prevrow `v' "BL: symbolic"
}

display _n(2) "### BOUNDARY OF THE CONTESTED MIDDLE GROUND: OVERT THREAT/VIOLENCE"
display "    These items mark the outer edge of the phenomenon the dissertation"
display "    studies. The contribution lies in the space BETWEEN elite capture"
display "    and physical violence, so these prevalences bound the argument"
display "    rather than constituting it."
foreach v of global BL_VIOLENT_F {
    prevrow `v' "BL: overt violence"
}

display _n(2) "### VICTIM-BLAMING EXPOSURE (external attribution)"
display "    These ask whether OTHERS told the respondent their troubles were"
display "    self-inflicted. They measure exposure to external blame, not the"
display "    respondent's own guilt."
foreach v of global VB_F {
    prevrow `v' "VB: exposure"
}

postclose `ph'
macro drop r_handle

*------------------------------------------------------------------------------*
* 2.1 Index distributions
*------------------------------------------------------------------------------*
display _n(2) "--- 2.1 Channel-specific index and count distributions ---"
display "Channels are kept SEPARATE deliberately. A single undifferentiated"
display "backlash score would erase the distinction between elite capture and"
display "physical violence, which is the distinction the dissertation exists"
display "to make. The pooled index is reported as secondary."
summarize ma_idx ma_insult_idx ma_inval_idx ma_assault_idx ///
          bl_idx bl_bureau_idx bl_intern_idx bl_commun_idx bl_symbol_idx ///
          bl_violent_idx vb_idx

display _n "Counts (the numbers to quote in prose):"
tabstat ma_cnt ma_insult_cnt ma_inval_cnt ma_assault_cnt ///
        bl_cnt bl_bureau_cnt bl_social_cnt vb_cnt, ///
    stat(mean sd p25 p50 p75 min max n) columns(statistics)

display _n "Distribution of the count of any backlash channel experienced:"
tab bl_cnt, missing

*------------------------------------------------------------------------------*
* 2.2 Frequency-conditional intensity
*
* Among those reporting occurrence, how often did it happen? This is available
* for D1, D3 and E1 only, because those are the blocks with frequency
* follow-ups.
*------------------------------------------------------------------------------*
display _n(2) "--- 2.2 Frequency among those reporting occurrence ---"
display "Available for D1 (microinsults), D3 (microassaults) and E1"
display "(bureaucratic backlash) only."

foreach v in ma_surprise ma_reserv ma_capacity ma_finance ma_flag ///
             ma_food ma_wait bl_meet bl_files bl_info bl_hostile {
    capture confirm variable `v'_f_n
    if !_rc {
        local lab : variable label `v'
        display _n "  `lab'"
        quietly count if `v'_b == 1
        display "    (among the `r(N)' reporting occurrence)"
        tab `v'_f_n if `v'_b == 1, missing
    }
}

*------------------------------------------------------------------------------*
* 2.3 The perception-experience gap
*
* d4_common asks about SC mukhiyas GENERALLY; the binary items ask about the
* respondent's OWN experience. Under-reporting of own experience relative to
* perceived general prevalence is a recognised pattern in discrimination
* research, and a gap in either direction is substantively interesting.
*------------------------------------------------------------------------------*
display _n(2) "--- 2.3 Perceived general prevalence vs own reported experience ---"
tab ma_common_r, missing
summarize ma_perc_scaled ma_own_rate ma_gap, detail

quietly ttest ma_perc_scaled == ma_own_rate
display _n "Paired comparison of perceived general prevalence (rescaled 0-1)"
display    "against own experience rate (0-1):"
display as result "  mean difference = " %6.3f r(mu_1) - r(mu_2) ///
    "   t = " %5.2f r(t) "   p = " %6.4f r(p)
display _n "This is a within-respondent comparison of two differently"
display    "constructed quantities, so treat it as descriptive rather than as"
display    "a test of a substantive hypothesis. The point is the direction and"
display    "magnitude of the gap, not its p-value."

*------------------------------------------------------------------------------*
* 2.4 The headline comparison statistic
*------------------------------------------------------------------------------*
display _n(2) "--- 2.4 Treatment relative to upper-caste mukhiyas (e1_comparison) ---"
display "Reversed so that higher = worse treatment."
tab bl_compare_r, missing

display _n "Share reporting WORSE treatment than upper-caste mukhiyas:"
display    "This is the cleanest quotable headline statistic in the survey."
quietly ci proportions bl_worse, wilson
display as result "  " %5.1f 100*r(proportion) "%   95% CI [" ///
    %5.1f 100*r(lb) ", " %5.1f 100*r(ub) "]   n = " r(N)

display _n "Overall severity of caste-related difficulties (reversed, 5 = very severe):"
tab bl_severity_r, missing
* display "NOTE: this item was not required in the form, so missingness is"
* display "possible and is not item refusal."

log close prevlog

*--- save the machine-readable prevalence estimates for 12_tables_figures.do ---*
preserve
    use `prevfile', clear
    gen double p_pct  = 100 * p
    gen double lo_pct = 100 * lo
    gen double hi_pct = 100 * hi
    label var p_pct  "Prevalence (%)"
    label var lo_pct "Wilson 95% lower bound (%)"
    label var hi_pct "Wilson 95% upper bound (%)"
    order item theme itemlab p_pct lo_pct hi_pct n
    save "$clean/prevalence_estimates.dta", replace
    export excel using "$out/tab_prevalence_full.xlsx", ///
        firstrow(variables) replace
    display as result "Saved: $clean/prevalence_estimates.dta"
restore

*--- FIGURE: ranked prevalence with CIs ---*
preserve
    use "$clean/prevalence_estimates.dta", clear
	keep in 1/10
    gsort p_pct
    gen byte order = _n

    levelsof order, local(ords)
    local ylab ""
    foreach o of local ords {
        local l = item[`o']
        local ylab `"`ylab' `o' "`l'""'
    }

    twoway (rcap lo_pct hi_pct order, horizontal lcolor(gs9) lwidth(thin)) ///
           (scatter order p_pct, msymbol(O) msize(small) mcolor(maroon)) ///
        , ylabel(`ylab', angle(0) labsize(vsmall)) ///
          ytitle("") xtitle("Prevalence (%)") ///
          xlabel(0(10)60) ///
          title("Prevalence of reported microaggression", ///
                size(medium)) ///
          subtitle("SC mukhiya survey, all binary items", size(small)) ///
          note("             			'Prefer not to say' treated as missing.", ///
               size(vsmall)) ///
          legend(off) graphregion(color(white)) ysize(9) xsize(9)
    graph export "$out/fig_prevalence_ma.png", replace width(1800)
restore

* xlabel(0(20)100)
* title("Prevalence of reported backlash and microaggression"


*==============================================================================*
* SECTION 3. MANSKI BOUNDS ON REFUSAL
*
* Recompute every primary prevalence estimate twice: treating all refusals as
* "yes", then as "no". This BRACKETS the estimate without any assumption about
* the refusal mechanism, which matters because refusal on a sensitive backlash
* item is very unlikely to be independent of the answer and the direction is
* not knowable a priori.
*
* HOW TO READ THE OUTPUT
*   Narrow bounds -> the finding is robust to any refusal mechanism.
*   Wide bounds   -> you have learned that the item cannot support a precise
*                    claim, which is itself worth knowing and reporting.
*
* This is straightforward to implement, easy to explain, and demonstrates the
* kind of inferential care that distinguishes strong work from adequate work.
*==============================================================================*
use "$clean/sc_analysis.dta", clear

capture log close mlog
log using "$out/tab_manski_bounds.txt", replace text name(mlog)

display _n "=================================================================="
display    " MANSKI BOUNDS ON PREVALENCE, GIVEN ITEM REFUSAL"
display    ""
display    " Lower bound: all refusals counted as 'no'  (minimum prevalence)"
display    " Upper bound: all refusals counted as 'yes' (maximum prevalence)"
display    " Point estimate: refusals treated as missing (complete case)"
display    ""
display    " No assumption is made about why respondents refused. The bounds"
display    " hold whatever the mechanism."
display    ""
display    " item | point % | [lower, upper] | refusal % | n"
display    "=================================================================="

tempfile manskifile
tempname mh
postfile `mh' str20 item str80 itemlab ///
    double(p_point p_lower p_upper refusal_rate n_all) using `manskifile', replace

local allitems ""
foreach v of global MA_INSULT {
    local allitems "`allitems' `v'"
}
foreach v in ma_bypass ma_ignored ma_slur ma_food ma_wait {
    local allitems "`allitems' `v'"
}
foreach v of global BL_BUREAU {
    local allitems "`allitems' `v'"
}
foreach v of global BL_INTERN {
    local allitems "`allitems' `v'"
}
foreach v of global BL_COMMUN {
    local allitems "`allitems' `v'"
}
foreach v of global BL_SYMBOL {
    local allitems "`allitems' `v'"
}
foreach v of global BL_VIOLENT {
    local allitems "`allitems' `v'"
}
foreach v of global VB {
    local allitems "`allitems' `v'"
}
foreach v in withdraw_asked bribe_offer elec_threat {
    local allitems "`allitems' `v'"
}

foreach v of local allitems {

    capture confirm variable `v'_b
    if _rc continue

    * denominator: everyone who was asked, INCLUDING refusers. This is the
    * correct denominator for bounds, because a refuser is a person whose
    * true value is unknown, not a person who was never asked.
    quietly count if !missing(`v'_b) | `v'_pns == 1
    local nall = r(N)
    if `nall' == 0 continue

    * point estimate: complete case
    quietly summarize `v'_b
    local ppoint = r(mean)

    * lower bound: refusals -> no
    quietly gen byte _lo = `v'_b
    quietly replace  _lo = 0 if `v'_pns == 1
    quietly summarize _lo
    local plower = r(mean)

    * upper bound: refusals -> yes
    quietly gen byte _hi = `v'_b
    quietly replace  _hi = 1 if `v'_pns == 1
    quietly summarize _hi
    local pupper = r(mean)

    quietly summarize `v'_pns
    local refrate = r(mean)

    drop _lo _hi

    local lab : variable label `v'
    display "  " %-16s "`v'" %6.1f 100*`ppoint' "%  [" %5.1f 100*`plower' ///
        ", " %5.1f 100*`pupper' "]   ref " %4.1f 100*`refrate' "%   n=" %4.0f `nall'

    post `mh' ("`v'") ("`lab'") (`ppoint') (`plower') (`pupper') (`refrate') (`nall')
}
postclose `mh'

display _n "--- Widest bounds (the items that cannot support precise claims) ---"
preserve
    use `manskifile', clear
    gen double width = 100 * (p_upper - p_lower)
    label var width "Bound width in percentage points"
    gsort -width
    list item width refusal_rate p_point in 1/10, clean noobs
    display _n "Any item with a bound width above roughly 10 pp should be"
    display    "reported with the bounds rather than as a point estimate."

    gen double p_point_pct = 100 * p_point
    gen double p_lower_pct = 100 * p_lower
    gen double p_upper_pct = 100 * p_upper
    gen double refusal_pct = 100 * refusal_rate
    save "$clean/manski_bounds.dta", replace
    export excel using "$out/tab_manski_bounds.xlsx", ///
        firstrow(variables) replace
restore

log close mlog


*==============================================================================*
* SECTION 4. ROBUSTNESS: EXPERIENCE ITEMS AND PROXY RESPONDENTS
*
* Modules D, E and F ask about the RESPONDENT'S OWN experience. When a proxy
* answered, those items are not the respondent's own experience. Every
* experience-based estimate is therefore re-run on self-respondents only.
*
* If the two sets of estimates are similar, the proxy interviews are not
* distorting the prevalence figures. If they differ, the self-respondent
* estimates are the defensible ones for experience items, and the difference
* is itself informative about proxy governance.
*==============================================================================*
use "$clean/sc_analysis.dta", clear

capture log close proxylog
log using "$out/tab_prevalence_selfonly.txt", replace text name(proxylog)

display _n "=================================================================="
display    " PREVALENCE RESTRICTED TO SELF-RESPONDENTS"
display    "=================================================================="

quietly count
local n_all = r(N)
quietly count if self_resp == 1
display _n "Full sample n = `n_all'; self-respondents n = `r(N)'"

display _n "--- Index means: all respondents vs self-respondents only ---"
tabstat ma_idx bl_bureau_idx bl_social_idx bl_symbol_idx vb_idx auth_idx, ///
    by(self_resp) stat(mean sd n)

display _n "--- Counts: all vs self-respondents only ---"
tabstat ma_cnt bl_cnt vb_cnt auth_tasks, by(self_resp) stat(mean sd p50 n)

display _n "--- Item prevalence, self-respondents only ---"
foreach v of global MA_INSULT_F {
    quietly ci proportions `v' if self_resp == 1, wilson
    local lab : variable label `v'
    display "  " %-16s "`v'" %6.1f 100*r(proportion) "%  [" ///
        %5.1f 100*r(lb) ", " %5.1f 100*r(ub) "]   `lab'"
}
foreach v of global BL_BUREAU_F {
    quietly ci proportions `v' if self_resp == 1, wilson
    local lab : variable label `v'
    display "  " %-16s "`v'" %6.1f 100*r(proportion) "%  [" ///
        %5.1f 100*r(lb) ", " %5.1f 100*r(ub) "]   `lab'"
}

log close proxylog

display as result _n "=== 05_desc_sc.do complete ==="
display as txt "Authority gap:        $out/tab_authority_gap.txt"
display as txt "Full prevalence:      $out/tab_prevalence_full.txt (+ .xlsx)"
display as txt "Manski bounds:        $out/tab_manski_bounds.txt (+ .xlsx)"
display as txt "Self-respondents:     $out/tab_prevalence_selfonly.txt"
display as txt "Figures:              $out/fig_task_self_exec.png"
display as txt "                      $out/fig_prevalence.png"

*==============================================================================*
* END 05_desc_sc.do
*==============================================================================*

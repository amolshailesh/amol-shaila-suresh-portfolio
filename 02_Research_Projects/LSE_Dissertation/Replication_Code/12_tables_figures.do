*==============================================================================*
* 12_tables_figures.do
*
* PURPOSE : Assemble the final dissertation exhibits. Everything here is a
*           PRESENTATION of results computed in earlier files; no new estimation
*           happens, so nothing in this file can change a finding.
*
* INPUT   : all $clean/*.dta produced by 01 through 11
* OUTPUT  : $out/EXHIBIT_*.rtf and $out/EXHIBIT_*.png
*           $out/exhibit_index.txt
*
* EXHIBIT NUMBERING follows the argument-driven chapter structure recommended in
* §12 of the analysis plan, not the module order of the instruments. The survey
* module order was determined by respondent burden and question flow -- sensitive
* items mid-interview, demographics early, wellbeing late -- which is
* instrument-design logic, not argument logic. Organising the exhibits by module
* would make the reader reconstruct the argument themselves and would bury the
* causal core in the middle of a descriptive sequence.
*
*   Chapter 1 exhibits : Measurement and the anatomy of independence
*   Chapter 2 exhibits : The forms and prevalence of everyday backlash
*   Chapter 3 exhibits : Independence and its costs
*   Chapter 4 exhibits : Experimental evidence on the sources of backlash
*   Chapter 5 exhibits : Comparison and mechanism
*
* The narrative arc: there is a gap -> here is what fills it -> correlation
* cannot tell us why -> experiments can -> and here is how it fits together.
* This foregrounds the strongest evidence and makes each chapter's limitation
* motivate the next chapter's design, so the limitations read as intellectual
* honesty rather than apology.
*==============================================================================*

capture log close exhibitlog
log using "$out/exhibit_index.txt", replace text name(exhibitlog)

display _n "=================================================================="
display    " DISSERTATION EXHIBITS"
display    " Generated: $S_DATE $S_TIME"
display    "=================================================================="


*==============================================================================*
* EXHIBIT 1. SAMPLE DESCRIPTION
*==============================================================================*
display _n(2) "--- EXHIBIT 1: Sample description ---"

use "$clean/pooled_analysis.dta", clear

local descvars auth_idx auth_tasks auth_final_ord eff_mean kn_demo_idx ///
               kn_claim_idx wb_sum_chk educ_ord n_terms n_stood fam_any ///
               gp_vill gp_pop gp_scshare_ord proxy_resp

* A plain-text version is always written, because it has no package dependency
* and is the version to check the numbers against.
capture log close ex1
log using "$out/EXHIBIT_01_sample_description.txt", replace text name(ex1)
display "Exhibit 1. Sample characteristics, SC and non-SC mukhiyas"
display ""
display "Bihar, 2026. Telephone surveys of elected mukhiyas."
display "auth_idx and kn_* are standardised or 0-1 indices; auth_tasks is a"
display "count 0-7; wb_sum_chk is a raw sum 5-25 on a modified five-point scale"
display "that is NOT comparable to published WHO-5 norms."
display ""
tabstat `descvars', by(sc_sample) stat(mean sd n) columns(statistics)
display _n "Differences (t-tests; descriptive only, caste is not assigned):"
foreach v of local descvars {
    capture confirm variable `v'
    if _rc continue
    capture quietly ttest `v', by(sc_sample)
    if !_rc {
        display "  " %-18s "`v'" "  non-SC " %9.3f r(mu_1) "   SC " %9.3f r(mu_2) ///
            "   diff " %9.3f r(mu_2)-r(mu_1) "   p = " %6.4f r(p)
    }
}
log close ex1
display "  Written: EXHIBIT_01_sample_description.txt"

* RTF version via estout. Two separate estpost summarize calls, one per sample,
* rather than estpost tabstat with by(): the by() form stores results in a
* structure esttab handles inconsistently across versions, and two columns is
* what the exhibit needs anyway.
capture which esttab
if !_rc {
    eststo clear
    quietly estpost summarize `descvars' if sc_sample == 0
    eststo nonsc
    quietly estpost summarize `descvars' if sc_sample == 1
    eststo sc

    esttab nonsc sc using "$out/EXHIBIT_01_sample_description.rtf", replace ///
        cells("mean(fmt(2)) sd(fmt(2)) count(fmt(0))") ///
        mtitles("Non-SC mukhiyas" "SC mukhiyas") ///
        label nonumber noobs ///
        title("Exhibit 1. Sample characteristics, SC and non-SC mukhiyas") ///
        addnotes("Bihar, 2026. Telephone surveys of elected mukhiyas." ///
                 "auth_idx and kn_* are standardised or 0-1 indices;" ///
                 "auth_tasks is a count 0-7; wb_sum_chk is a raw sum 5-25 on a" ///
                 "modified five-point scale NOT comparable to WHO-5 norms.")
    display "  Written: EXHIBIT_01_sample_description.rtf"
}


*==============================================================================*
* CHAPTER 1 EXHIBITS: MEASUREMENT AND THE ANATOMY OF INDEPENDENCE
*
* Establishes that the de jure / de facto gap exists and is measurable, before
* any attempt to explain it.
*==============================================================================*
display _n(2) "--- CHAPTER 1 EXHIBITS ---"

use "$clean/sc_analysis.dta", clear

*------------------------------------------------------------------------------*
* Exhibit 2. Distribution of de facto authority
*------------------------------------------------------------------------------*
histogram auth_tasks, discrete percent ///
    xlabel(0(1)7) xtitle("Number of the seven core functions self-executed") ///
    ytitle("Percent of SC mukhiyas") ///
    title("Exhibit 2. How much of the office do SC mukhiyas actually run?", ///
          size(medium)) ///
    note("Seven core functions: cheques and finance, beneficiary lists, chairing" ///
         "the Gram Sabha, meeting the BDO, block-level representation," ///
         "development priorities, and villagers' grievances.", size(vsmall)) ///
    fcolor(navy%60) lcolor(navy) graphregion(color(white))
graph export "$out/EXHIBIT_02_authority_distribution.png", replace width(2000)
display "  Written: EXHIBIT_02_authority_distribution.png"

*------------------------------------------------------------------------------*
* Exhibit 3. Ranked self-execution by function
*
* Rebuilt here rather than reusing the 05_desc_sc.do version, so that the
* exhibit is self-contained and its formatting is under this file's control.
*------------------------------------------------------------------------------*
tempfile taskprev
tempname th
postfile `th' str20 task str36 shortlab double(p lo hi n) using `taskprev', replace

foreach v of global AUTHTASKS {
    quietly ci proportions `v'_self, wilson
    local p = r(proportion)
    local lo = r(lb)
    local hi = r(ub)
    local n = r(N)
    local sl = ""
    if "`v'" == "auth_cheq"  local sl "Cheques and financial documents"
    if "`v'" == "auth_benef" local sl "Scheme beneficiary lists"
    if "`v'" == "auth_gs"    local sl "Chairing the Gram Sabha"
    if "`v'" == "auth_bdo"   local sl "Meeting the BDO and officials"
    if "`v'" == "auth_block" local sl "Block-level representation"
    if "`v'" == "auth_works" local sl "Development work priorities"
    if "`v'" == "auth_griev" local sl "Villagers' grievances"
    post `th' ("`v'") ("`sl'") (`p') (`lo') (`hi') (`n')
}
postclose `th'

preserve
    use `taskprev', clear
    gsort p
    gen byte order = _n
    levelsof order, local(ords)
    local ylab ""
    foreach o of local ords {
        local l = shortlab[`o']
        local ylab `"`ylab' `o' "`l'""'
    }
    twoway (rcap lo hi order, horizontal lcolor(gs7)) ///
           (scatter order p, msymbol(O) mcolor(navy) msize(medium)) ///
        , ylabel(`ylab', angle(0) labsize(small)) ///
          ytitle("") xtitle("Share of SC mukhiyas who perform the task themselves") ///
          xlabel(0(0.2)1, format(%3.1f)) xscale(range(0 1)) ///
          title("Exhibit 3. Which functions does the mukhiya personally perform?", ///
                size(medium)) ///
          note("Wilson 95% confidence intervals. Tasks performed with family" ///
               "assistance are not counted as self-executed.", size(vsmall)) ///
          legend(off) graphregion(color(white))
    graph export "$out/EXHIBIT_03_task_ranking.png", replace width(2000)
    export excel using "$out/EXHIBIT_03_task_ranking.xlsx", ///
        firstrow(variables) replace
restore
display "  Written: EXHIBIT_03_task_ranking.png / .xlsx"

*------------------------------------------------------------------------------*
* Exhibit 4. Final decision authority and self-described proxy status
*------------------------------------------------------------------------------*
graph bar (percent), over(auth_final_ord, label(angle(30) labsize(small))) ///
    ytitle("Percent of SC mukhiyas") ///
    title("Exhibit 4. Who makes the final call on panchayat decisions?", ///
          size(medium)) ///
    subtitle("Self-reported", size(small)) ///
    note("The two rightmost categories are respondents describing proxy status" ///
         "in their own words.", size(vsmall)) ///
    bar(1, fcolor(maroon%60) lcolor(maroon)) graphregion(color(white))
graph export "$out/EXHIBIT_04_final_decision.png", replace width(2000)
display "  Written: EXHIBIT_04_final_decision.png"

*------------------------------------------------------------------------------*
* Exhibit 5. Authority, efficacy and knowledge are distinct
*
* The evidence for the decision not to collapse the three constructs.
*------------------------------------------------------------------------------*
capture log close ex5
log using "$out/EXHIBIT_05_construct_separation.txt", replace text name(ex5)
display "Exhibit 5. Correlations among authority, self-efficacy and knowledge"
display ""
display "Moderate correlations support treating these as separate constructs."
display "Near-unity would suggest they measure one thing and the three-way"
display "separation would need rethinking. Conflating them would make the"
display "independence measure uninterpretable."
display ""
correlate auth_idx auth_tasks eff_idx eff_mean kn_demo_idx kn_claim_idx
display _n "Pairwise correlations with n and p-values:"
pwcorr auth_idx eff_idx kn_demo_idx kn_claim_idx, sig obs
log close ex5
display "  Written: EXHIBIT_05_construct_separation.txt"


*==============================================================================*
* CHAPTER 2 EXHIBITS: THE FORMS AND PREVALENCE OF EVERYDAY BACKLASH
*
* Organised by the four qualitative themes, because here the mapping between the
* survey items and the themes is genuinely tight and the themes supply the
* interpretive vocabulary. This is where the qualitative and quantitative arms
* speak most directly to each other.
*==============================================================================*
display _n(2) "--- CHAPTER 2 EXHIBITS ---"

*------------------------------------------------------------------------------*
* Exhibit 6. Full prevalence table, grouped by theme
*------------------------------------------------------------------------------*
capture confirm file "$clean/prevalence_estimates.dta"
if !_rc {
    preserve
        use "$clean/prevalence_estimates.dta", clear

        * order themes to follow the chapter's narrative rather than
        * alphabetically
        gen byte theme_ord = .
        replace theme_ord = 1 if theme == "BL: bureaucratic"
        replace theme_ord = 2 if theme == "MA: microinsult"
        replace theme_ord = 3 if theme == "MA: microinvalidation"
        replace theme_ord = 4 if theme == "MA: microassault"
        replace theme_ord = 5 if theme == "BL: panchayat-internal"
        replace theme_ord = 6 if theme == "BL: community/elite"
        replace theme_ord = 7 if theme == "BL: entry pressure"
        replace theme_ord = 8 if theme == "BL: symbolic"
        replace theme_ord = 9 if theme == "VB: exposure"
        replace theme_ord = 10 if theme == "BL: overt violence"

        gsort theme_ord -p_pct
        order theme_ord theme item itemlab p_pct lo_pct hi_pct n

        export excel using "$out/EXHIBIT_06_prevalence_by_theme.xlsx", ///
            firstrow(variables) replace

        capture log close ex6
        log using "$out/EXHIBIT_06_prevalence_by_theme.txt", replace text name(ex6)
        display "Exhibit 6. Prevalence of reported backlash and microaggression"
        display ""
        display "SC mukhiya survey. Wilson 95% confidence intervals."
        display "'Prefer not to say' treated as missing; see Exhibit 7 for bounds."
        display ""
        display "  item                   %      [95% CI]        n   question"
        display "  --------------------------------------------------------------"
        levelsof theme_ord, local(tos)
        foreach t of local tos {
            quietly levelsof theme if theme_ord == `t', local(tn) clean
            display _n "  ### `tn'"
            quietly count if theme_ord == `t'
            local nn = r(N)
            forvalues i = 1/`=_N' {
                if theme_ord[`i'] == `t' {
                    display "  " %-18s item[`i'] %6.1f p_pct[`i'] ///
                        "  [" %5.1f lo_pct[`i'] ", " %5.1f hi_pct[`i'] "]" ///
                        %5.0f n[`i'] "  " itemlab[`i']
                }
            }
        }
        log close ex6
    restore
    display "  Written: EXHIBIT_06_prevalence_by_theme.txt / .xlsx"
}
else {
    display as error "  prevalence_estimates.dta not found; run 05_desc_sc.do."
}

*------------------------------------------------------------------------------*
* Exhibit 7. Prevalence with Manski bounds
*
* The exhibit that shows which estimates can support a precise claim and which
* cannot. Narrow bounds mean the finding is robust to any refusal mechanism;
* wide bounds mean the item cannot support a point estimate, which is itself
* worth reporting.
*------------------------------------------------------------------------------*
capture confirm file "$clean/manski_bounds.dta"
if !_rc {
    preserve
        use "$clean/manski_bounds.dta", clear
        gen double bound_width = p_upper_pct - p_lower_pct
        label var bound_width "Bound width, percentage points"
        gsort -bound_width

        export excel using "$out/EXHIBIT_07_manski_bounds.xlsx", ///
            firstrow(variables) replace

        * figure: point estimate with bounds, sorted by point estimate
        gsort p_point_pct
        gen byte order = _n
        levelsof order, local(ords)
        local ylab ""
        foreach o of local ords {
            local l = item[`o']
            local ylab `"`ylab' `o' "`l'""'
        }
        twoway (rcap p_lower_pct p_upper_pct order, horizontal ///
                    lcolor(gs11) lwidth(medthick)) ///
               (scatter order p_point_pct, msymbol(O) msize(vsmall) ///
                    mcolor(maroon)) ///
            , ylabel(`ylab', angle(0) labsize(tiny)) ///
              ytitle("") xtitle("Prevalence (%)") xlabel(0(20)100) ///
              title("Exhibit 7. Prevalence with refusal bounds", size(medium)) ///
              subtitle("Bars span the range from treating all refusals as 'no' to all as 'yes'", ///
                       size(vsmall)) ///
              note("Wide bars indicate items where refusal is common enough that" ///
                   "the point estimate cannot support a precise claim.", size(vsmall)) ///
              legend(off) graphregion(color(white)) ysize(9) xsize(6)
        graph export "$out/EXHIBIT_07_manski_bounds.png", replace width(1800)
    restore
    display "  Written: EXHIBIT_07_manski_bounds.png / .xlsx"
}

*------------------------------------------------------------------------------*
* Exhibit 8. Microaggression by Sue et al. subtype
*------------------------------------------------------------------------------*
use "$clean/sc_analysis.dta", clear

capture log close ex8
log using "$out/EXHIBIT_08_sue_taxonomy.txt", replace text name(ex8)
display "Exhibit 8. Microaggression exposure by Sue et al. (2007) subtype"
display ""
if $slur_as_assault == 1 {
    display "NOTE ON CLASSIFICATION. The caste-slur item (d2_slur) is analysed"
    display "as a MICROASSAULT, not as the microinvalidation the instrument's"
    display "block placement implies. A caste slur is overt, conscious and"
    display "explicitly derogatory, which is Sue et al.'s definition of a"
    display "microassault; it is not a dismissal or a denial. The instrument's"
    display "layout should not override the taxonomy being tested. Footnote"
    display "the discrepancy in the write-up."
    display ""
}
display "Index distributions:"
summarize ma_insult_idx ma_inval_idx ma_assault_idx ma_idx
display _n "Counts of items endorsed:"
tabstat ma_insult_cnt ma_inval_cnt ma_assault_cnt ma_cnt, ///
    stat(mean sd p25 p50 p75 max n) columns(statistics)
display _n "Share reporting at least one of each subtype:"
foreach s in insult inval assault {
    quietly gen byte _any = (ma_`s'_cnt > 0) if !missing(ma_`s'_cnt)
    quietly ci proportions _any, wilson
    display "  " %-14s "`s'" %6.1f 100*r(proportion) "%  [" ///
        %5.1f 100*r(lb) ", " %5.1f 100*r(ub) "]"
    drop _any
}
display _n "Frequency among those reporting occurrence (D1 and D3 only;"
display "the D2 block has no frequency follow-up):"
foreach v in ma_surprise ma_reserv ma_capacity ma_finance ma_flag ma_food ma_wait {
    capture confirm variable `v'_f_n
    if _rc continue
    quietly summarize `v'_f_n if `v'_b == 1
    if r(N) > 0 {
        display "  " %-14s "`v'" "  mean frequency = " %4.2f r(mean) ///
            " of 4   (n = " r(N) ")"
    }
}
log close ex8
display "  Written: EXHIBIT_08_sue_taxonomy.txt"

*------------------------------------------------------------------------------*
* Exhibit 9. The perception-experience gap
*------------------------------------------------------------------------------*
twoway (histogram ma_own_rate, percent width(0.1) start(0) ///
            fcolor(navy%40) lcolor(navy)) ///
       (histogram ma_perc_scaled, percent width(0.1) start(0) ///
            fcolor(maroon%40) lcolor(maroon)) ///
    , xtitle("Rate, rescaled to 0-1") ytitle("Percent of respondents") ///
      title("Exhibit 9. Perceived general prevalence vs own experience", ///
            size(medium)) ///
      note("Own experience is the share of microaggression items the respondent" ///
           "reports experiencing. Perceived prevalence rescales d4_common to 0-1." ///
           "Under-reporting of own experience relative to perceived general" ///
           "prevalence is a recognised pattern in discrimination research.", ///
           size(vsmall)) ///
      legend(order(1 "Own reported experience" 2 "Perceived general prevalence") ///
             size(small)) graphregion(color(white))
graph export "$out/EXHIBIT_09_perception_gap.png", replace width(2000)
display "  Written: EXHIBIT_09_perception_gap.png"


*==============================================================================*
* CHAPTER 3 EXHIBITS: INDEPENDENCE AND ITS COSTS
*
* The association analysis, with the endogeneity problem stated up front rather
* than deferred. Ends by arguing that observational data cannot settle
* direction, which motivates Chapter 4 -- exactly the transition wanted.
*==============================================================================*
display _n(2) "--- CHAPTER 3 EXHIBITS ---"

use "$clean/sc_analysis.dta", clear
local vce "vce(robust)"
if $use_block_cluster == 1 {
    capture encode block, gen(block_n)
    local vce "vce(cluster block_n)"
}

*------------------------------------------------------------------------------*
* Exhibit 10. Forward and reverse specifications side by side
*
* THE point of this exhibit: both directions fit the data comparably, so the
* data cannot distinguish them. Putting them in one table makes the argument
* visually rather than asking the reader to hold two tables in mind.
*------------------------------------------------------------------------------*
eststo clear
foreach y of global PRIMARY_Y {
    eststo f_`y': quietly regress `y' auth_idx $X_DEMOG $X_PANCH $X_POLIT ///
        kn_idx proxy_resp, `vce'
}
foreach x of global PRIMARY_Y {
    eststo b_`x': quietly regress auth_idx `x' $X_DEMOG $X_PANCH $X_POLIT ///
        kn_idx proxy_resp, `vce'
}

capture which esttab
if !_rc {
    esttab f_* using "$out/EXHIBIT_10a_forward.rtf", replace ///
        keep(auth_idx) b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
        stats(N r2, fmt(0 3) labels("Observations" "R-squared")) ///
        mtitles("Microaggression" "Bureaucratic" "Social/elite" "Victim-blaming") ///
        title("Exhibit 10a. Backlash regressed on de facto authority") ///
        addnotes("ASSOCIATIONS, not effects. The reverse specification in" ///
                 "Exhibit 10b fits comparably, which is why no causal reading" ///
                 "is available from these data.") label

    esttab b_* using "$out/EXHIBIT_10b_reverse.rtf", replace ///
        keep($PRIMARY_Y) b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
        stats(N r2, fmt(0 3) labels("Observations" "R-squared")) ///
        title("Exhibit 10b. De facto authority regressed on backlash") ///
        addnotes("Reported to demonstrate that cross-sectional data cannot" ///
                 "distinguish direction. Reverse causation is PREDICTED by the" ///
                 "framework: backlash reimposing the de jure/de facto gap is" ///
                 "the qualitative finding, which makes independence and" ///
                 "backlash simultaneously determined.") label
    display "  Written: EXHIBIT_10a_forward.rtf, EXHIBIT_10b_reverse.rtf"
}

*------------------------------------------------------------------------------*
* Exhibit 11. Coefficient plot across all channels
*------------------------------------------------------------------------------*
eststo clear
foreach y in ma_idx bl_bureau_idx bl_intern_idx bl_commun_idx bl_symbol_idx ///
             bl_violent_idx vb_idx {
    capture confirm variable `y'
    if _rc continue
    eststo p_`y': quietly regress `y' auth_idx $X_DEMOG $X_PANCH $X_POLIT ///
        kn_idx proxy_resp, `vce'
}

capture which coefplot
if !_rc {
    coefplot (p_ma_idx, label("Microaggression, all subtypes")) ///
             (p_bl_bureau_idx, label("Bureaucratic (Theme 1)")) ///
             (p_bl_intern_idx, label("Panchayat-internal (Theme 3)")) ///
             (p_bl_commun_idx, label("Community and elite (Themes 2, 3)")) ///
             (p_bl_symbol_idx, label("Symbolic (Theme 4)")) ///
             (p_bl_violent_idx, label("Overt threat or violence")) ///
             (p_vb_idx, label("Victim-blaming exposure")) ///
        , keep(auth_idx) xline(0, lcolor(gs8) lpattern(dash)) ///
          levels(95 90) ciopts(recast(rcap)) ///
          xtitle("Coefficient on de facto authority (SD units)") ///
          title("Exhibit 11. Authority and backlash, by channel", size(medium)) ///
          subtitle("Full specification; 90% and 95% intervals", size(small)) ///
          note("ASSOCIATIONS. Channels are reported separately because the" ///
               "dissertation's contribution is the contested middle ground" ///
               "between elite capture and physical violence, which a pooled" ///
               "score would erase.", size(vsmall)) ///
          graphregion(color(white)) legend(off)
    graph export "$out/EXHIBIT_11_channels_coefplot.png", replace width(2000)
    display "  Written: EXHIBIT_11_channels_coefplot.png"
}


*==============================================================================*
* CHAPTER 4 EXHIBITS: EXPERIMENTAL EVIDENCE
*
* The causal core. The caste x authority interaction is the chapter's centre of
* gravity, and this is where the dissertation's central claim lives.
*==============================================================================*
display _n(2) "--- CHAPTER 4 EXHIBITS ---"

capture confirm file "$clean/conjoint_long.dta"
if _rc {
    display as error "  conjoint_long.dta not found; run 07 and 08 first."
}
else {

use "$clean/conjoint_long.dta", clear
local vce "vce(cluster uid)"
if "$cj_caste_ref" == "yadav"  local cref 2
if "$cj_caste_ref" == "rajput" local cref 3

*------------------------------------------------------------------------------*
* Exhibit 12. AMCE table, both outcomes
*------------------------------------------------------------------------------*
eststo clear
eststo x_coop:  quietly regress chosen_coop  ib`cref'.caste_n i.auth_n ///
    i.econ_n i.educ_n, `vce'
eststo x_elect: quietly regress chosen_elect ib`cref'.caste_n i.auth_n ///
    i.econ_n i.educ_n, `vce'

capture which esttab
if !_rc {
    esttab x_coop x_elect using "$out/EXHIBIT_12_amce.rtf", replace ///
        b(3) ci(3) star(* 0.10 ** 0.05 *** 0.01) ///
        stats(N r2, fmt(0 3) labels("Profile observations" "R-squared")) ///
        mtitles("Cooperation (primary)" "Election preference (secondary)") ///
        title("Exhibit 12. Average marginal component effects") ///
        addnotes("OLS on stacked profile data; SEs clustered by respondent." ///
                 "Reference: $cj_caste_ref caste, follows elders, poor and" ///
                 "landless, little education." ///
                 "Caste was drawn with unequal probabilities (0.50 SC," ///
                 "0.25 Yadav, 0.25 Rajput), so precision differs across levels." ///
                 "Cooperation is the pre-specified primary outcome.") label
    display "  Written: EXHIBIT_12_amce.rtf"
}

*------------------------------------------------------------------------------*
* Exhibit 13. THE CENTRAL EXHIBIT: the 2x2 marginal means
*
* Readers grasp the interaction far faster from four means than from a
* triple-product coefficient, so this belongs in the main text with the
* interaction coefficient in a table beneath it.
*------------------------------------------------------------------------------*
quietly regress chosen_coop i.p_sc##i.auth_n i.econ_n i.educ_n, `vce'
quietly margins p_sc#auth_n, post

capture which coefplot
if !_rc {
    coefplot, vertical yline(0.5, lcolor(gs9) lpattern(dash)) ///
        ciopts(recast(rcap) lcolor(gs5)) ///
        mcolor(navy) msymbol(O) ///
        ytitle("Probability of being chosen as easier to work with") ///
        ylabel(, format(%3.2f)) ///
        title("Exhibit 13. Does independence amplify the SC penalty?", ///
              size(medium)) ///
        subtitle("Marginal means with 95% confidence intervals", size(small)) ///
        note("Forced-choice design, so 0.5 is the no-preference benchmark." ///
             "This is the dissertation's central causal test. Interpret the" ///
             "magnitude and interval rather than statistical significance:" ///
             "the interaction is the least well-powered quantity in the study.", ///
             size(vsmall)) ///
        graphregion(color(white))
    graph export "$out/EXHIBIT_13_central_2x2.png", replace width(2000)
    display "  Written: EXHIBIT_13_central_2x2.png"
}

*------------------------------------------------------------------------------*
* Exhibit 14. Interaction table with explicit confidence intervals
*------------------------------------------------------------------------------*
use "$clean/conjoint_long.dta", clear
local vce "vce(cluster uid)"

capture log close ex14
log using "$out/EXHIBIT_14_interaction.txt", replace text name(ex14)
display "Exhibit 14. The caste x authority interaction"
display ""
display "PRE-SPECIFIED as the primary hypothesis before the data were examined."
display "Report the confidence interval and the magnitude, not the p-value."
display ""
foreach y in chosen_coop chosen_elect {
    display _n "### `y'"
    quietly regress `y' i.p_sc##i.auth_n i.econ_n i.educ_n, `vce'
    capture {
        quietly lincom 1.p_sc#1.auth_n
        display "  interaction   = " %7.4f r(estimate) " (" %5.1f 100*r(estimate) " pp)"
        display "  95% CI        = [" %5.1f 100*r(lb) " pp, " %5.1f 100*r(ub) " pp]"
        display "  p-value       = " %6.4f r(p)
    }
    display _n "  The four cell means:"
    quietly regress `y' i.p_sc##i.auth_n i.econ_n i.educ_n, `vce'
    margins p_sc#auth_n
}
display _n "HOW TO PHRASE THIS IN THE TEXT"
display ""
display "  'Non-SC mukhiyas were X pp less likely to choose an SC profile as"
display "   easier to work with. That penalty was Y pp among profiles described"
display "   as following established elders and Z pp among those described as"
display "   taking decisions independently, a difference of D pp (95% CI A to"
display "   B). The study is powered to detect interaction effects of"
display "   approximately M pp, so this estimate is consistent with effects"
display "   ranging from A to B.'"
display ""
display "  Do NOT write 'the interaction was not significant, so independence"
display "  does not amplify the penalty'. A confidence interval spanning"
display "  substantively important values does not license that conclusion."
log close ex14
display "  Written: EXHIBIT_14_interaction.txt"

*------------------------------------------------------------------------------*
* Exhibit 15. Allocation experiment
*------------------------------------------------------------------------------*
capture confirm file "$clean/alloc_long.dta"
if !_rc {
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
        coefplot, vertical ciopts(recast(rcap) lcolor(gs5)) ///
            mcolor(maroon) msymbol(O) ///
            ytitle("Rupees spent to reduce the profile's chances") ///
            title("Exhibit 15. Allocation experiment: the 2x2", size(medium)) ///
            subtitle("Respondent fixed effects, 95% confidence intervals", ///
                     size(small)) ///
            note("STATED PREFERENCE with hypothetical stakes, not a costly" ///
                 "behavioural measure. 'Own caste' is respondent-specific, so" ///
                 "the caste contrast conflates anti-SC animus with in-group" ///
                 "favouritism; the conjoint's named castes partially separate" ///
                 "these.", size(vsmall)) ///
            graphregion(color(white))
        graph export "$out/EXHIBIT_15_allocation_2x2.png", replace width(2000)
        display "  Written: EXHIBIT_15_allocation_2x2.png"
    }
}

}   // end chapter 4 block


*==============================================================================*
* CHAPTER 5 EXHIBITS: COMPARISON AND MECHANISM
*==============================================================================*
display _n(2) "--- CHAPTER 5 EXHIBITS ---"

capture confirm file "$clean/pooled_analysis.dta"
if !_rc {

use "$clean/pooled_analysis.dta", clear
local X3 i.educ_ord n_terms n_stood i.mukh_sex_n fam_any ///
         i.gp_scshare_ord ln_gp_pop gp_vill i.gp_mainvill_n i.income_n i.party_n

*------------------------------------------------------------------------------*
* Exhibit 16. The authority gap alongside the capacity gap
*
* The stereotype-refutation exhibit, and the single most rhetorically effective
* table available: it puts the measured authority gap next to the measured
* capacity gap on the same scale, so the reader can see that the second cannot
* explain the first.
*------------------------------------------------------------------------------*
capture log close ex16
log using "$out/EXHIBIT_16_authority_vs_capacity.txt", replace text name(ex16)
display "Exhibit 16. The authority gap and the capacity gap, on one scale"
display ""
display "All differences are ADJUSTED DIFFERENCES in SD units of the pooled"
display "distribution, not effects of caste. Caste is not randomly assigned,"
display "and because Bihar allocates seat reservation by SC population share"
display "the two samples come from systematically different panchayats."
display ""
display "  measure            adjusted difference (SD)   SE (SD)"
display "  ------------------------------------------------------"
foreach y in auth_idx auth_tasks auth_final_ord kn_demo_idx kn_claim_idx ///
             eff_idx eff_mean wb_idx {
    capture confirm variable `y'
    if _rc continue
    quietly summarize `y'
    local sd = r(sd)
    if `sd' <= 0 continue
    quietly regress `y' sc_sample `X3', vce(robust)
    display "  " %-18s "`y'" %14.3f _b[sc_sample]/`sd' %14.3f _se[sc_sample]/`sd'
}
display ""
display "THE ARGUMENT. If the authority difference is detectable on these data"
display "and the knowledge and efficacy differences are not, the authority gap"
display "is not a capacity story. The non-SC instrument independently measures"
display "the BELIEF that SC mukhiyas are less capable, so the stereotype and"
display "the measured reality can be juxtaposed directly."
display ""
display "THE LIMIT. 'No detectable difference' is not 'no difference'. The MDE"
display "here is roughly 0.3 SD, so a genuine small capacity gap would be"
display "invisible. The defensible claim is that the data provide no evidence"
display "of a capacity deficit LARGE ENOUGH to explain the authority gap."
log close ex16
display "  Written: EXHIBIT_16_authority_vs_capacity.txt"

*------------------------------------------------------------------------------*
* Exhibit 17. Task-level comparison figure
*------------------------------------------------------------------------------*
eststo clear
foreach v of global AUTHTASKS {
    capture confirm variable `v'_self
    if _rc continue
    eststo c_`v': quietly regress `v'_self sc_sample `X3', vce(robust)
}
capture which coefplot
if !_rc {
    coefplot (c_auth_cheq,  label("Cheques and finance")) ///
             (c_auth_benef, label("Beneficiary lists")) ///
             (c_auth_gs,    label("Chairing the Gram Sabha")) ///
             (c_auth_bdo,   label("Meeting the BDO")) ///
             (c_auth_block, label("Block representation")) ///
             (c_auth_works, label("Development priorities")) ///
             (c_auth_griev, label("Villagers' grievances")) ///
        , keep(sc_sample) xline(0, lcolor(gs8) lpattern(dash)) ///
          levels(95) ciopts(recast(rcap)) ///
          xtitle("Adjusted SC minus non-SC difference in self-execution") ///
          title("Exhibit 17. Where the authority gap is largest", size(medium)) ///
          subtitle("Adjusted differences with 95% intervals", size(small)) ///
          note("Adjusted differences, NOT effects of caste. Negative values" ///
               "indicate SC mukhiyas perform the function themselves less" ///
               "often.", size(vsmall)) ///
          graphregion(color(white)) legend(off)
    graph export "$out/EXHIBIT_17_task_gap.png", replace width(2000)
    display "  Written: EXHIBIT_17_task_gap.png"
}

}   // end chapter 5 block

*------------------------------------------------------------------------------*
* Exhibit 18. The mixed-methods joint display
*
* Assembled as a spreadsheet so it can be formatted into a landscape table in
* the dissertation. The columns follow §11 of the analysis plan.
*------------------------------------------------------------------------------*
display _n "--- Exhibit 18: joint display ---"

clear
set obs 4
gen byte theme_no = _n
gen str80 theme = ""
gen str200 qual_finding = ""
gen str200 quant_counterpart = ""
gen str120 key_estimate = ""

replace theme = "1. Bureaucratic roadblocks and institutional gatekeeping" in 1
replace qual_finding = "Officials refuse meetings, withhold beneficiary lists, " + ///
    "keep files pending; explicit contrast with treatment of upper-caste mukhiyas" in 1
replace quant_counterpart = "bl_meet, bl_files, bl_info, bl_hostile, bl_compare; " + ///
    "bureaucratic backlash index" in 1
replace key_estimate = "Item prevalence with Wilson CIs; share reporting worse " + ///
    "treatment; association with authority index" in 1

replace theme = "2. Social microaggressions and symbolic delegitimisation" in 2
replace qual_finding = "Caste slurs after years in office; food and seating " + ///
    "exclusion; capability and financial standing questioned; initial social boycott" in 2
replace quant_counterpart = "ma_* items across the three Sue et al. subtypes; " + ///
    "ma_common for perceived prevalence" in 2
replace key_estimate = "Prevalence by subtype; frequency-conditional intensity " + ///
    "(D1 and D3 only); perception-experience gap" in 2

replace theme = "3. Elite strategies to maintain control" in 3
replace qual_finding = "Expectation of proxy leadership; compliant candidates " + ///
    "brought forward; booth capture and voter intimidation" in 3
replace quant_counterpart = "Task displacement to former_mukhiya and up_mukhiya; " + ///
    "bl_exmukh, bl_deputy, bl_ward, bl_cases, bl_organise; wd_asked, bribe_offer; " + ///
    "CONJOINT authority-style AMCE" in 3
replace key_estimate = "Actor composition of displacement; conjoint caste x " + ///
    "authority interaction as the experimental counterpart" in 3

replace theme = "4. Resistance to Ambedkar symbols and rights assertion" in 4
replace qual_finding = "Ambedkar statue broken twice; threats against a gate " + ///
    "named for Ambedkar; opposition to rights awareness in the Gram Sabha" in 4
replace quant_counterpart = "bl_symbols, bl_rights (thin coverage: two items)" in 4
replace key_estimate = "Prevalence with CIs; association with authority index" in 4

label var theme_no           "Theme"
label var theme              "Organising theme"
label var qual_finding       "Qualitative finding (3 Bihar pilot interviews)"
label var quant_counterpart  "Quantitative counterpart"
label var key_estimate       "Estimate reported"

export excel using "$out/EXHIBIT_18_joint_display.xlsx", ///
    firstrow(varlabels) replace
display "  Written: EXHIBIT_18_joint_display.xlsx"
display "  Fill in the realised estimates from tab_joint_display.txt before"
display "  formatting this into the dissertation."


*==============================================================================*
* INDEX OF EXHIBITS
*==============================================================================*
display _n(2) "=================================================================="
display       " INDEX OF EXHIBITS"
display       "=================================================================="
display _n "  Exhibit  1  Sample characteristics, SC and non-SC"
display    "  --- Chapter: Measurement and the anatomy of independence ---"
display    "  Exhibit  2  Distribution of de facto authority (task count)"
display    "  Exhibit  3  Ranked self-execution by function"
display    "  Exhibit  4  Final decision authority and self-described proxy status"
display    "  Exhibit  5  Authority, efficacy and knowledge are distinct constructs"
display _n "  --- Chapter: The forms and prevalence of everyday backlash ---"
display    "  Exhibit  6  Full prevalence table, grouped by qualitative theme"
display    "  Exhibit  7  Prevalence with Manski refusal bounds"
display    "  Exhibit  8  Microaggression by Sue et al. subtype"
display    "  Exhibit  9  Perception-experience gap"
display _n "  --- Chapter: Independence and its costs ---"
display    "  Exhibit 10a Backlash regressed on authority (forward)"
display    "  Exhibit 10b Authority regressed on backlash (reverse)"
display    "  Exhibit 11  Channel-specific associations, coefficient plot"
display _n "  --- Chapter: Experimental evidence on the sources of backlash ---"
display    "  Exhibit 12  Average marginal component effects, both outcomes"
display    "  Exhibit 13  THE CENTRAL 2x2: does independence amplify the penalty?"
display    "  Exhibit 14  Interaction with confidence intervals, and phrasing"
display    "  Exhibit 15  Allocation experiment 2x2"
display _n "  --- Chapter: Comparison and mechanism ---"
display    "  Exhibit 16  Authority gap alongside capacity gap (stereotype loop)"
display    "  Exhibit 17  Where the authority gap is largest, task by task"
display    "  Exhibit 18  Mixed-methods joint display"
display _n "  Supporting output, not numbered as exhibits:"
display    "    qc_report.txt, tab_refusal_rates.txt      (04)"
display    "    tab_recode_check_*.txt                    (02) READ THESE"
display    "    tab_alpha_efficacy.txt, tab_attitude_pca.txt (03)"
display    "    tab_conjoint_randomisation.txt            (07)"
display    "    tab_power_realised.txt                    (11)"

log close exhibitlog

display as result _n "=== 12_tables_figures.do complete ==="
display as txt "All exhibits in: $out"
display as txt "Index:           $out/exhibit_index.txt"

*==============================================================================*
* END 12_tables_figures.do
*==============================================================================*

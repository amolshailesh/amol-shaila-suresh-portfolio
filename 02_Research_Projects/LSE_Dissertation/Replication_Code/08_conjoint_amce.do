*==============================================================================*
* 08_conjoint_amce.do
*
* PURPOSE : Conjoint estimation. AMCEs, marginal means, the caste x authority
*           interaction, and heterogeneity
*
* INPUT   : $clean/conjoint_long.dta
* OUTPUT  : $out/tab_amce_main.rtf / .txt
*           $out/tab_amce_interaction.txt
*           $out/tab_marginal_means.txt
*           $out/tab_amce_heterogeneity.txt
*           $out/tab_amce_robustness.txt
*           $out/fig_amce.png, fig_interaction_2x2.png, fig_marginal_means.png
*
*==============================================================================*
* WHY THIS FILE CARRIES THE DISSERTATION'S CAUSAL CLAIM
*
* The SC survey (06_assoc_sc.do) cannot separate three observationally
* equivalent readings of the authority-backlash association, and one of them
* (backlash suppressing independence) is the dissertation's own theory. The
* conjoint resolves this: authority style is RANDOMLY ASSIGNED, which breaks the
* simultaneity by construction. The caste x authority interaction therefore
* identifies the causal effect of independence on non-SC hostility, free of
* reverse causation and omitted-variable bias.
*
* State this explicitly in the methodology chapter. A dissertation that
* identifies its own identification problem and then shows the design that
* solves it reads very differently from one that reports a regression and calls
* it evidence.
*
* ESTIMATOR
*   OLS (linear probability) on the stacked profile data with SEs clustered by
*   respondent. This is the standard AMCE estimator associated with Hainmueller,
*   Hopkins and Yamamoto (2014), Political Analysis.
*
*   No specialised package is required. Doing it with plain regress makes the
*   estimator transparent in the write-up, which is worth something in a
*   methods-focused viva. R's cregg package is a convenient cross-check.
*
* THE BINDING POWER CONSTRAINT
*   Simulating this exact design (150 respondents, 5 tasks, cluster-robust SEs)
*   gives approximate MDEs of:
*       authority-style AMCE        10.1 pp
*       SC caste AMCE               11.3 pp
*       caste x authority interaction  14.4 pp   <-- the central test
*       AMCE difference across subgroups  ~20.4 pp
*
*   The interaction is simultaneously the LEAST well-powered estimate and the
*   MOST theoretically central. Two consequences, both implemented below:
*     1. Emphasise the confidence interval and the effect magnitude, not the
*        p-value. A point estimate of -0.09 with a CI spanning -0.19 to 0.01 is
*        INFORMATIVE about plausible effect sizes and should be reported as
*        such, not dismissed as a null.
*     2. The interaction is PRE-SPECIFIED as the primary hypothesis, so a modest
*        estimate cannot be retrospectively reframed. That pre-specification is
*        honoured in the code by estimating it first, unconditionally, before
*        any exploratory analysis.
*==============================================================================*

use "$clean/conjoint_long.dta", clear

*------------------------------------------------------------------------------*
* 0. Settings
*------------------------------------------------------------------------------*
* Clustering by respondent throughout. Each respondent contributes 10 correlated
* profile rows; ignoring that would understate the SEs substantially.
local vce "vce(cluster uid)"

* Reference categories. The caste reference is NOT innocuous, which is why the
* plan asks for both. $cj_caste_ref sets the primary; the alternative runs
* automatically in section 1.3.
if "$cj_caste_ref" == "yadav"  local cref 2
if "$cj_caste_ref" == "rajput" local cref 3
if "`cref'" == "" {
    display as error "cj_caste_ref must be 'yadav' or 'rajput'. Check 00_master.do."
    exit 198
}
display as txt "Primary caste reference category: $cj_caste_ref (level `cref')"
display as txt "Authority reference: follows_elders, so the coefficient reads as"
display as txt "the effect of ACTING INDEPENDENTLY."


*==============================================================================*
* SECTION 1. AMCEs
*==============================================================================*
capture log close amcelog
log using "$out/tab_amce_main.txt", replace text name(amcelog)

display _n "=================================================================="
display    " AVERAGE MARGINAL COMPONENT EFFECTS"
display    ""
display    " Outcome designation:"
display    "   PRIMARY   chosen_coop  -- easier to cooperate with"
display    "   SECONDARY chosen_elect -- preferred as mukhiya of own GP"
display    ""
display    " Cooperation is primary for four reasons: it maps directly onto the"
display    " dissertation's object (everyday working relations, withheld"
display    " cooperation, obstruction in the contested middle ground); the"
display    " election framing invites the respondent's own incumbency and"
display    " succession interests into the answer; pre-specifying one primary"
display    " outcome halves the multiple-testing burden on the headline claim;"
display    " and because both are measured on the same randomised profiles,"
display    " their agreement is convergent evidence rather than a second test."
display    ""
display    " Estimator: OLS on stacked profile data, SEs clustered by"
display    " respondent. Coefficients read as changes in the probability of"
display    " being chosen, in percentage points when multiplied by 100."
display    "=================================================================="

*------------------------------------------------------------------------------*
* 1.1 Primary outcome
*------------------------------------------------------------------------------*
display _n "--- 1.1 PRIMARY OUTCOME: chosen_coop ---"

eststo clear

eststo amce_coop: regress chosen_coop ib`cref'.caste_n i.auth_n i.econ_n ///
    i.educ_n, `vce'

display _n "Interpretation of the caste coefficients: the change in the"
display    "probability of being chosen relative to a $cj_caste_ref profile,"
display    "averaging over the realised distribution of the other attributes."

*------------------------------------------------------------------------------*
* 1.2 Secondary outcome
*------------------------------------------------------------------------------*
display _n "--- 1.2 SECONDARY OUTCOME: chosen_elect ---"

eststo amce_elect: regress chosen_elect ib`cref'.caste_n i.auth_n i.econ_n ///
    i.educ_n, `vce'

*------------------------------------------------------------------------------*
* 1.3 The alternative caste reference
*------------------------------------------------------------------------------*
if `cref' == 2 local altref 3
if `cref' == 3 local altref 2
local altname "rajput"
if `altref' == 2 local altname "yadav"

display _n "--- 1.3 Alternative caste reference: `altname' ---"
eststo amce_coop_alt: regress chosen_coop ib`altref'.caste_n i.auth_n ///
    i.econ_n i.educ_n, `vce'

*------------------------------------------------------------------------------*
* 1.4 With profile-position control
*------------------------------------------------------------------------------*
display _n "--- 1.4 Controlling for profile position ---"
display "Included as a robustness column in case respondents systematically"
display "favoured the first or second profile presented."
eststo amce_coop_pos: regress chosen_coop ib`cref'.caste_n i.auth_n ///
    i.econ_n i.educ_n prof_b, `vce'

*------------------------------------------------------------------------------*
* 1.5 Export
*------------------------------------------------------------------------------*
capture which esttab
if !_rc {
    esttab amce_coop amce_elect amce_coop_alt amce_coop_pos ///
        using "$out/tab_amce_main.rtf", replace ///
        b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
        stats(N r2, fmt(0 3) labels("Profile observations" "R-squared")) ///
        mtitles("Cooperation" "Election" "Alt. reference" "+ Position") ///
        title("Average marginal component effects") ///
        addnotes("OLS on stacked profile data; SEs clustered by respondent." ///
                 "Caste drawn with unequal probabilities (0.50 SC / 0.25 Yadav" ///
                 "/ 0.25 Rajput), so precision differs across caste levels." ///
                 "Approximate MDE: 11.3 pp for the SC AMCE, 10.1 pp for" ///
                 "authority style.") ///
        label
}
else {
    display as error "esttab not installed. ssc install estout"
}

log close amcelog


*==============================================================================*
* SECTION 2. MARGINAL MEANS
*
* Reported alongside the AMCEs because marginal means are LESS SENSITIVE TO
* REFERENCE-CATEGORY CHOICE and are the recommended presentation for subgroup
* comparisons. The relevant methodological reference is Leeper, Hobolt and 
* Tilley in Political Analysis.
*
* A marginal mean is the average probability of a profile with a given attribute
* level being chosen, averaging over everything else. In a forced-choice design
* with two profiles the marginal means are centred on 0.5 by construction, so a
* level with a marginal mean of 0.42 is chosen 42% of the time it appears.
*==============================================================================*
capture log close mmlog
log using "$out/tab_marginal_means.txt", replace text name(mmlog)

display _n "=================================================================="
display    " MARGINAL MEANS"
display    ""
display    " Read as: the probability that a profile with this attribute level"
display    " is chosen, averaging over the other attributes. Centred on 0.5 by"
display    " the forced-choice design."
display    ""
display    " Preferred over AMCEs for subgroup comparisons because they do not"
display    " depend on a reference category."
display    "=================================================================="

foreach y in chosen_coop chosen_elect {
    display _n(2) "### OUTCOME: `y'"

    quietly regress `y' i.caste_n i.auth_n i.econ_n i.educ_n, `vce'

    display _n "--- Caste ---"
    margins caste_n
    display _n "--- Authority style ---"
    margins auth_n
    display _n "--- Economic status ---"
    margins econ_n
    display _n "--- Education ---"
    margins educ_n
}

*--- the 2x2 cells that constitute the central test, as marginal means ---*
display _n(2) "=================================================================="
display       " THE CENTRAL 2x2 AS MARGINAL MEANS"
display       "=================================================================="

* SC vs non-SC collapsed, crossed with authority style
gen byte p_nonsc = 1 - p_sc
label var p_nonsc "Profile is not Scheduled Caste (Yadav or Rajput)"

foreach y in chosen_coop chosen_elect {
    display _n "### OUTCOME: `y'"
    quietly regress `y' i.p_sc##i.auth_n i.econ_n i.educ_n, `vce'
    margins p_sc#auth_n
    display _n "Pairwise contrasts between the four cells:"
    margins p_sc#auth_n, pwcompare(effects)
}

* full three-level caste crossed with authority style
display _n(2) "--- Full caste (3 levels) x authority style ---"
quietly regress chosen_coop i.caste_n##i.auth_n i.econ_n i.educ_n, `vce'
margins caste_n#auth_n

log close mmlog


*==============================================================================*
* SECTION 3. THE CENTRAL TEST: CASTE x AUTHORITY INTERACTION
*
* Does the penalty attaching to an SC profile GROW when that profile is
* described as acting independently?
*
* A negative interaction is the experimental analogue of the qualitative
* finding that backlash intensifies against SC mukhiyas who resist proxy status.
*==============================================================================*
capture log close intlog
log using "$out/tab_amce_interaction.txt", replace text name(intlog)

display _n "=================================================================="
display    " THE CENTRAL TEST: CASTE x AUTHORITY INTERACTION"
display    ""
display    " PRE-SPECIFIED as the primary hypothesis. Approximate MDE 14.4 pp."
display    "=================================================================="

eststo clear

foreach y in chosen_coop chosen_elect {

    display _n(2) "########## OUTCOME: `y' ##########"

    *--- 3.1 binary SC vs non-SC specification ---*
    display _n "--- 3.1 SC vs non-SC, interacted with authority style ---"
    eststo int_`y': regress `y' i.p_sc##i.auth_n i.econ_n i.educ_n, `vce'

    * extract and display the interaction with its CI, which is what to report
    quietly lincom 1.p_sc#1.auth_n
    display _n as result "  INTERACTION (SC x independent):"
    display    as result "    point estimate = " %7.4f r(estimate) ///
        "  (" %5.1f 100*r(estimate) " pp)"
    display    as result "    SE             = " %7.4f r(se)
    display    as result "    95% CI         = [" %7.4f r(lb) ", " %7.4f r(ub) "]"
    display    as result "                     [" %5.1f 100*r(lb) " pp, " ///
        %5.1f 100*r(ub) " pp]"
    display    as result "    p-value        = " %6.4f r(p)
    display _n "  Compare the CI width with the 14.4 pp MDE: if the CI spans"
    display    "  roughly that width, the study is doing what it was powered to"
    display    "  do and the estimate should be interpreted for magnitude."

    *--- 3.2 the four cell means and the difference-in-differences ---*
    display _n "--- 3.2 The four cells, and the DiD written out ---"
    quietly regress `y' i.p_sc##i.auth_n i.econ_n i.educ_n, `vce'
    margins p_sc#auth_n

    display _n "  SC penalty among COMPLIANT profiles:"
    quietly margins, dydx(p_sc) at(auth_n = 0)
    matrix b = r(b)
    matrix V = r(V)
    display as result "    " %7.4f b[1,2] "  (se " %6.4f sqrt(V[2,2]) ")"

    display _n "  SC penalty among INDEPENDENT profiles:"
    quietly margins, dydx(p_sc) at(auth_n = 1)
    matrix b = r(b)
    matrix V = r(V)
    display as result "    " %7.4f b[1,2] "  (se " %6.4f sqrt(V[2,2]) ")"

    display _n "  The difference between those two penalties IS the interaction."
    display    "  Presenting it this way is more legible than the product term:"
    display    "  'the SC penalty is X pp among compliant profiles and Y pp"
    display    "   among independent ones'."

    *--- 3.3 three-level caste specification ---*
    display _n "--- 3.3 Full caste (3 levels) x authority ---"
    display "Retains the Yadav / Rajput distinction, at the cost of precision"
    display "on the two smaller cells (each drawn with probability 0.25)."
    eststo int3_`y': regress `y' ib`cref'.caste_n##i.auth_n i.econ_n i.educ_n, `vce'

    display _n "Interaction terms:"
    capture {
        quietly lincom 1.caste_n#1.auth_n
        display as result "  SC x independent (vs $cj_caste_ref):  " ///
            %7.4f r(estimate) "  [" %7.4f r(lb) ", " %7.4f r(ub) "]  p = " %6.4f r(p)
    }
}

capture which esttab
if !_rc {
    esttab int_chosen_coop int_chosen_elect int3_chosen_coop int3_chosen_elect ///
        using "$out/tab_amce_interaction.rtf", replace ///
        b(3) star(* 0.10 ** 0.05 *** 0.01) ci(3) ///
        stats(N r2, fmt(0 3) labels("Profile observations" "R-squared")) ///
        mtitles("Coop 2-level" "Elect 2-level" "Coop 3-level" "Elect 3-level") ///
        title("Caste x authority-style interaction (pre-specified primary test)") ///
        addnotes("The interaction is the dissertation's central quantitative" ///
                 "parameter. Approximate MDE 14.4 pp; interpret magnitude and" ///
                 "confidence interval rather than statistical significance." ///
                 "SEs clustered by respondent.") ///
        label
}

log close intlog

*--- FIGURE: the 2x2 marginal means with CIs ---*
quietly regress chosen_coop i.p_sc##i.auth_n i.econ_n i.educ_n, `vce'
quietly margins p_sc#auth_n, post
capture which coefplot
if !_rc {
    coefplot, vertical ///
        yline(0.5, lcolor(gs10) lpattern(dash)) ///
        ciopts(recast(rcap)) ///
        ytitle("Probability of being chosen as easier to work with") ///
        title("The central test: does independence amplify the SC penalty?", ///
              size(medium)) ///
        subtitle("Marginal means with 95% confidence intervals", size(small)) ///
        note("Forced-choice design, so 0.5 is the no-preference benchmark." ///
             "Approximate MDE for the interaction is 14.4 pp.", size(vsmall)) ///
        graphregion(color(white))
    graph export "$out/fig_interaction_2x2.png", replace width(2000)
}

*--- FIGURE: AMCE plot ---*
use "$clean/conjoint_long.dta", clear
eststo clear
eststo a_coop:  quietly regress chosen_coop  ib`cref'.caste_n i.auth_n ///
    i.econ_n i.educ_n, vce(cluster uid)
eststo a_elect: quietly regress chosen_elect ib`cref'.caste_n i.auth_n ///
    i.econ_n i.educ_n, vce(cluster uid)

capture which coefplot
if !_rc {
    coefplot (a_coop, label("Cooperation (primary)")) ///
             (a_elect, label("Election preference (secondary)")) ///
        , drop(_cons) xline(0, lcolor(gs8) lpattern(dash)) ///
          levels(95 90) ciopts(recast(rcap)) ///
          xtitle("Change in probability of being chosen") ///
          title("Average marginal component effects", size(medium)) ///
          subtitle("Reference: $cj_caste_ref caste, follows elders, poor and landless, little education", ///
                   size(vsmall)) ///
          note("SEs clustered by respondent. 90% and 95% intervals.", size(vsmall)) ///
          graphregion(color(white))
    graph export "$out/fig_amce.png", replace width(2000)
}


*==============================================================================*
* SECTION 4. HETEROGENEITY   (§6.5)
*
* PRIMARY MODERATOR: the first principal component of the Module C attitude
* battery, PRE-SPECIFIED in 03_indices.do before any outcome was examined. This
* gives the direct analogue of the Cullen et al. (2024) finding that backlash
* concentrated among men holding conservative gender attitudes -- the parallel
* the theoretical framework already invokes. Note that the parallel is
* structural, not identical: caste and gender hierarchies operate through
* different mechanisms and the framing in the write-up must not conflate them.
*
* BE CANDID ABOUT POWER. The MDE for an AMCE DIFFERENCE across two 75-person
* subgroups is roughly 20.4 pp, and the triple interaction is worse still.
* Report as exploratory, with CIs, and resist interpreting sign alone.
*==============================================================================*
use "$clean/conjoint_long.dta", clear
local vce "vce(cluster uid)"

capture log close hetlog
log using "$out/tab_amce_heterogeneity.txt", replace text name(hetlog)

display _n "=================================================================="
display    " HETEROGENEITY"
display    ""
display    " EXPLORATORY. The MDE for an AMCE difference across two 75-person"
display    " subgroups is roughly 20.4 pp; the triple interaction is worse."
display    " Report confidence intervals and do not interpret sign alone."
display    ""
display    " Moderators are PRE-SPECIFIED and every one is reported whatever"
display    " the result, so there is no scope for selective reporting."
display    "=================================================================="

*------------------------------------------------------------------------------*
* 4.1 Primary moderator: prejudice (first principal component)
*------------------------------------------------------------------------------*
display _n "--- 4.1 PRIMARY MODERATOR: prejudice index (attitude battery PC1) ---"
display "prej_pc1 is standardised and oriented so that HIGHER = MORE"
display "PREJUDICED (the sign was fixed in 03_indices.do by anchoring on"
display "at_resincap, since principal-component signs are arbitrary)."

display _n "Continuous moderation, with the full triple interaction:"
eststo clear
eststo het_cont: regress chosen_coop ///
    i.p_sc##i.auth_n##c.prej_pc1 i.econ_n i.educ_n, `vce'

display _n "The triple interaction is the coefficient of interest here, and it"
display    "is very underpowered:"
capture {
    quietly lincom 1.p_sc#1.auth_n#c.prej_pc1
    display as result "  triple interaction = " %7.4f r(estimate) ///
        "  [" %7.4f r(lb) ", " %7.4f r(ub) "]  p = " %6.4f r(p)
}

display _n "Marginal means at low and high prejudice (-1 SD and +1 SD):"
margins p_sc#auth_n, at(prej_pc1 = (-1 0 1))

display _n "--- Split-sample version, for legibility ---"
display "The continuous specification above is the primary one. The split is"
display "reported because a 2x2 of marginal means within each half is far"
display "easier for a reader to interpret than a triple product."
quietly summarize prej_pc1, detail
local pmed = r(p50)
gen byte high_prej = (prej_pc1 > `pmed') if !missing(prej_pc1)
label var high_prej "Above-median prejudice index"
label define hp 0 "Below-median prejudice" 1 "Above-median prejudice", replace
label values high_prej hp
tab high_prej

foreach h in 0 1 {
    display _n "  Subgroup: high_prej == `h'"
    quietly regress chosen_coop i.p_sc##i.auth_n i.econ_n i.educ_n ///
        if high_prej == `h', `vce'
    margins p_sc#auth_n
    capture {
        quietly lincom 1.p_sc#1.auth_n
        display as result "    interaction = " %7.4f r(estimate) ///
            "  [" %7.4f r(lb) ", " %7.4f r(ub) "]  n = " e(N)
    }
}

*------------------------------------------------------------------------------*
* 4.2 Secondary moderators, all pre-specified
*------------------------------------------------------------------------------*
display _n(2) "--- 4.2 Secondary moderators ---"

*--- respondent's own caste category ---*
display _n "### Respondent's own caste category (General / BC-1 / BC-2) ###"
display "This bears on whether hostility to SC profiles is concentrated among"
display "General-category respondents or is shared across the non-SC"
display "categories. Cell sizes will be small; read the CIs."
capture {
    tab caste_cat_n
    quietly regress chosen_coop i.p_sc##i.auth_n##i.caste_cat_n ///
        i.econ_n i.educ_n, `vce'
    margins p_sc#auth_n#caste_cat_n
}

*--- SC population share of the respondent's own panchayat ---*
display _n "### SC population share of the respondent's panchayat ###"
display "A group-threat reading predicts more hostility where the SC share is"
display "larger. A contact reading predicts the opposite. Either is a finding."
capture {
    quietly regress chosen_coop i.p_sc##i.auth_n##c.gp_scshare_ord ///
        i.econ_n i.educ_n, `vce'
    margins p_sc#auth_n, at(gp_scshare_ord = (1 2 3 4))
}

*--- respondent's own de facto authority ---*
display _n "### Respondent's own de facto authority index ###"
display "Do non-SC mukhiyas who themselves exercise more authority react"
display "differently to an independently acting SC profile?"
capture {
    quietly regress chosen_coop i.p_sc##i.auth_n##c.auth_idx ///
        i.econ_n i.educ_n, `vce'
    margins p_sc#auth_n, at(auth_idx = (-1 0 1))
}

*--- respondent's education ---*
display _n "### Respondent's education (secondary or above) ###"
capture {
    quietly regress chosen_coop i.p_sc##i.auth_n##i.educ_sec ///
        i.econ_n i.educ_n, `vce'
    margins p_sc#auth_n#educ_sec
}

*--- victim-blaming endorsement specifically ---*
display _n "### Victim-blaming endorsement (at_vb_idx) ###"
display "This is the most theoretically targeted moderator available: it asks"
display "whether the respondents who endorse the view that SC mukhiyas bring"
display "their problems on themselves are also the ones who penalise"
display "independent SC profiles. If so, the attitude and the behaviour"
display "cohere, which strengthens the interpretation of both."
capture {
    quietly regress chosen_coop i.p_sc##i.auth_n##c.at_vb_idx ///
        i.econ_n i.educ_n, `vce'
    margins p_sc#auth_n, at(at_vb_idx = (-1 0 1))
}

log close hetlog


*==============================================================================*
* SECTION 5. ROBUSTNESS
*==============================================================================*
use "$clean/conjoint_long.dta", clear
local vce "vce(cluster uid)"

capture log close cjroblog
log using "$out/tab_amce_robustness.txt", replace text name(cjroblog)

display _n "=================================================================="
display    " CONJOINT ROBUSTNESS"
display    "=================================================================="

*------------------------------------------------------------------------------*
* 5.1 Excluding flip-guard tasks  (the disclosure the design requires)
*
* In tasks where the guard fired, caste was NOT independently randomised across
* profiles: profile B's caste was deterministically set by a three-way cycle
* from profile A's. Excluding those tasks removes the departure from
* independence entirely. If the estimates are stable, the issue is closed.
* Report both.
*------------------------------------------------------------------------------*
display _n "--- 5.1 Excluding tasks where the flip guard fired ---"
quietly count if cj_flip == 1
display "Profile rows in flip-guard tasks: `r(N)'"

eststo clear
eststo r_all:  quietly regress chosen_coop i.p_sc##i.auth_n i.econ_n i.educ_n, `vce'
quietly lincom 1.p_sc#1.auth_n
display "  All tasks:            interaction = " %7.4f r(estimate) ///
    "  [" %7.4f r(lb) ", " %7.4f r(ub) "]  n = " e(N)

eststo r_noflip: quietly regress chosen_coop i.p_sc##i.auth_n i.econ_n i.educ_n ///
    if cj_flip == 0, `vce'
quietly lincom 1.p_sc#1.auth_n
display "  Excluding flip tasks: interaction = " %7.4f r(estimate) ///
    "  [" %7.4f r(lb) ", " %7.4f r(ub) "]  n = " e(N)

display _n "  Also comparing the caste AMCE:"
quietly regress chosen_coop ib`cref'.caste_n i.auth_n i.econ_n i.educ_n, `vce'
display "    All tasks, SC coefficient    = " %7.4f _b[1.caste_n]
quietly regress chosen_coop ib`cref'.caste_n i.auth_n i.econ_n i.educ_n ///
    if cj_flip == 0, `vce'
display "    Excluding flip, SC coeff.    = " %7.4f _b[1.caste_n]

*------------------------------------------------------------------------------*
* 5.2 Comprehension
*------------------------------------------------------------------------------*
display _n "--- 5.2 Restricting to respondents who grasped the task ---"
display "q_conjoint_r is the enumerator's assessment, reversed so 3 = understood"
display "well. A conjoint delivered by telephone places real cognitive demands"
display "on the respondent, so this is not a pro-forma check."
tab q_conjoint_r if task == 1 & profile == "a"

foreach threshold in 3 2 {
    quietly regress chosen_coop i.p_sc##i.auth_n i.econ_n i.educ_n ///
        if q_conjoint_r >= `threshold', `vce'
    quietly lincom 1.p_sc#1.auth_n
    display "  q_conjoint_r >= `threshold': interaction = " %7.4f r(estimate) ///
        "  [" %7.4f r(lb) ", " %7.4f r(ub) "]  n = " e(N)
}

*------------------------------------------------------------------------------*
* 5.3 Learning and fatigue across tasks
*
* Five tasks in a telephonic interview may produce either learning (later tasks
* better understood) or fatigue (later tasks answered more carelessly).
* Interacting the treatment with task number tests for both.
*------------------------------------------------------------------------------*
display _n "--- 5.3 Does the effect vary across tasks? ---"
quietly regress chosen_coop i.p_sc##i.auth_n##c.task i.econ_n i.educ_n, `vce'
capture {
    quietly lincom 1.p_sc#1.auth_n#c.task
    display "  interaction x task number = " %7.4f r(estimate) ///
        "  [" %7.4f r(lb) ", " %7.4f r(ub) "]  p = " %6.4f r(p)
}
display _n "  By task, first vs last:"
foreach t in 1 5 {
    quietly regress chosen_coop i.p_sc##i.auth_n i.econ_n i.educ_n ///
        if task == `t', `vce'
    capture {
        quietly lincom 1.p_sc#1.auth_n
        display "    task `t': interaction = " %7.4f r(estimate) "  n = " e(N)
    }
}
display _n "  Dropping the first task (in case of a warm-up effect):"
quietly regress chosen_coop i.p_sc##i.auth_n i.econ_n i.educ_n if task > 1, `vce'
capture {
    quietly lincom 1.p_sc#1.auth_n
    display "    interaction = " %7.4f r(estimate) "  n = " e(N)
}

*------------------------------------------------------------------------------*
* 5.4 Excluding proxy respondents and low-quality interviews
*------------------------------------------------------------------------------*
display _n "--- 5.4 Sample restrictions ---"
foreach r in "self_resp == 1" "lowqual == 0" {
    quietly regress chosen_coop i.p_sc##i.auth_n i.econ_n i.educ_n if `r', `vce'
    capture {
        quietly lincom 1.p_sc#1.auth_n
        display "  `r': interaction = " %7.4f r(estimate) ///
            "  [" %7.4f r(lb) ", " %7.4f r(ub) "]  n = " e(N)
    }
}

*------------------------------------------------------------------------------*
* 5.5 Respondent fixed effects
*
* Because the attributes were randomised WITHIN respondent, respondent fixed
* effects are available and absorb all respondent-level heterogeneity. They are
* not necessary for unbiasedness (randomisation already delivers that) but they
* can improve precision, and their inclusion is a useful check: a large change
* in the estimate would indicate that the randomisation was not in fact
* independent of respondent characteristics.
*------------------------------------------------------------------------------*
display _n "--- 5.5 With respondent fixed effects ---"
capture which reghdfe
if !_rc {
    quietly reghdfe chosen_coop i.p_sc##i.auth_n i.econ_n i.educ_n, ///
        absorb(uid) vce(cluster uid)
    capture {
        quietly lincom 1.p_sc#1.auth_n
        display "  reghdfe with respondent FE: interaction = " %7.4f r(estimate) ///
            "  [" %7.4f r(lb) ", " %7.4f r(ub) "]"
    }
}
else {
    display as txt "  reghdfe not installed; using areg (official Stata)."
    quietly areg chosen_coop i.p_sc##i.auth_n i.econ_n i.educ_n, ///
        absorb(uid) vce(cluster uid)
    capture {
        quietly lincom 1.p_sc#1.auth_n
        display "  areg with respondent FE: interaction = " %7.4f r(estimate) ///
            "  [" %7.4f r(lb) ", " %7.4f r(ub) "]"
    }
}

*------------------------------------------------------------------------------*
* 5.6 Logit as a functional-form check
*
* The linear probability model is primary because its coefficients read directly
* as percentage-point changes, which is what a conjoint is for. Logit is
* reported to confirm that the LPM is not producing the result through its
* functional form. Note that logit interaction terms are NOT directly
* comparable to LPM ones: the marginal effects are what to compare.
*------------------------------------------------------------------------------*
display _n "--- 5.6 Logit, compared via average marginal effects ---"
quietly logit chosen_coop i.p_sc##i.auth_n i.econ_n i.educ_n, `vce'
display _n "  Average marginal effects from logit:"
margins, dydx(p_sc auth_n)
display _n "  Marginal means by cell, from logit:"
margins p_sc#auth_n

display _n "  For comparison, the LPM:"
quietly regress chosen_coop i.p_sc##i.auth_n i.econ_n i.educ_n, `vce'
margins p_sc#auth_n

log close cjroblog

display as result _n "=== 08_conjoint_amce.do complete ==="
display as txt "AMCEs:          $out/tab_amce_main.txt (+ .rtf)"
display as txt "Marginal means: $out/tab_marginal_means.txt"
display as txt "Interaction:    $out/tab_amce_interaction.txt (+ .rtf)"
display as txt "Heterogeneity:  $out/tab_amce_heterogeneity.txt"
display as txt "Robustness:     $out/tab_amce_robustness.txt"
display as txt "Figures:        $out/fig_amce.png, fig_interaction_2x2.png"

*==============================================================================*
* END 08_conjoint_amce.do
*==============================================================================*

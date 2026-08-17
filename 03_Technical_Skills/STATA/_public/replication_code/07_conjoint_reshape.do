*==============================================================================*
* 07_conjoint_reshape.do
*
* PURPOSE : Reshape the conjoint experiment from wide (one row per respondent)
*           to long (one row per respondent x task x profile), and run
*           randomisation diagnostics.
*
* INPUT   : $clean/nonsc_analysis.dta
* OUTPUT  : $clean/conjoint_long.dta
*           $out/tab_conjoint_randomisation.txt
*
* TARGET STRUCTURE
*   Each respondent contributes 5 tasks x 2 profiles = 10 profile-level rows.
*   With n = 150 that is 1,500 profile observations.
*
* THE RESHAPE IS TWO STEPS, NOT ONE
*   Step 1: wide -> respondent x task     (150 -> 750 rows)
*   Step 2: task -> respondent x task x profile  (750 -> 1,500 rows)
*==============================================================================*

use "$clean/nonsc_analysis.dta", clear

*------------------------------------------------------------------------------*
* 0. Record the starting point and keep only what the long file needs
*------------------------------------------------------------------------------*
count
local n_resp = r(N)
display as result "Respondents entering the conjoint reshape: `n_resp'"

* Respondent-level variables carried into the long file. Everything here is
* constant within respondent, so it will be duplicated across the 10 rows.
* Keep the moderators and the covariates needed for the heterogeneity analysis.
local keepvars uid prej_pc1 prej_pc2 prej_pc3 prej_z                   	///
               at_res_idx at_stereo_idx at_poa_idx at_vb_idx           	///
               caste_cat_n educ_ord educ_sec income_n party_n          	///
               mukh_sex_n n_terms n_stood                              	///
               gp_scshare_ord gp_scshare_ns ln_gp_pop           		///
               revenue_villages gp_mainvill_n fam_any                   ///
               auth_idx auth_tasks eff_idx kn_demo_idx wb_idx	        ///
               proxy_resp self_resp lowqual q_underst_r q_sincere_r    	///
               q_conjoint q_conjoint_r pns_rate

* geography, if the frame merge supplied it
foreach v in district block gp strata sample_group kobo_user dur_min speeder {
    capture confirm variable `v'
    if !_rc local keepvars "`keepvars' `v'"
}

* the conjoint variables themselves
foreach t in 1 2 3 4 5 {
    local keepvars "`keepvars' cj_caste_a`t' cj_caste_b`t'"
    local keepvars "`keepvars' cj_auth_a`t'  cj_auth_b`t'"
    local keepvars "`keepvars' cj_econ_a`t'  cj_econ_b`t'"
    local keepvars "`keepvars' cj_educ_a`t'  cj_educ_b`t'"
    local keepvars "`keepvars' cj_flip`t' cj_coop`t' cj_elect`t'"
}

keep `keepvars'

* uid must be unique before reshaping, or the i() specification is invalid
isid uid

*------------------------------------------------------------------------------*
* 1. STEP ONE: wide -> respondent x task
*------------------------------------------------------------------------------*
reshape long cj_caste_a cj_caste_b cj_auth_a cj_auth_b ///
             cj_econ_a  cj_econ_b  cj_educ_a cj_educ_b ///
             cj_flip    cj_coop    cj_elect, ///
        i(uid) j(task)

label var task "Conjoint task number (1-5)"

* assertion: exactly five tasks per respondent
count
local n_task = r(N)
display as result "Rows after step 1 (respondent x task): `n_task'"
assert `n_task' == `n_resp' * 5
display as result "  Assertion passed: `n_resp' respondents x 5 tasks."

isid uid task

*------------------------------------------------------------------------------*
* 2. STEP TWO: respondent x task -> respondent x task x profile
*
* taskid uniquely identifies a respondent-task and becomes the i() for the
* second reshape. Built with egen group() on a SORTED key rather than _n,
* because _n depends on the current sort order and would not be reproducible
* if the file were ever re-sorted upstream. This is the same reproducibility
* lesson as the sampling do-file: never let a row number carry meaning.
*------------------------------------------------------------------------------*
sort uid task
egen long taskid = group(uid task)
label var taskid "Unique respondent x task identifier"
isid taskid

* The stubs for the second reshape end in an underscore, and the suffix is a
* bare a/b. That is why the naming convention in 01_import_merge.do used
* cj_caste_a rather than cj_caste_A: reshape treats "cj_caste_" as the stub and
* "a"/"b" as the j values.
reshape long cj_caste_ cj_auth_ cj_econ_ cj_educ_, i(taskid) j(profile) string

rename cj_caste_ cj_caste
rename cj_auth_  cj_auth
rename cj_econ_  cj_econ
rename cj_educ_  cj_educ

label var profile  "Profile within task (a = Mukhiya 1, b = Mukhiya 2)"
label var cj_caste "Profile caste attribute"
label var cj_auth  "Profile authority style attribute"
label var cj_econ  "Profile economic status attribute"
label var cj_educ  "Profile education attribute"

count
local n_prof = r(N)
display as result "Rows after step 2 (respondent x task x profile): `n_prof'"
assert `n_prof' == `n_resp' * 10
display as result "  Assertion passed: `n_resp' respondents x 5 tasks x 2 profiles."

isid uid task profile

*------------------------------------------------------------------------------*
* 3. Outcome indicators
*
* cj_coop and cj_elect hold the chosen profile as "a" or "b" (from the
* conjoint_ab choice list, where a = Mukhiya 1 and b = Mukhiya 2). The chosen
* indicator is 1 on the row whose profile matches.
*
* DIRECTION CHECK, and it matters: if the comparison were inverted, every AMCE
* would flip sign and the results would look coherent while being backwards.
* The assertions below confirm that exactly one profile per task is chosen.
*------------------------------------------------------------------------------*
gen byte chosen_coop  = (trim(lower(cj_coop))  == trim(lower(profile))) ///
                        if !missing(cj_coop)
gen byte chosen_elect = (trim(lower(cj_elect)) == trim(lower(profile))) ///
                        if !missing(cj_elect)

label var chosen_coop  "Chosen as easier to cooperate with (PRIMARY outcome)"
label var chosen_elect "Preferred as mukhiya of own GP (SECONDARY outcome)"
label define chosen_lbl 0 "Not chosen" 1 "Chosen", replace
label values chosen_coop chosen_lbl
label values chosen_elect chosen_lbl

* Exactly one of the two profiles must be chosen in each task. A task summing
* to 0 or 2 means the indicator is misconstructed, not that the respondent was
* indecisive: the form used a select_one, so a valid answer is always exactly
* one profile.
bysort taskid: egen byte _sum_coop  = total(chosen_coop)
bysort taskid: egen byte _sum_elect = total(chosen_elect)

quietly count if _sum_coop != 1 & !missing(cj_coop)
if r(N) > 0 {
    display as error "`r(N)' profile rows sit in a task where chosen_coop does"
    display as error "not sum to 1. The outcome indicator is misconstructed."
    display as error "Check the case and values of cj_coop against 'profile'."
    list uid task profile cj_coop chosen_coop if _sum_coop != 1, clean noobs
    exit 459
}
quietly count if _sum_elect != 1 & !missing(cj_elect)
if r(N) > 0 {
    display as error "`r(N)' profile rows sit in a task where chosen_elect does"
    display as error "not sum to 1."
    exit 459
}
drop _sum_coop _sum_elect
display as result "  Outcome indicators verified: exactly one profile chosen per task."

*------------------------------------------------------------------------------*
* 4. Attribute variables: factors and dummies
*
* Both forms are created. Factors are used with i. notation in the regressions
* and with margins; the explicit dummies are used where an interaction needs to
* be written out and read unambiguously.
*------------------------------------------------------------------------------*

*--- caste ---*
gen byte caste_n = .
replace  caste_n = 1 if trim(lower(cj_caste)) == "sc"
replace  caste_n = 2 if trim(lower(cj_caste)) == "yadav"
replace  caste_n = 3 if trim(lower(cj_caste)) == "rajput"
label define caste3 1 "Scheduled Caste" 2 "Yadav" 3 "Rajput", replace
label values caste_n caste3
label var caste_n "Profile caste (randomised)"

gen byte p_sc     = (caste_n == 1) if !missing(caste_n)
gen byte p_yadav  = (caste_n == 2) if !missing(caste_n)
gen byte p_rajput = (caste_n == 3) if !missing(caste_n)
label var p_sc     "Profile is Scheduled Caste"
label var p_yadav  "Profile is Yadav"
label var p_rajput "Profile is Rajput"

*--- authority style: THE experimental manipulation of independence ---*
gen byte auth_n = .
replace  auth_n = 0 if trim(lower(cj_auth)) == "follows_elders"
replace  auth_n = 1 if trim(lower(cj_auth)) == "independent"
label define auth2 0 "Follows established elders" 1 "Takes decisions independently", replace
label values auth_n auth2
label var auth_n "Profile authority style (randomised): 1 = independent"

clonevar p_indep = auth_n
label var p_indep "Profile acts independently"

*--- economic status ---*
gen byte econ_n = .
replace  econ_n = 0 if trim(lower(cj_econ)) == "poor_landless"
replace  econ_n = 1 if trim(lower(cj_econ)) == "welloff_landowning"
label define econ2 0 "Poor and landless" 1 "Well-off and landowning", replace
label values econ_n econ2
label var econ_n "Profile economic status (randomised)"
clonevar p_welloff = econ_n
label var p_welloff "Profile is well-off and landowning"

*--- education ---*
gen byte educ_n = .
replace  educ_n = 0 if trim(lower(cj_educ)) == "little_education"
replace  educ_n = 1 if trim(lower(cj_educ)) == "well_educated"
label define peduc2 0 "Little education" 1 "Well educated", replace
label values educ_n peduc2
label var educ_n "Profile education (randomised)"
clonevar p_educated = educ_n
label var p_educated "Profile is well educated"

* verify no attribute failed to parse
foreach v in caste_n auth_n econ_n educ_n {
    quietly count if missing(`v')
    if r(N) > 0 {
        display as error "`v' is missing on `r(N)' rows: an attribute value did"
        display as error "not match the expected strings. Inspect:"
        tab cj_caste cj_auth if missing(`v')
        exit 459
    }
}
display as result "  All four attributes parsed on every row."

*--- the central interaction term, created explicitly so it can be inspected ---*
gen byte sc_x_indep = p_sc * p_indep
label var sc_x_indep "SC x acts independently (the central interaction)"

*--- profile position, to test for a left-right or first-second order effect ---*
gen byte prof_b = (trim(lower(profile)) == "b")
label var prof_b "Profile presented second (Mukhiya 2)"

*--- flip-guard indicator, carried to the profile level ---*
label var cj_flip "Flip guard fired in this task (profiles were identical)"

*------------------------------------------------------------------------------*
* 5. Save
*------------------------------------------------------------------------------*
order uid task profile taskid caste_n auth_n econ_n educ_n ///
      chosen_coop chosen_elect
sort uid task profile

compress
save "$clean/conjoint_long.dta", replace
display as result "Saved: $clean/conjoint_long.dta  (`n_prof' profile rows)"


*==============================================================================*
* SECTION 6. RANDOMISATION DIAGNOSTICS
*
* Two distinct questions:
*   (a) Did the attributes realise at their intended marginal probabilities?
*   (b) Are the attributes independent of each other and of respondent
*       characteristics?
*
* (b) is the one that matters for identification. If an attribute correlates
* with a respondent characteristic, the randomisation failed and the AMCEs are
* not clean. (a) is a weaker check: a modest departure from intended marginals
* is sampling variation, not a failure.
*==============================================================================*
capture log close randlog
log using "$out/tab_conjoint_randomisation.txt", replace text name(randlog)

display _n "=================================================================="
display    " CONJOINT RANDOMISATION DIAGNOSTICS"
display    ""
display    " DESIGN FEATURES TO DISCLOSE IN THE METHODOLOGY CHAPTER"
display    ""
display    " 1. UNEQUAL CASTE PROBABILITIES. The form drew caste as"
display    "    P(sc)=0.50, P(yadav)=0.25, P(rajput)=0.25. AMCEs remain"
display    "    unbiased because the probabilities are known and independent of"
display    "    the outcome, but PRECISION DIFFERS ACROSS LEVELS: the SC"
display    "    estimate is more precise, Yadav and Rajput less so. Note also"
display    "    that AMCEs are defined with respect to the realised"
display    "    distribution of the OTHER attributes, which is what makes the"
display    "    reference-category choice consequential."
display    ""
display    " 2. THE FLIP GUARD. When all four attributes matched between the two"
display    "    profiles, caste_B was deterministically reassigned by a"
display    "    three-way cycle (sc->yadav->rajput->sc). Under the deployed"
display    "    design this fires with probability 0.375 x 0.5^3 = approximately"
display    "    4.7%, roughly 35 of 750 tasks. IN THOSE TASKS CASTE IS NOT"
display    "    INDEPENDENTLY RANDOMISED ACROSS PROFILES. This is a small but"
display    "    real departure from full independence. Disclose it, and see the"
display    "    robustness check in 08_conjoint_amce.do that excludes"
display    "    flip-guard tasks."
display    "=================================================================="

use "$clean/conjoint_long.dta", clear

*------------------------------------------------------------------------------*
* 6.1 Realised marginal distributions
*------------------------------------------------------------------------------*
display _n "--- 6.1 Realised attribute marginals (all profile rows) ---"
display "Intended: caste 0.50 / 0.25 / 0.25; the other three 0.50 / 0.50."
tab caste_n
tab auth_n
tab econ_n
tab educ_n

display _n "--- Realised marginals BY PROFILE POSITION ---"
display "Profile B should depart slightly from the intended caste marginals"
display "because the flip guard only ever modifies profile B."
tab caste_n profile, col
tab auth_n  profile, col
tab econ_n  profile, col
tab educ_n  profile, col

display _n "--- Realised marginals by task, to check the once() calls held ---"
tab caste_n task, col
tab auth_n  task, col

*------------------------------------------------------------------------------*
* 6.2 Attribute independence: the check that matters for identification
*------------------------------------------------------------------------------*
display _n "--- 6.2 Are the attributes independent of each other? ---"
display "Chi-squared tests of pairwise independence. These SHOULD be"
display "insignificant. A significant result would mean the randomisation"
display "produced correlated attributes, which would confound the AMCEs."
tab caste_n auth_n, chi2 nofreq row
tab caste_n econ_n, chi2 nofreq row
tab caste_n educ_n, chi2 nofreq row
tab auth_n  econ_n, chi2 nofreq row
tab auth_n  educ_n, chi2 nofreq row
tab econ_n  educ_n, chi2 nofreq row

display _n "Restricted to profile A only, where no flip guard operates:"
tab caste_n auth_n if profile == "a", chi2 nofreq row

*------------------------------------------------------------------------------*
* 6.3 Attribute balance on respondent characteristics
*
* Since attributes were randomised WITHIN respondent by the form, they should be
* unrelated to any respondent characteristic. A significant relationship would
* indicate a form-logic problem (for example a once() call not firing, so an
* attribute is constant within respondent and therefore correlated with
* everything about that respondent).
*------------------------------------------------------------------------------*
display _n "--- 6.3 Are attributes balanced on respondent characteristics? ---"
display "All of these SHOULD be null."

foreach x in prej_pc1 educ_ord auth_idx caste_cat_n mukh_sex_n gp_scshare_ord {
    capture confirm variable `x'
    if _rc continue
    display _n "  Respondent characteristic: `x'"
    quietly regress p_sc `x', vce(cluster uid)
    quietly test `x'
    display "    P(profile is SC)          b = " %7.4f _b[`x'] "  p = " %6.4f r(p)
    quietly regress p_indep `x', vce(cluster uid)
    quietly test `x'
    display "    P(profile is independent) b = " %7.4f _b[`x'] "  p = " %6.4f r(p)
}

*------------------------------------------------------------------------------*
* 6.4 Flip-guard incidence
*------------------------------------------------------------------------------*
display _n "--- 6.4 Flip-guard firing rate ---"
display "Design expectation: approximately 4.7% of tasks."
preserve
    * one row per task for the correct denominator
    bysort taskid: keep if _n == 1
    quietly count
    local ntasks = r(N)
    quietly count if cj_flip == 1
    local nfired = r(N)
    display as result "  `nfired' of `ntasks' tasks = " ///
        %5.2f 100*`nfired'/`ntasks' "%"
    display _n "  By task number:"
    tab task cj_flip, row
restore

display _n "Caste combinations in tasks where the guard fired:"
display "The cycle sc->yadav->rajput->sc means the guard never leaves the two"
display "profiles with the same caste, so these tasks are caste-discordant by"
display "construction. That is precisely why they are not independently"
display "randomised."
tab cj_caste profile if cj_flip == 1

*------------------------------------------------------------------------------*
* 6.5 Outcome distribution and profile-position effect
*------------------------------------------------------------------------------*
display _n "--- 6.5 Outcome distributions ---"
summarize chosen_coop chosen_elect

display _n "Profile-position effect: is the second-presented profile chosen"
display "more or less often? A large asymmetry would indicate an order effect,"
display "which the AMCE specification should then control for."
tab prof_b chosen_coop, row
quietly regress chosen_coop prof_b, vce(cluster uid)
quietly test prof_b
display as result "  Coefficient on 'presented second' = " %7.4f _b[prof_b] ///
    "   p = " %6.4f r(p)
display "  If this is substantial, include prof_b as a control in the AMCE"
display "  specification (08_conjoint_amce.do runs that as a robustness column)."

display _n "--- Correlation between the two outcomes ---"
display "They are measured on the SAME randomised profiles, so agreement"
display "between them is genuine convergent evidence rather than an independent"
display "replication. Report the correlation and treat them as two facets of"
display "one measurement exercise, not two tests."
correlate chosen_coop chosen_elect

display _n "Cross-tabulation:"
tab chosen_coop chosen_elect, row

log close randlog

display as result _n "=== 07_conjoint_reshape.do complete ==="
display as txt "Long data:      $clean/conjoint_long.dta"
display as txt "Diagnostics:    $out/tab_conjoint_randomisation.txt"

*==============================================================================*
* END 07_conjoint_reshape.do
*==============================================================================*

*==============================================================================*
* 02_clean_recode.do
*
* PURPOSE : Recode variables.
*
* INPUT   : $clean/sc_merged.dta, $clean/nonsc_merged.dta
* OUTPUT  : $clean/sc_recoded.dta, $clean/nonsc_recoded.dta
*           $out/qc_recode_check_*.txt  (verification cross-tabs)
*==============================================================================*

*==============================================================================*
* HELPER PROGRAMME: convert a Kobo string select_one into a numeric variable
*==============================================================================*
capture program drop pnsbinary
program define pnsbinary
    * Converts a yes/no/prefer_not string variable into:
    *   <stub>      byte 1=yes 0=no, prefer_not -> missing (or 0 if $pns_to_missing==0)
    *   <stub>_pns  byte 1 if the respondent refused this item

    syntax varlist(min=1)
    foreach v of local varlist {

        * refusal flag first, before any information is destroyed
        capture confirm string variable `v'
        if !_rc {
            gen byte `v'_pns = (trim(lower(`v')) == "prefer_not") if !missing(`v')
            gen byte `v'_b   = .
            replace  `v'_b   = 1 if trim(lower(`v')) == "yes"
            replace  `v'_b   = 0 if trim(lower(`v')) == "no"
        }
        else {
            gen byte `v'_pns = 0
            gen byte `v'_b   = (`v' == 1) if inlist(`v', 0, 1)
        }

        * optional non-recommended treatment: refusal counted as "no"
        if $pns_to_missing == 0 replace `v'_b = 0 if `v'_pns == 1

        local lab : variable label `v'
        label var `v'_b   "`lab'"
        label var `v'_pns "Refused (prefer not to say): `lab'"
        label values `v'_b yesno_lbl
    }
end

capture program drop pnslikert
program define pnslikert
    * Converts a 1-5 Likert variable that also carries "prefer_not" into:
    *   <stub>_n    byte 1..5, prefer_not -> missing
    *   <stub>_pns  byte 1 if refused
	
    syntax varlist(min=1)
    foreach v of local varlist {
		
        capture confirm string variable `v'
        if !_rc {
            gen byte `v'_pns = (trim(lower(`v')) == "prefer_not") if !missing(`v')
            gen byte `v'_n   = real(`v')          // real() returns . for "prefer_not"
        }
        else {
            gen byte `v'_pns = 0
            gen byte `v'_n   = `v'
        }
		
        local lab : variable label `v'
        label var `v'_n   "`lab'"
        label var `v'_pns "Refused (prefer not to say): `lab'"
        label values `v'_n likert5
    }
end


*==============================================================================*
* PART A. SC SURVEY
*==============================================================================*
use "$clean/sc_merged.dta", clear

*------------------------------------------------------------------------------*
* A0. Value label definitions
*------------------------------------------------------------------------------*
label define yesno_lbl   0 "No" 1 "Yes", replace
label define likert5     1 "Strongly disagree" 2 "Disagree" 3 "Neutral" ///
                         4 "Agree" 5 "Strongly agree", replace
label define freq4       1 "Rarely" 2 "Sometimes" 3 "Often" 4 "Very often", replace
label define authlvl     0 "Displaced to another actor" 1 "Self with assistance" ///
                         2 "Self-executed", replace
label define finaldec    1 "Others decide entirely" 2 "Others decide, I formalise" ///
                         3 "Jointly with deputy or others" ///
                         4 "I do, after consulting" 5 "I do, independently", replace
label define edu6        1 "No formal schooling" 2 "Primary" 3 "Middle" ///
                         4 "Secondary (10th)" 5 "Higher secondary (12th)" ///
                         6 "Graduate or above", replace
label define scshare4    1 "Less than 10%" 2 "10-15%" 3 "15-20%" ///
                         4 "More than 20%", replace
label define worse5      1 "Lot better" 2 "Better" 3 "The same" ///
                         4 "Somewhat worse" 5 "Much worse", replace
label define severe5     1 "None" 2 "Mild" 3 "Moderate" 4 "Severe" ///
                         5 "Very severe", replace
label define common4     1 "Never" 2 "Rare" 3 "Somewhat common" 4 "Very common", replace
label define wb5         1 "Never" 2 "Rarely" 3 "Some of the time" ///
                         4 "Most of the time" 5 "All of the time", replace
label define qual4       1 "Poorly" 2 "Somewhat" 3 "Mostly" 4 "Fully", replace
label define sinc4       1 "Doubtful" 2 "Somewhat" 3 "Mostly" 4 "Fully sincere", replace
label define sex2        1 "Male" 2 "Female", replace
label define party3      1 "No, independent" 2 "Yes, informally" 3 "Yes, formally", replace

*------------------------------------------------------------------------------*
* A1. Sample eligibility: consent and duplicate-ID verification
*------------------------------------------------------------------------------*
* consent is a yes/no string
gen byte consent_b = (trim(lower(consent)) == "yes")
label var consent_b "Consented to interview"
label values consent_b yesno_lbl

display as txt _n "=== SC: consent ==="
tab consent_b, missing

count if consent_b == 0
local n_noconsent = r(N)
display as result "SC non-consenting records dropped: `n_noconsent'"
drop if consent_b == 0

* uid_check is the in-form re-entry of uid. The form enforces equality by
* constraint, so avoid enumerator error while entering uid.
capture confirm variable uid_check
if !_rc {
    capture confirm numeric variable uid_check
    if _rc destring uid_check, replace force
    count if uid != uid_check & !missing(uid_check)
    if r(N) > 0 {
        display as error "`r(N)' records have uid != uid_check. Reconcile before use."
        list uid uid_check if uid != uid_check & !missing(uid_check), clean noobs
    }
    else display as txt "uid verification passed."
    drop uid_check
}

* uid must be unique in the analysis file
duplicates report uid
duplicates tag uid, gen(_dupuid)
count if _dupuid > 0
if r(N) > 0 {
    display as error "`r(N)' duplicate uid records in the SC survey. Inspect."
    list uid mukhiya_name survey_date if _dupuid > 0, clean noobs
}
drop _dupuid

* Every record in this file should be an SC mukhiya
display as txt _n "=== SC sample purity: caste_category should be 'sc' throughout ==="
tab caste_category, missing
count if trim(caste_category) != "sc"
if r(N) > 0 {
    display as error "`r(N)' records in the SC file are not caste_category=='sc'."
    display as error "Investigate: frame error, misrouted call, or respondent correction."
    * NOT dropped automatically. This is a substantive decision for you.
    gen byte sc_purity_flag = (trim(caste_category) != "sc")
    label var sc_purity_flag "Record in SC file with caste_category != Scheduled Caste"
}

*------------------------------------------------------------------------------*
* A2. Proxy respondents
* resp_type == "on_behalf" means someone other than the elected mukhiya answered.
*------------------------------------------------------------------------------*
gen byte proxy_resp = (trim(lower(resp_type)) == "on_behalf")
label var proxy_resp "Someone other than the mukhiya answered the survey"
label values proxy_resp yesno_lbl

gen byte self_resp = 1 - proxy_resp
label var self_resp "The elected mukhiya answered in person"

display as txt _n "=== SC: proxy respondents, and by gender of the mukhiya ==="
tab proxy_resp, missing
capture tab proxy_rel proxy_resp
capture tab mukhiya_gender proxy_resp, row

*------------------------------------------------------------------------------*
* A3. Module A demographics
*------------------------------------------------------------------------------*
* gender: numeric with labels
gen byte mukh_sex_n = .
replace  mukh_sex_n = 1 if trim(lower(mukhiya_gender)) == "male"
replace  mukh_sex_n = 2 if trim(lower(mukhiya_gender)) == "female"
label var mukh_sex_n "Gender of the elected mukhiya"
label values mukh_sex_n sex2

* education: ordinal 1-6 following the instrument's own ordering
gen byte educ_ord = .
replace  educ_ord = 1 if trim(lower(educ)) == "none"
replace  educ_ord = 2 if trim(lower(educ)) == "primary"
replace  educ_ord = 3 if trim(lower(educ)) == "middle"
replace  educ_ord = 4 if trim(lower(educ)) == "secondary"
replace  educ_ord = 5 if trim(lower(educ)) == "higher_sec"
replace  educ_ord = 6 if trim(lower(educ)) == "graduate"
label var educ_ord "Education (ordinal 1-6)"
label values educ_ord edu6

* binary "secondary or above", which is the more legible form for prose
gen byte educ_sec = (educ_ord >= 4) if !missing(educ_ord)
label var educ_sec "Completed secondary (10th) or above"
label values educ_sec yesno_lbl

* SC population share: ordinal, with "not sure" to missing and its own flag.
* "not_sure" is set missing because it carries no ordinal information, but the
* rate is reported because it indicates how well mukhiyas know their own
* panchayat's composition, which is substantively interesting.
gen byte gp_scshare_ord = .
replace  gp_scshare_ord = 1 if trim(lower(sc_pop_share)) == "lt10"
replace  gp_scshare_ord = 2 if trim(lower(sc_pop_share)) == "b10_15"
replace  gp_scshare_ord = 3 if trim(lower(sc_pop_share)) == "b15_20"
replace  gp_scshare_ord = 4 if trim(lower(sc_pop_share)) == "gt20"
label var gp_scshare_ord "SC share of panchayat population (ordinal 1-4)"
label values gp_scshare_ord scshare4

gen byte gp_scshare_ns = (trim(lower(sc_pop_share)) == "not_sure")
label var gp_scshare_ns "Did not know the panchayat's SC share"

* income source as numeric factors
gen byte income_n = .
replace  income_n = 1 if trim(lower(income)) == "agri_labour"
replace  income_n = 2 if trim(lower(income)) == "own_cult"
replace  income_n = 3 if trim(lower(income)) == "small_business"
replace  income_n = 4 if trim(lower(income)) == "salaried"
replace  income_n = 5 if trim(lower(income)) == "govt_scheme"
replace  income_n = 6 if trim(lower(income)) == "other"
label var income_n "Main household income source"
label define income6 1 "Agricultural labour" 2 "Own cultivation" ///
                     3 "Small business" 4 "Salaried job" ///
                     5 "Government scheme work" 6 "Other", replace
label values income_n income6

* party support: ordered from independent to formal party backing
gen byte party_n = .
replace  party_n = 1 if trim(lower(party_support)) == "independent"
replace  party_n = 2 if trim(lower(party_support)) == "yes_informal"
replace  party_n = 3 if trim(lower(party_support)) == "yes_formal"
label var party_n "Party or leader support when contesting"
label values party_n party3

gen byte gp_mainvill_n = (trim(lower(gp_mainvill)) == "yes")
label var gp_mainvill_n "Belongs to the main village of the panchayat"
label values gp_mainvill_n yesno_lbl

* panchayat population: log for the regressions
capture confirm numeric variable gp_pop
if _rc destring gp_pop, replace force
summarize gp_pop, detail
gen double ln_gp_pop = ln(gp_pop) if gp_pop > 0 & !missing(gp_pop)
label var ln_gp_pop "Log of panchayat population"
count if missing(ln_gp_pop) & !missing(gp_pop)
if r(N) > 0 display as error "`r(N)' records have gp_pop <= 0. Inspect."

capture confirm numeric variable revenue_villages
if _rc destring revenue_villages, replace force
capture confirm numeric variable n_terms
if _rc destring n_terms, replace force
capture confirm numeric variable n_stood
if _rc destring n_stood, replace force

* logical consistency: cannot have served more terms than times stood
count if n_terms > n_stood & !missing(n_terms, n_stood)
if r(N) > 0 {
    display as error "`r(N)' records report more terms served than times stood."
    list uid n_stood n_terms if n_terms > n_stood, clean noobs
}

* family political background: any prior family office
* fam_none is the "No one" dummy from the select_multiple expansion, so
* fam_any is its complement. Built from the dummy rather than parsing the
* combined string, which is more robust to export formatting.
capture confirm variable fam_office_noone
if !_rc {
    gen byte fam_any = 1 - fam_office_noone
}
else {
    * fallback: parse the combined select_multiple string
    gen byte fam_any = (!regexm(trim(lower(fam_office)), "no_one")) ///
                       if !missing(fam_office)
}
label var fam_any "Any family member held a panchayat position before"
label values fam_any yesno_lbl

*------------------------------------------------------------------------------*
* A4. Module B: entry pathway and pressure (SC only)
*------------------------------------------------------------------------------*
pnsbinary withdraw_asked bribe_offer elec_threat

* Elite-sponsored entry: encouraged by an upper-caste leader or the former mukhiya's circle
capture confirm variable entry_idea_uclead
if !_rc {
    gen byte entry_elite = (entry_idea_uclead == 1 | entry_idea_exmukh == 1)
    label var entry_elite "Encouraged to contest by an upper-caste leader or ex-mukhiya"
    label values entry_elite yesno_lbl
}

*------------------------------------------------------------------------------*
* A5. De facto authority: the behavioural core of "independence"
*
* Three-level ordinal coding of each of the seven task items, NOT a binary.
* "I do it with help from family" is analytically distinct from "the former
* mukhiya does it", and collapsing them would discard the distinction the
* dissertation exists to make.
*
*   2 = self-executed   : self
*   1 = assisted        : self_family_help, family_member_for_me
*   0 = displaced       : secretary, former_mukhiya, up_mukhiya, someone_else
*
* The displaced category is separately decomposed in 05_desc_sc.do, because
* WHO does the work when the mukhiya does not is a finding in its own right.
*------------------------------------------------------------------------------*
foreach v of global AUTHTASKS {
    gen byte `v'_ord = .
    replace  `v'_ord = 2 if trim(lower(`v')) == "self"
    replace  `v'_ord = 1 if inlist(trim(lower(`v')), "self_family_help", ///
                                   "family_member_for_me")
    replace  `v'_ord = 0 if inlist(trim(lower(`v')), "secretary", "former_mukhiya", ///
                                   "up_mukhiya", "someone_else")
    local lab : variable label `v'
    label var `v'_ord "`lab' (0 displaced / 1 assisted / 2 self)"
    label values `v'_ord authlvl

    * binary self-executed, for the task-count measure
    gen byte `v'_self = (`v'_ord == 2) if !missing(`v'_ord)
    label var `v'_self "Self-executes: `lab'"
    label values `v'_self yesno_lbl

    * displacement actor, retained for the composition analysis
    gen str20 `v'_who = trim(lower(`v'))
}

* final decision authority, coded so that HIGHER = MORE INDEPENDENT.
* The instrument lists options from most to least independent, so a naive
* ascending numeric coding would run backwards. This is the reversal the
* analysis plan refers to for final_decision.
gen byte auth_final_ord = .
replace  auth_final_ord = 5 if trim(lower(auth_final)) == "independent"
replace  auth_final_ord = 4 if trim(lower(auth_final)) == "after_consult"
replace  auth_final_ord = 3 if trim(lower(auth_final)) == "jointly"
replace  auth_final_ord = 2 if trim(lower(auth_final)) == "others_formalise"
replace  auth_final_ord = 1 if trim(lower(auth_final)) == "others_entirely"
label var auth_final_ord "Final decision authority (5 = fully independent)"
label values auth_final_ord finaldec

* self-described proxy: the two lowest categories are respondents describing
* proxy status in their own words. This is the direct quantitative counterpart
* to the interview claim about how few reserved mukhiyas decide independently.
gen byte auth_proxy_self = (auth_final_ord <= 2) if !missing(auth_final_ord)
label var auth_proxy_self "Reports others decide (formalise or entirely)"
label values auth_proxy_self yesno_lbl

* enumerator's independent judgement, used to validate the self-report
gen byte q_indep_b = .
replace  q_indep_b = 1 if trim(lower(q_indep)) == "yes"
replace  q_indep_b = 0 if trim(lower(q_indep)) == "no"
label var q_indep_b "Enumerator judged respondent independently acting"
label values q_indep_b yesno_lbl
gen byte q_indep_cant = (trim(lower(q_indep)) == "cant_say")
label var q_indep_cant "Enumerator could not say whether independently acting"

*------------------------------------------------------------------------------*
* A6. Self-efficacy: likert_agree, 1-5
*------------------------------------------------------------------------------*
foreach v of global EFF {
    capture confirm numeric variable `v'
    if _rc {
        gen byte `v'_n = real(`v')
    }
    else {
        gen byte `v'_n = `v'
    }
    local lab : variable label `v'
    label var `v'_n "`lab'"
    label values `v'_n likert5
}

*------------------------------------------------------------------------------*
* A7. Rights and functional knowledge
*------------------------------------------------------------------------------*

*--- claimed awareness (2 items) ---*
foreach v in kn_gramsabha kn_gpdp {
    gen byte `v'_claim = (trim(lower(`v')) == "yes")
    gen byte `v'_ns    = (trim(lower(`v')) == "not_sure")
    local lab : variable label `v'
    label var `v'_claim "Claims to know: `lab'"
    label var `v'_ns    "Answered not sure: `lab'"
    label values `v'_claim yesno_lbl
}

*--- demonstrated knowledge (4 items) ---*
gen byte kn_15fc_c = (trim(lower(kn_15fc)) == "$kn_15fc_correct") ///
                     if !missing(kn_15fc)
gen byte kn_15fc_ns = (trim(lower(kn_15fc)) == "not_sure")

gen byte kn_cert_c = (trim(lower(kn_cert)) == "$kn_cert_correct") ///
                     if !missing(kn_cert)
gen byte kn_cert_ns = (trim(lower(kn_cert)) == "not_sure")

gen byte kn_pmayg_c = (trim(lower(kn_pmayg)) == "$kn_pmayg_correct") ///
                      if !missing(kn_pmayg)
gen byte kn_pmayg_ns = (trim(lower(kn_pmayg)) == "not_sure")

* kn_commit is an integer response, not a select_one, and it was not required
* in the form, so missingness here is meaningful (declined or unaware).
capture confirm numeric variable kn_commit
if _rc destring kn_commit, replace force
gen byte kn_commit_c = ///
    (abs(kn_commit - $kn_commit_correct) <= $kn_commit_tol) if !missing(kn_commit)
gen byte kn_commit_ns = missing(kn_commit)

foreach v in kn_15fc kn_cert kn_pmayg kn_commit {
    local lab : variable label `v'
    label var `v'_c  "Answered correctly: `lab'"
    label var `v'_ns "Not sure or no answer: `lab'"
    label values `v'_c yesno_lbl
}

*------------------------------------------------------------------------------*
* A8. Microaggression exposure: yesnopns items and frequency follow-ups
*------------------------------------------------------------------------------*
pnsbinary $MA_INSULT $MA_INVAL $MA_ASSAULT ma_slur

* frequency items: freq_opts, 1-4 (higher = more frequent)
foreach v of varlist ma_*_f {
    capture confirm numeric variable `v'
    if _rc {
        gen byte `v'_n = real(`v')
    }
    else {
        gen byte `v'_n = `v'
    }
    local lab : variable label `v'
    label var `v'_n "`lab'"
    label values `v'_n freq4
}

* ma_common scores need to be reversed
gen byte ma_common_r = 5 - ma_common
label var ma_common_r "Perceived prevalence among SC mukhiyas (4 = very common)"
label values ma_common_r common4

* Assigning ma_slur correctly to microassault
if $slur_as_assault == 1 {
    global MA_INVAL_F   "ma_bypass_b ma_ignored_b ma_wait_b"
    global MA_ASSAULT_F "ma_food_b ma_slur_b"
    display as txt "ma_slur assigned to MICROASSAULT index (taxonomy-consistent)."
}
else {
    global MA_INVAL_F   "ma_bypass_b ma_ignored_b ma_wait_b ma_slur_b"
    global MA_ASSAULT_F "ma_food_b "
    display as txt "ma_slur retained in MICROINVALIDATION index (instrument layout)."
}
global MA_INSULT_F "ma_surprise_b ma_reserv_b ma_capacity_b ma_finance_b ma_flag_b"

*------------------------------------------------------------------------------*
* A9. Backlash exposure
*------------------------------------------------------------------------------*
pnsbinary $BL_BUREAU $BL_INTERN $BL_COMMUN $BL_SYMBOL $BL_VIOLENT

foreach v of varlist bl_*_f {
    capture confirm numeric variable `v'
    if _rc {
        gen byte `v'_n = real(`v')
    }
    else {
        gen byte `v'_n = `v'
    }
    local lab : variable label `v'
    label var `v'_n "`lab'"
    label values `v'_n freq4
}

* bl_compare (e1_comparison): treat_compare runs 1 = Much worse to 5 = Lot
* better, so higher raw = BETTER treatment. REVERSED so that higher expresses
* relative DISADVANTAGE.
gen byte bl_compare_r = 6 - bl_compare
label var bl_compare_r "Treated worse than upper-caste mukhiyas (5 = much worse)"
label values bl_compare_r worse5

* headline binary: reports worse treatment than upper-caste mukhiyas
gen byte bl_worse = (bl_compare_r >= 4) if !missing(bl_compare_r)
label var bl_worse "Reports worse treatment than upper-caste mukhiyas"
label values bl_worse yesno_lbl

* bl_severity (e6_severity): severity_opts runs 1 = Very severe to 5 = None,
* so higher raw = LESS severe. REVERSED so that higher = more severe.
gen byte bl_severity_r = 6 - bl_severity
label var bl_severity_r "Overall severity of caste-related difficulties (5 = very severe)"
label values bl_severity_r severe5

*------------------------------------------------------------------------------*
* A10. Victim-blaming exposure
*------------------------------------------------------------------------------*
pnsbinary $VB

*------------------------------------------------------------------------------*
* A11. Wellbeing: modified five-point scale, NOT the validated WHO-5
*------------------------------------------------------------------------------*
foreach v of global WB {
    capture confirm numeric variable `v'
    if _rc {
        gen byte `v'_n = real(`v')
    }
    else {
        gen byte `v'_n = `v'
    }
    local lab : variable label `v'
    label var `v'_n "`lab'"
    label values `v'_n wb5
}

* Recompute the sum rather than trusting the form's calculate field
egen byte wb_sum_chk = rowtotal(wb_cheer_n wb_calm_n wb_active_n wb_rested_n ///
                                wb_interest_n), missing
label var wb_sum_chk "Wellbeing raw sum, recomputed (5-25)"

capture confirm variable wb_sum
if !_rc {
    capture confirm numeric variable wb_sum
    if _rc destring wb_sum, replace force
    count if wb_sum != wb_sum_chk & !missing(wb_sum, wb_sum_chk)
    if r(N) > 0 {
        display as error "`r(N)' records: form wb_sum differs from recomputed sum."
        display as error "Use wb_sum_chk and investigate the form calculation."
    }
}

* NOT applying the WHO-5 x4 transformation, deliberately. Recording the
* rescaled version only to make the non-comparability explicit if quoted.
gen double wb_scaled = wb_sum_chk * 4
label var wb_scaled "Wellbeing x4 (range 20-100; NOT WHO-5 comparable)"

*------------------------------------------------------------------------------*
* A12. Interview quality (enumerator assessment)
*------------------------------------------------------------------------------*
gen byte q_underst_r = 5 - q_underst
label var q_underst_r "Respondent understanding (4 = fully)"
label values q_underst_r qual4

gen byte q_sincere_r = 5 - q_sincere
label var q_sincere_r "Respondent sincerity (4 = fully sincere)"
label values q_sincere_r sinc4

gen byte lowqual = (q_underst_r < $qual_min | q_sincere_r < $qual_min) ///
                   if !missing(q_underst_r, q_sincere_r)
label var lowqual "Interview flagged low quality by enumerator"
label values lowqual yesno_lbl

*------------------------------------------------------------------------------*
* A13. Interview duration
*------------------------------------------------------------------------------*
capture confirm string variable start_time
if !_rc {
    gen double start_dt = clock(subinstr(start_time, "T", " ", 1), "YMDhms#")
    gen double end_dt   = clock(subinstr(end_time,   "T", " ", 1), "YMDhms#")
    format start_dt end_dt %tc
    gen double dur_min = (end_dt - start_dt) / 60000     // ms -> minutes
    label var dur_min "Interview duration in minutes (end - start)"

    count if missing(dur_min)
    if r(N) > 0 display as error ///
        "`r(N)' records: timestamp parse failed. Check the clock() mask in A13."
}

*------------------------------------------------------------------------------*
* A14. Save
*------------------------------------------------------------------------------*
compress
save "$clean/sc_recoded.dta", replace
display as result "Saved: $clean/sc_recoded.dta"


*==============================================================================*
* PART B. NON-SC SURVEY
*==============================================================================*
use "$clean/nonsc_merged.dta", clear

* re-declare value labels in this dataset
label define yesno_lbl   0 "No" 1 "Yes", replace
label define likert5     1 "Strongly disagree" 2 "Disagree" 3 "Neutral" ///
                         4 "Agree" 5 "Strongly agree", replace
label define authlvl     0 "Displaced to another actor" 1 "Self with assistance" ///
                         2 "Self-executed", replace
label define finaldec    1 "Others decide entirely" 2 "Others decide, I formalise" ///
                         3 "Jointly with deputy or others" ///
                         4 "I do, after consulting" 5 "I do, independently", replace
label define edu6        1 "No formal schooling" 2 "Primary" 3 "Middle" ///
                         4 "Secondary (10th)" 5 "Higher secondary (12th)" ///
                         6 "Graduate or above", replace
label define scshare4    1 "Less than 10%" 2 "10-15%" 3 "15-20%" ///
                         4 "More than 20%", replace
label define wb5         1 "Never" 2 "Rarely" 3 "Some of the time" ///
                         4 "Most of the time" 5 "All of the time", replace
label define qual4       1 "Poorly" 2 "Somewhat" 3 "Mostly" 4 "Fully", replace
label define sinc4       1 "Doubtful" 2 "Somewhat" 3 "Mostly" 4 "Fully sincere", replace
label define conj3       1 "Major difficulty" 2 "Some difficulty" 3 "Understood well", replace
label define sex2        1 "Male" 2 "Female", replace
label define party3      1 "No, independent" 2 "Yes, informally" 3 "Yes, formally", replace
label define income6     1 "Agricultural labour" 2 "Own cultivation" ///
                         3 "Small business" 4 "Salaried job" ///
                         5 "Government scheme work" 6 "Other", replace
label define castecat6   1 "General" 2 "BC-1 (EBC)" 3 "BC-2 (BC)" ///
                         4 "Scheduled Caste" 5 "Scheduled Tribe" 6 "Other", replace

*------------------------------------------------------------------------------*
* B1. Sample eligibility
*------------------------------------------------------------------------------*
gen byte consent_b = (trim(lower(consent)) == "yes")
label var consent_b "Consented to interview"
label values consent_b yesno_lbl

display as txt _n "=== Non-SC: consent ==="
tab consent_b, missing
count if consent_b == 0
display as result "Non-SC non-consenting records dropped: `r(N)'"
drop if consent_b == 0

capture confirm variable uid_check
if !_rc {
    capture confirm numeric variable uid_check
    if _rc destring uid_check, replace force
    count if uid != uid_check & !missing(uid_check)
    if r(N) > 0 display as error "`r(N)' records have uid != uid_check."
    drop uid_check
}
duplicates report uid

* caste category as a labelled factor
gen byte caste_cat_n = .
replace  caste_cat_n = 1 if trim(lower(caste_category)) == "general"
replace  caste_cat_n = 2 if trim(lower(caste_category)) == "bc1"
replace  caste_cat_n = 3 if trim(lower(caste_category)) == "bc2"
replace  caste_cat_n = 4 if trim(lower(caste_category)) == "sc"
replace  caste_cat_n = 5 if trim(lower(caste_category)) == "st"
replace  caste_cat_n = 6 if trim(lower(caste_category)) == "other"
label var caste_cat_n "Caste category of the elected mukhiya"
label values caste_cat_n castecat6

* Sample purity: All records should be caste_category != "sc"
display as txt _n "=== Non-SC sample purity: caste_cat should NOT be 'sc' ==="
tab caste_cat_n, missing
count if caste_cat_n == 4
if r(N) > 0 {
    display as error "`r(N)' SC records found in the NON-SC file. Investigate."
    gen byte ns_purity_flag = (caste_cat_n == 4)
    label var ns_purity_flag "Record in non-SC file with caste_cat == sc"
}

* ST respondents: the frame excluded ST, so this should be empty.
count if caste_cat_n == 5
local n_st = r(N)
if `n_st' > 0 {
    display as error "`n_st' ST respondents in the non-SC file (frame excluded ST)."
    if $drop_st == 1 {
        display as txt "drop_st==1: dropping them and reporting the count."
        drop if caste_cat_n == 5
    }
}

*------------------------------------------------------------------------------*
* B2. Proxy respondents and demographics
*------------------------------------------------------------------------------*
gen byte proxy_resp = (trim(lower(resp_type)) == "on_behalf")
label var proxy_resp "Someone other than the mukhiya answered the interview"
label values proxy_resp yesno_lbl
gen byte self_resp = 1 - proxy_resp
label var self_resp "The elected mukhiya answered in person"

tab proxy_resp, missing
capture tab mukhiya_gender proxy_resp, row

gen byte mukh_sex_n = .
replace  mukh_sex_n = 1 if trim(lower(mukhiya_gender)) == "male"
replace  mukh_sex_n = 2 if trim(lower(mukhiya_gender)) == "female"
label var mukh_sex_n "Gender of the elected mukhiya"
label values mukh_sex_n sex2

gen byte educ_ord = .
replace  educ_ord = 1 if trim(lower(educ)) == "none"
replace  educ_ord = 2 if trim(lower(educ)) == "primary"
replace  educ_ord = 3 if trim(lower(educ)) == "middle"
replace  educ_ord = 4 if trim(lower(educ)) == "secondary"
replace  educ_ord = 5 if trim(lower(educ)) == "higher_sec"
replace  educ_ord = 6 if trim(lower(educ)) == "graduate"
label var educ_ord "Education (ordinal 1-6)"
label values educ_ord edu6
gen byte educ_sec = (educ_ord >= 4) if !missing(educ_ord)
label var educ_sec "Completed secondary (10th) or above"
label values educ_sec yesno_lbl

gen byte gp_scshare_ord = .
replace  gp_scshare_ord = 1 if trim(lower(sc_pop_share)) == "lt10"
replace  gp_scshare_ord = 2 if trim(lower(sc_pop_share)) == "b10_15"
replace  gp_scshare_ord = 3 if trim(lower(sc_pop_share)) == "b15_20"
replace  gp_scshare_ord = 4 if trim(lower(sc_pop_share)) == "gt20"
label var gp_scshare_ord "SC share of panchayat population (ordinal 1-4)"
label values gp_scshare_ord scshare4
gen byte gp_scshare_ns = (trim(lower(sc_pop_share)) == "not_sure")
label var gp_scshare_ns "Did not know the panchayat's SC share"

gen byte income_n = .
replace  income_n = 1 if trim(lower(income)) == "agri_labour"
replace  income_n = 2 if trim(lower(income)) == "own_cult"
replace  income_n = 3 if trim(lower(income)) == "small_business"
replace  income_n = 4 if trim(lower(income)) == "salaried"
replace  income_n = 5 if trim(lower(income)) == "govt_scheme"
replace  income_n = 6 if trim(lower(income)) == "other"
label var income_n "Main household income source"
label values income_n income6

gen byte party_n = .
replace  party_n = 1 if trim(lower(party_support)) == "independent"
replace  party_n = 2 if trim(lower(party_support)) == "yes_informal"
replace  party_n = 3 if trim(lower(party_support)) == "yes_formal"
label var party_n "Party or leader support when contesting"
label values party_n party3

gen byte gp_mainvill_n = (trim(lower(gp_mainvill)) == "yes")
label var gp_mainvill_n "Belongs to the main village of the panchayat"
label values gp_mainvill_n yesno_lbl

foreach v in gp_pop revenue_villages n_terms n_stood {
    capture confirm numeric variable `v'
    if _rc destring `v', replace force
}
gen double ln_gp_pop = ln(gp_pop) if gp_pop > 0 & !missing(gp_pop)
label var ln_gp_pop "Log panchayat population"


foreach v in fam_office_* {
    capture confirm numeric variable `v'
    if _rc destring `v', replace force
}

capture confirm variable fam_office_noone
if !_rc {
    gen byte fam_any = 1 - fam_office_noone
}
else {
    gen byte fam_any = (!regexm(trim(lower(fam_office)), "no_one")) ///
                       if !missing(fam_office)
}
label var fam_any "Any family member held a panchayat position before"
label values fam_any yesno_lbl

*------------------------------------------------------------------------------*
* B3. Authority, efficacy, knowledge
*------------------------------------------------------------------------------*

foreach v of global AUTHTASKS {
    gen byte `v'_ord = .
    replace  `v'_ord = 2 if trim(lower(`v')) == "self"
    replace  `v'_ord = 1 if inlist(trim(lower(`v')), "self_family_help", ///
                                   "family_member_for_me")
    replace  `v'_ord = 0 if inlist(trim(lower(`v')), "secretary", "former_mukhiya", ///
                                   "up_mukhiya", "someone_else")
    local lab : variable label `v'
    label var `v'_ord "`lab' (0 displaced / 1 assisted / 2 self)"
    label values `v'_ord authlvl
    gen byte `v'_self = (`v'_ord == 2) if !missing(`v'_ord)
    label var `v'_self "Self-executes: `lab'"
    label values `v'_self yesno_lbl
    gen str20 `v'_who = trim(lower(`v'))
}

gen byte auth_final_ord = .
replace  auth_final_ord = 5 if trim(lower(auth_final)) == "independent"
replace  auth_final_ord = 4 if trim(lower(auth_final)) == "after_consult"
replace  auth_final_ord = 3 if trim(lower(auth_final)) == "jointly"
replace  auth_final_ord = 2 if trim(lower(auth_final)) == "others_formalise"
replace  auth_final_ord = 1 if trim(lower(auth_final)) == "others_entirely"
label var auth_final_ord "Final decision authority (5 = fully independent)"
label values auth_final_ord finaldec
gen byte auth_proxy_self = (auth_final_ord <= 2) if !missing(auth_final_ord)
label var auth_proxy_self "Reports others decide (formalise or entirely)"
label values auth_proxy_self yesno_lbl

foreach v of global EFF {
    capture confirm numeric variable `v'
    if _rc {
        gen byte `v'_n = real(`v')
    }
    else {
        gen byte `v'_n = `v'
    }
    local lab : variable label `v'
    label var `v'_n "`lab'"
    label values `v'_n likert5
}

foreach v in kn_gramsabha kn_gpdp {
    gen byte `v'_claim = (trim(lower(`v')) == "yes")
    gen byte `v'_ns    = (trim(lower(`v')) == "not_sure")
    local lab : variable label `v'
    label var `v'_claim "Claims to know: `lab'"
    label var `v'_ns    "Answered not sure: `lab'"
    label values `v'_claim yesno_lbl
}

gen byte kn_15fc_c  = (trim(lower(kn_15fc)) == "$kn_15fc_correct") if !missing(kn_15fc)
gen byte kn_15fc_ns = (trim(lower(kn_15fc)) == "not_sure")
gen byte kn_cert_c  = (trim(lower(kn_cert)) == "$kn_cert_correct") if !missing(kn_cert)
gen byte kn_cert_ns = (trim(lower(kn_cert)) == "not_sure")
gen byte kn_pmayg_c = (trim(lower(kn_pmayg)) == "$kn_pmayg_correct") if !missing(kn_pmayg)
gen byte kn_pmayg_ns = (trim(lower(kn_pmayg)) == "not_sure")
capture confirm numeric variable kn_commit
if _rc destring kn_commit, replace force
gen byte kn_commit_c = ///
    (abs(kn_commit - $kn_commit_correct) <= $kn_commit_tol) if !missing(kn_commit)
gen byte kn_commit_ns = missing(kn_commit)
foreach v in kn_15fc kn_cert kn_pmayg kn_commit {
    local lab : variable label `v'
    label var `v'_c  "Answered correctly: `lab'"
    label var `v'_ns "Not sure or no answer: `lab'"
    label values `v'_c yesno_lbl
}

*------------------------------------------------------------------------------*
* B4. Attitude battery
*------------------------------------------------------------------------------*
pnslikert $AT_ALL

gen byte att_stereo_nocaste_r = 6 - att_stereo_nocaste_n
label var att_stereo_nocaste_r "Good mukhiya unrelated to caste, REVERSED (5 = disagrees)"
label values att_stereo_nocaste_r likert5

* Final attitude list for indexing: at_nocaste enters in its reversed form.
global AT_IDX  att_res_bad_n att_res_miss_n att_res_incapable_n att_res_hamlets_n ///
               att_stereo_help_n att_stereo_officials_n att_stereo_nocaste_r ///
               att_poa_unjust_n att_poa_fake_n att_vb_cooperate_n att_vb_misuse_n

*------------------------------------------------------------------------------*
* B5. Wellbeing and interview quality
*------------------------------------------------------------------------------*
foreach v of global WB {
    capture confirm numeric variable `v'
    if _rc {
        gen byte `v'_n = real(`v')
    }
    else {
        gen byte `v'_n = `v'
    }
    local lab : variable label `v'
    label var `v'_n "`lab'"
    label values `v'_n wb5
}
egen byte wb_sum_chk = rowtotal(wb_cheer_n wb_calm_n wb_active_n wb_rested_n ///
                                wb_interest_n), missing
label var wb_sum_chk "Wellbeing raw sum, recomputed (5-25)"
gen double wb_scaled = wb_sum_chk * 4
label var wb_scaled "Wellbeing x4 (range 20-100; NOT WHO-5 comparable)"


foreach v in q_underst q_sincere q_conjoint {
    capture confirm numeric variable `v'
    if _rc destring `v', replace force
}

gen byte q_underst_r = 5 - q_underst
label var q_underst_r "Respondent understanding (4 = fully)"
label values q_underst_r qual4
gen byte q_sincere_r = 5 - q_sincere
label var q_sincere_r "Respondent sincerity (4 = fully sincere)"
label values q_sincere_r sinc4

* q_conjoint: REVERSED so that higher = better
gen byte q_conjoint_r = 4 - q_conjoint
label var q_conjoint_r "Conjoint task comprehension (3 = understood well)"
label values q_conjoint_r conj3

gen byte lowqual = (q_underst_r < $qual_min | q_sincere_r < $qual_min) ///
                   if !missing(q_underst_r, q_sincere_r)
label var lowqual "Interview flagged low quality by enumerator"
label values lowqual yesno_lbl

*------------------------------------------------------------------------------*
* B6. Duration
*------------------------------------------------------------------------------*
capture confirm string variable start_time
if !_rc {
    gen double start_dt = clock(subinstr(start_time, "T", " ", 1), "YMDhms#")
    gen double end_dt   = clock(subinstr(end_time,   "T", " ", 1), "YMDhms#")
    format start_dt end_dt %tc
    gen double dur_min = (end_dt - start_dt) / 60000
    label var dur_min "Interview duration in minutes (end - start)"
}

*------------------------------------------------------------------------------*
* B7. Conjoint and Allocation amounts: numeric conversion and design check
*
* IMPORTANT DESIGN FACT, which differs from how the analysis plan describes it.
* Each e_alloc_slot* is an INDEPENDENT range 0-100,000 with no cross-slot
* constraint, and the hint explicitly instructs the respondent NOT to
* subtract amounts spent in previous questions. So this is FOUR independent
* willingness-to-spend measures, each out of a fresh Rs 1,00,000 -- not a
* single budget divided across four profiles.
*------------------------------------------------------------------------------*
* Conjoint
foreach v in 1 2 3 4 5 {
    capture confirm numeric variable cj_flip`v'
    if _rc destring cj_flip`v', replace force
}

* Allocation
foreach k in 1 2 3 4 {
    capture confirm numeric variable al_amt`k'
    if _rc destring al_amt`k', replace force
}
egen double al_total = rowtotal(al_amt1 al_amt2 al_amt3 al_amt4), missing
label var al_total "Sum of the four independent allocation amounts"

display as txt _n "=== Allocation: distribution of the four amounts ==="
summarize al_amt1 al_amt2 al_amt3 al_amt4 al_total, detail

* step compliance: the range widget used step=5000, so every value should be a
* multiple of 5000. A violation indicates manual entry outside the widget.
foreach k in 1 2 3 4 {
    count if mod(al_amt`k', 5000) != 0 & !missing(al_amt`k')
    if r(N) > 0 display as error ///
        "al_amt`k': `r(N)' values are not multiples of 5000. Investigate entry mode."
}

* zero-mass check: substantial clustering at zero is expected and is the reason
* 09_alloc.do prefers a two-part model over Tobit.
foreach k in 1 2 3 4 {
    count if al_amt`k' == 0
    display as txt "al_amt`k' == 0 in `r(N)' records"
}

*------------------------------------------------------------------------------*
* B8. Save
*------------------------------------------------------------------------------*
compress
save "$clean/nonsc_recoded.dta", replace
display as result "Saved: $clean/nonsc_recoded.dta"


*==============================================================================*
* PART C. RECODE VERIFICATION
*==============================================================================*
capture log close recodechk
log using "$out/qc_recode_check_sc.txt", replace text name(recodechk)

use "$clean/sc_recoded.dta", clear

display _n "=================================================================="
display    " SC SURVEY: RECODE VERIFICATION"
display    "=================================================================="

display _n "--- REVERSED: bl_compare -> bl_compare_r (5 should = 'Much worse') ---"
tab bl_compare bl_compare_r, missing

display _n "--- REVERSED: bl_severity -> bl_severity_r (5 should = 'Very severe') ---"
tab bl_severity bl_severity_r, missing

display _n "--- REVERSED: ma_common -> ma_common_r (4 should = 'Very common') ---"
tab ma_common ma_common_r, missing

display _n "--- REVERSED: q_underst -> q_underst_r (4 should = 'Fully') ---"
tab q_underst q_underst_r, missing

display _n "--- REVERSED: q_sincere -> q_sincere_r (4 should = 'Fully sincere') ---"
tab q_sincere q_sincere_r, missing

display _n "--- REVERSED ORDER: auth_final -> auth_final_ord (5 = independent) ---"
tab auth_final auth_final_ord, missing

display _n "--- NOT REVERSED: authority tasks, raw actor -> 0/1/2 ordinal ---"
foreach v of global AUTHTASKS {
    display _n "  `v'"
    tab `v' `v'_ord, missing
}

display _n "--- NOT REVERSED: self-efficacy (5 should = Strongly agree) ---"
foreach v of global EFF {
    tab `v' `v'_n, missing
}

display _n "--- NOT REVERSED: wellbeing (5 should = All of the time) ---"
foreach v of global WB {
    tab `v' `v'_n, missing
}

display _n "--- yesnopns -> binary + refusal flag ---"
foreach v of global MA_INSULT {
    display _n "  `v'"
    tab `v' `v'_b, missing
    tab `v' `v'_pns, missing
}
foreach v of global BL_BUREAU {
    display _n "  `v'"
    tab `v' `v'_b, missing
}

display _n "--- Ordinal codings ---"
tab educ educ_ord, missing
tab sc_pop_share gp_scshare_ord, missing
tab income income_n, missing
tab party_support party_n, missing

log close recodechk


capture log close recodechkns
log using "$out/qc_recode_check_nonsc.txt", replace text name(recodechkns)

use "$clean/nonsc_recoded.dta", clear

display _n "=================================================================="
display    " NON-SC SURVEY: RECODE VERIFICATION"
display    "=================================================================="

display _n "--- REVERSED: at_nocaste -> at_nocaste_r (5 = disagrees, i.e. more prejudiced) ---"
tab att_stereo_nocaste att_stereo_nocaste_r, missing

display _n "--- NOT REVERSED: rest of the attitude battery ---"
foreach v in att_res_bad att_res_miss att_res_incapable att_res_hamlets att_stereo_help ///
             att_stereo_officials att_poa_unjust att_poa_fake att_vb_cooperate att_vb_misuse {
    display _n "  `v'"
    tab `v' `v'_n, missing
    tab `v' `v'_pns, missing
}

display _n "--- REVERSED ORDER: auth_final -> auth_final_ord (5 = independent) ---"
tab auth_final auth_final_ord, missing

display _n "--- REVERSED: q_conjoint -> q_conjoint_r (3 = understood well) ---"
tab q_conjoint q_conjoint_r, missing

display _n "--- Conjoint attribute realisation: check randomisation worked ---"
* Expected marginals: caste 0.50 sc / 0.25 yadav / 0.25 rajput on profile A;
* profile B departs slightly because of the flip guard.
foreach t in 1 2 3 4 5 {
    display _n "  task `t' profile A caste"
    tab cj_caste_a`t'
    display "  task `t' profile B caste (post flip guard)"
    tab cj_caste_b`t'
}

log close recodechkns

display as result _n "=== 02_clean_recode.do complete ==="
display as txt "Verification output: $out/qc_recode_check_sc.txt"
display as txt "                    $out/qc_recode_check_nonsc.txt"
display as error "READ BOTH FILES BEFORE PROCEEDING TO ANALYSIS."

*==============================================================================*
* END 02_clean_recode.do
*==============================================================================*

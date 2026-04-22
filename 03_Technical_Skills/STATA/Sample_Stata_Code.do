/*==============================================================================
Project   	: Bihar NREGA Union (Sample code)
Author    	: Amol Shaila Suresh
Created   	: 20 Jul 2024
Last Modified	: 29 Aug 2024
Purpose   	: (1) Clean and recode Round 1 Wave 2 survey data
              	  (2) Match and merge NREGA administrative data (job cards,
                  employment records) using string-matched panchayat IDs
              	  (3) Prepare GP-level panel and run balance tests on
                  NREGA outcome variables

Notes     : - All file paths are set via globals below. To run on a new
              machine, update the ${root} global only.
            - Requires: balancetable, iebaltab (ssc install iebaltab)
==============================================================================*/

clear all
set more off
macro drop _all

*------------------------------------------------------------------------------*
*                         GLOBAL FILE PATHS                                    *
*------------------------------------------------------------------------------*

***** UPDATE THIS LINE ONLY when running on a new machine *****
global root     "~/Dropbox/Bihar Union Research/Data_All"

global raw      "$root/0_raw_surveys"
global clean    "$root/1_clean_surveys/2_data"
global admin    "$root/0_raw_admin/NREGA_data/WebScrape/Job Card"
global inter    "$root/2_intermediate"
global analyze  "$root/3_analyze"
global data     "$analyze/0_data"
global output   "$analyze/2_out"
global logs     "$analyze/3_logs"

* Date stamp for logs and outputs
local today = subinstr("`c(current_date)'", " ", "_", .)
global today "`today'"


*------------------------------------------------------------------------------*
*                              LOG FILE                                        *
*------------------------------------------------------------------------------*

cap log close _all
log using "$logs/log_clean_survey_wave2_${today}.log", replace text

*==============================================================================*
*                                                                              *
*   SECTION 1: SURVEY DATA CLEANING                                            *
*   Source: Round 1, Wave 2 phone surveys.                                     *
*   Input : $raw/round1_wave2/round1_wave2_npii.dta                            *
*   Output: $clean/round1_wave2_data.dta                                       *
*                                                                              *
*==============================================================================*

di _newline ">>> SECTION 1: Survey Cleaning"

use "$raw/round1_wave2/round1_wave2_npii", clear

* Verify expected observation count before cleaning
count
assert r(N) > 0, rc0
di "Observations loaded: `r(N)'"


***** RECODE MISSING AND DON'T KNOW *****

* SECTION 1: RESPONDENT DEMOGRAPHICS

* Codes 99 and -99 denote "don't know" / "refused" across all numeric vars
#delimit ;
ds  resp_age educ marital_status family_member_male family_member_female
    hh_male_age15 resp_female_age15 resp_land_owner resp_agri_last_year
    resp_family_business resp_caste_cat resp_jati
    resp_jati_list_yn resp_jati_others, has(type numeric) ;
#delimit cr

foreach x in `r(varlist)' {
    replace `x' = . if inlist(`x', 99, -99)
}

* Verify no outlier values in age
assert resp_age >= 18 & resp_age <= 100 if resp_age != .



* SECTION 2: PROGRAM AWARENESS


* MGNREGA jobcard: recode conditional on programme awareness
replace hh_jobcard_mnrega = 0  if heard_mnrega == 0

* Old age pension
replace hh_rec_oldagepension = 0  if heard_oldagepension == 0

* Jeevika (women's SHG programme)
replace hh_participate_jeevika = 0  if heard_jeevika == 0

* Organisation awareness and participation
replace aware_org_name      = "."  if aware_org_name == "-99"

* Conditional zero: if unaware of org, set participation to 0
replace hh_involved_organization = 0  if aware_organization == 0
replace hh_paid_organization     = 0  if aware_organization == 0


* Codes 99 and -99 denote "don't know" / "refused" across all numeric vars
#delimit ;
ds  hh_jobcard_mnrega hh_rec_oldagepension hh_participate_jeevika
    involved_org_name hh_involved_organization 
    hh_paid_organization, has(type numeric) ;
#delimit cr

foreach x in `r(varlist)' {
    replace `x' = . if inlist(`x', 99, -99)
}

rename aware_organization       	aware_org
rename hh_paid_organization     	hh_paid_dues
rename hh_involved_organization 	hh_participate_org

* Flag respondents who identified SPSS organization by name
gen org_name_id_spss = (involved_org_name_1 == 1 | aware_org_name == "1")
la var org_name_id_spss "Respondent identified SPSS organization by name"



* SECTION 3: MGNREGA WORK

* Conditional: if no work after Chhath, no work after Holi either
replace work_mnrega_afterholi = 0 if work_mnrega_afterchhath == 0

rename name_hh_work_days    mnrega_work_days
rename hh_work_wages        mnrega_work_wages

recode mnrega_work_days mnrega_work_wages (-99 = .)

rename hh_work_wages_pending mnrega_wages_pending

* If no work after Holi, set days/wages/pending to 0
foreach v of varlist mnrega_work_days mnrega_work_wages mnrega_wages_pending {
    replace `v' = 0 if work_mnrega_afterholi == 0
    assert `v' >= 0 if `v' != .        // no negative values
}


gen mnrega_wages_pending_any = (mnrega_wages_pending > 0)
la var mnrega_wages_pending_any "Any MGNREGA wages pending (binary)"

replace work_mnrega_afterholi_hh_count = 0  if work_mnrega_afterchhath_hh == 0
replace work_mnrega_afterholi_hh_count = .  if work_mnrega_afterchhath_hh == 99

drop member_detail

* Clean all application and work-days variables
ds appl_jobcard demand_work days_hh_work* wages_hh_work*, has(type numeric)
foreach x in `r(varlist)' {
    replace `x' = . if inlist(`x', 99, -99)
}

* Aggregate household-level MGNREGA totals across members
egen mnrega_hh_total_days  = rowtotal(mnrega_work_days days_hh_work_*),  missing
egen mnrega_hh_total_wages = rowtotal(mnrega_work_wages wages_hh_work_*), missing

la var mnrega_hh_total_days  "Total MGNREGA HH person-days since Holi"
la var mnrega_hh_total_wages "Total MGNREGA HH wages since Holi (INR)"

foreach x in mnrega_work_deny hh_participation_act community_participation_act {
    replace `x' = . if inlist(`x', 99, -99)
}

rename mnrega_work_deny             denied_mnrega
rename hh_participation_act         hh_participate_action
rename community_participation_act  other_participate_action

replace wage_recent          	= . if wage_recent < 0 | inlist(wage_recent, 98, 99)
replace workdays_future_nrega 	= . if workdays_future_nrega < 0



* SECTION 4: NON-NREGA WORK

rename non_nrega_work_days_others_holi  non_nrega_work_days
rename total_income_holi                non_nrega_work_wages
rename (freq_discussed_work freq_discussed_wages) (freq_discuss_work freq_negotiate)

ds non_nrega_work_days non_nrega_work_wages work_offered_private
   work_with_private workdays_future_priv, has(type numeric)
foreach x in `r(varlist)' {
    replace `x' = . if inlist(`x', 99, -99)
}


* Flag respondents not willing to work at any wage
gen     min_wage_97 = (minimum_wages == -97)
la var  min_wage_97 "Respondent not willing to work at any wage"

replace minimum_wages = . if inlist(minimum_wages, -97, -99)
rename  minimum_wages   min_wage
rename  minimum_wages_* min_wage_*

* If no discussion related to work, zero out all discussion channels
foreach x in freq_discussed_whom_*  {
    replace `x' = 0 if freq_discuss_work == 1
}

replace work_offered_private = . if work_offered_private < 0
replace work_with_private    = . if work_with_private    < 0

replace non_nrega_work_days  = 0 if non_nrega_work_holi == 0
replace non_nrega_work_wages = 0 if non_nrega_work_holi == 0



* SECTIONS 5–6: SOCIAL CAPITAL AND GRIEVANCES

ds friends_social friends_work scaling_people_badspeak
   threat_faced threat_faced_nrega, has(type numeric)
foreach x in `r(varlist)' {
    replace `x' = . if inlist(`x', 99, -99)
}



*--------------------------------------*
*       SAVE AND QUICK CHECKS          *
*--------------------------------------*

save "$clean/round1_wave2_data", replace
di "Data cleaning complete. File saved: round1_wave2_data.dta"

* --- Quick data quality checks --- *

* GP-level coverage
bys ugp: egen countHH = count(uid)
egen utag  = tag(ugp)
egen gp50  = tag(ugp) if countHH >= 50

di _newline "  --- Data Quality Summary ---"
sum gp50 if gp50 == 1           // GPs with 50+ surveys complete
ta  panchayat if countHH < 30   // GPs below target threshold
ta  sample_type treatment
ta  share_contact_consent, m

tabstat heard_mnrega aware_org hh_participate_org hh_paid_dues ///
        org_name_id_spss, by(treatment)

tabstat appl_jobcard demand_work work_mnrega_afterholi, by(treatment)
tabstat hh_participate_action other_participate_action, by(treatment)




*==============================================================================*
*                                                                              *
*   SECTION 2: ADMINISTRATIVE DATA — STRING MATCHING AND MERGING               *
*   Source: NREGA job card and employment web-scraped data, Muzaffarpur        *
*   Input : Excel files in $admin/MUZAFFARPUR/                                 *
*   Output: $admin/MUZAFFARPUR/output/			                       *
*                                                                              *
*==============================================================================*


cap cd "$admin"


*--------------------------------------*
*  2.1  PANCHAYAT REFERENCE FILE       *
*--------------------------------------*

import excel "input.xlsx", clear sheet("Sheet1") firstrow
rename H GP_name
keep Dis_name Block_name GP_name pan_code

* Extract numeric panchayat ID from code string
gen panchid_str = substr(pan_code, 5, .)
destring panchid_str, gen(panchid)
format panchid %10.0f

* Validate: no missing panchayat IDs in reference file
assert panchid != .
assert panchid > 0

tempfile input_ref
save `input_ref', replace
di "Panchayat reference file loaded: `r(N)' records"


*--------------------------------------*
*  2.2  JOB CARD DATA                  *
*--------------------------------------*

drop _all
tempfile job_card
qui save `job_card', emptyok

* Append: fragmented excel data files in web scraping
foreach x in job_card missing_job_card {
    import excel using "MUZAFFARPUR/`x'.xlsx", clear firstrow
    append using `job_card'
    qui save `job_card', replace
}

* Document data quality issues before cleaning
count if job_card_no == ""
di "WARNING: `r(N)' records with missing job card number"

count if name_head_household == ""
di "WARNING: `r(N)' records with missing household head name"

* Parse district, block and panchayat IDs from job card number
* Job card structure: BH-XX-XXX-XXX (state-district-block-panchayat)
gen id1 = substr(job_card_no, 4, 2)    // district
gen id2 = substr(job_card_no, 7, 3)    // block
gen id3 = substr(job_card_no, 11, 3)   // panchayat

gen     id0_n = 05                      // Bihar state code
tostring id0_n, gen(id0) format(%02.0f)
drop id0_n

* Reconstruct panchayat, block and district composite IDs
egen panchid_str = concat(id0 id1 id2 id3)
gen  blockid_str = substr(panchid_str, 1, 7)
gen  distid_str  = substr(panchid_str, 1, 4)

destring panchid_str, gen(panchid)
format panchid %10.0f

* Merge with panchayat reference file
merge m:1 panchid using `input_ref'

* Document merge result before dropping
count if _merge == 1
di "WARNING: `r(N)' job cards unmatched to panchayat reference"
count if _merge == 2
di "WARNING: `r(N)' panchayats in reference file with no job cards"

keep if _merge == 3
drop url address panchayat block district id1 id2 id3 id0 pan_code _merge

rename (Dis_name Block_name GP_name) (district block GP)


* Clean GP names: remove slashes and digits, standardize case
gen GP_name = upper(trim(GP))
replace GP_name = subinstr(GP_name, "/", "", .)

* Remove all digit characters via loop (0–9)
forval n = 0/9 {
    replace GP_name = subinstr(GP_name, "`n'", "", .)
}

* Remove multiple internal spaces after digit removal
replace GP_name = itrim(GP_name)

* Validate GP name cleaning
assert GP_name != ""
assert GP_name == upper(GP_name)    // confirm all uppercase

* Drop exact duplicate job cards
duplicates report job_card_no
duplicates drop job_card_no, force
di "Job card file cleaned and deduplicated"

save "MUZAFFARPUR/intermediate/MZ_jobcard_corrected", replace


*--------------------------------------*
*  2.3  APPLICANT DETAILS              *
*--------------------------------------*

preserve

drop _all
tempfile applicant_details
qui save `applicant_details', emptyok

foreach x in applicant_details missing_applicant_details {
    import excel using "MUZAFFARPUR/`x'.xlsx", clear firstrow
    append using `applicant_details'
    qui save `applicant_details', replace
}

count if job_card_no == ""
di "WARNING: `r(N)' applicant records with missing job card number"

tempfile applicant_details
save `applicant_details', replace

restore

merge 1:m job_card_no using `applicant_details'

count if _merge == 1
di "NOTE: `r(N)' job cards with no applicant details"
count if _merge == 2
di "NOTE: `r(N)' applicant records unmatched to job cards"

save "MUZAFFARPUR/output/MZ_jobcard_appdetails_merged", replace


*--------------------------------------*
*  2.4  EMPLOYMENT FILES (LOOP)        *
*--------------------------------------*

* Employment data comes in three types: requested, offered, given
* Each type has 4 main files + 1 missing file

foreach etype in requested offered given {

drop _all
tempfile emp_`etype'
qui save `emp_`etype'', emptyok

forvalues i = 1/4 {
    import excel using "MUZAFFARPUR/employment_`etype'`i'.xlsx", clear firstrow
    append using `emp_`etype''
    qui save `emp_`etype'', replace
    }

    import excel using "MUZAFFARPUR/missing_employment_`etype'.xlsx", clear firstrow
    append using `emp_`etype''
    qui save `emp_`etype'', replace

    count if job_card_no == ""
    di "WARNING: `r(N)' records missing job card no in `etype'"
    drop if job_card_no == ""

    save "MUZAFFARPUR/intermediate/employment_`etype'", replace
    di "  Saved: employment_`etype'.dta"
}


*--------------------------------------*
*  2.5  MERGE EMPLOYMENT TO JOB CARDS  *
*--------------------------------------*

foreach etype in requested offered given {

    use "MUZAFFARPUR/intermediate/MZ_jobcard_corrected", clear

    merge 1:m job_card_no using "MUZAFFARPUR/intermediate/employment_`etype'"

    * Document all merge outcomes explicitly
    count if _merge == 1
    di "`etype': `r(N)' job cards with no employment record"
    count if _merge == 2
    di "`etype': `r(N)' employment records unmatched to job cards"
    count if _merge == 3
    di "`etype': `r(N)' successfully matched records"

    save "MUZAFFARPUR/output/MZ_jobcard_emp`etype'_merged", replace
    di "Saved: MZ_jobcard_emp`etype'_merged.dta"
}



*==============================================================================*
*                                                                              *
*   SECTION 3: BALANCE TABLES — GP-LEVEL NREGA VARIABLES                     *
*   Source: GP-Quarter-Year panel (2021, Q1–Q3)                               *
*   Input : $data/BR_GP_Quarter_Year_vars.dta                                 *
*   Output: $output/BalanceGPNREGA.xlsx, .tex (full, Wave1, Wave2)            *
*                                                                              *
*==============================================================================*


use "$data/BR_GP_Quarter_Year_vars.dta", clear

* Standardize variable names
rename (Wave1 Wave2 Treatment) (wave1 wave2 treatment)


*--------------------------------------*
*  3.1  STRATA AND SAMPLE CONSTRUCTION *
*--------------------------------------*

* Strata defined by median SC population share x randomization wave
gen strataFE = .
replace strataFE = 1 if AboveMedian == 1 & wave1 == 1
replace strataFE = 2 if AboveMedian == 0 & wave1 == 1
replace strataFE = 3 if AboveMedian == 1 & wave2 == 1
replace strataFE = 4 if AboveMedian == 0 & wave2 == 1

* Validate: every observation should have a valid stratum
assert strataFE != .

la def strataFE_l                               ///
    1 "Wave1 & Above Median SC"                 ///
    2 "Wave1 & Below Median SC"                 ///
    3 "Wave2 & Above Median SC"                 ///
    4 "Wave2 & Below Median SC"
la val strataFE strataFE_l
la var strataFE "Randomization strata"

* Restrict to baseline year (2021) Q1–Q3 only
keep if Year    == 2021
keep if Quarter != 4

* Expected: 127 GPs x 3 quarters = 381; Q1 missing for GP 4263
count
assert r(N) >= 375 & r(N) <= 381   // allow for known missing
di "Observations after sample restriction: `r(N)'"


*--------------------------------------*
*  3.2  COLLAPSE TO GP-YEAR LEVEL      *
*--------------------------------------*

#delimit ;
collapse
    (first)   Year PanchayatName BlockName DistrictName
              N_GramPanchayatName N_SubDistrictName N_DistrictName
              wave1 wave2 strataFE treatment
    (mean)    total_hh_working_gp_year
              total_hh_work100_gp_year
              total_cards_gp
              total_cards_gp_sc
              total_active_cards_gp_year
              total_act_sc_cards_gp_year
              total_active_wmen_gp_year
              total_active_SCfem_gp_year
              RequestDayCount_q_v
              RequestDayCount_q_v_sc
              RequestDayCount_fem_q_v
              DayCount_q_v
              DayCount_q_v_sc
              DayCount_fem_q_v
              PaymentReceived_q_v
    (count)   Quarter,
    by(UGP) ;
#delimit cr

rename Quarter              		NofQuarters
rename total_active_wmen_gp_year 	total_active_women_gp_year

* Validate collapse: 127 unique GPs expected
count
assert r(N) <= 127
di "GP-year observations after collapse: `r(N)'"


*--------------------------------------*
*  3.3  GENERATE ANALYSIS VARIABLES    *
*--------------------------------------*

gen P_RequestDayCount_sc  = RequestDayCount_q_v_sc  / RequestDayCount_q_v
gen P_RequestDayCount_fem = RequestDayCount_fem_q_v  / RequestDayCount_q_v
gen P_DayCount_sc         = DayCount_q_v_sc          / DayCount_q_v
gen P_DayCount_fem        = DayCount_fem_q_v         / DayCount_q_v

* Validate proportions: must be between 0 and 1
foreach v of varlist P_* {
    assert `v' >= 0 & `v' <= 1 if `v' != .
}


*--------------------------------------*
*  3.4  VARIABLE LABELS                *
*--------------------------------------*

la var total_cards_gp                 "Total Jobcards in GP"
la var total_cards_gp_sc              "Total Jobcards (Scheduled Castes)"
la var total_active_cards_gp_year     "Total Active Jobcards"
la var total_act_sc_cards_gp_year     "Total Active Jobcards (Scheduled Castes)"
la var total_active_women_gp_year     "Total Active Women Members"
la var total_active_SCfem_gp_year     "Total Active Women Members (Scheduled Castes)"
la var RequestDayCount_q_v            "Total Work Days Requested"
la var RequestDayCount_q_v_sc         "Total Work Days Requested (Scheduled Castes)"
la var RequestDayCount_fem_q_v        "Total Work Days Requested (Women)"
la var DayCount_q_v                   "Total Days Worked"
la var DayCount_q_v_sc                "Total Days Worked (Scheduled Castes)"
la var DayCount_fem_q_v               "Total Days Worked (Women)"
la var PaymentReceived_q_v            "Total Payment Received (INR)"
la var total_hh_working_gp_year       "Total Households Worked"
la var total_hh_work100_gp_year       "Households Completing 100 Work Days"
la var P_RequestDayCount_sc           "Proportion of Work Days Requested by SCs"
la var P_RequestDayCount_fem          "Proportion of Work Days Requested by Women"
la var P_DayCount_sc                  "Proportion of Days Worked by SCs"
la var P_DayCount_fem                 "Proportion of Days Worked by Women"

save "$data/GPSample_NREGA_Q", replace
di "  GP-year analysis file saved"


*--------------------------------------*
*  3.5  BALANCE TESTS                  *
*--------------------------------------*

#delimit ;
local gpcontrols
    total_cards_gp
    total_active_cards_gp_year
    total_act_sc_cards_gp_year
    total_active_women_gp_year
    RequestDayCount_q_v
    P_RequestDayCount_sc
    total_hh_working_gp_year
    DayCount_q_v
    P_DayCount_sc
    P_DayCount_fem
    PaymentReceived_q_v
    total_hh_work100_gp_year ;
#delimit cr

* Validate treatment variable
assert inlist(treatment, 0, 1)
tab treatment, m

* --- Full sample balance table (World Bank's iebaltab command) ---
iebaltab `gpcontrols',                          ///
    grpvar(treatment)                           ///
    fixedeffect(strataFE)                       ///
    vce(robust)                                 ///
    grplabels(0 "Control" @ 1 "Treatment")      ///
    rowvarlabels                                ///
    ttest                                       ///
    savexlsx("$output/BalanceGPNREGA.xlsx")     ///
    savecsvok                                   ///
    replace

* --- Wave 1 subsample ---
preserve
keep if wave1 == 1
iebaltab `gpcontrols',                          ///
    grpvar(treatment)                           ///
    vce(robust)                                 ///
    grplabels(0 "Control" @ 1 "Treatment")      ///
    rowvarlabels                                ///
    ttest                                       ///
    savexlsx("$output/BalanceGPNREGA_W1.xlsx")  ///
    replace
restore

* --- Wave 2 subsample ---
preserve
keep if wave2 == 1
iebaltab `gpcontrols',                          ///
    grpvar(treatment)                           ///
    vce(robust)                                 ///
    grplabels(0 "Control" @ 1 "Treatment")      ///
    rowvarlabels                                ///
    ttest                                       ///
    savexlsx("$output/BalanceGPNREGA_W2.xlsx")  ///
    replace
restore

* --- LaTeX output for paper (full sample, strata FE) ---
#delimit ;
balancetable treatment `gpcontrols'
    using "$output/BalanceGPNREGA.tex",
    vce(robust) fe(strataFE)
    ctitles("Control" "Treatment" "Difference")
    replace varlabels observationscolumn
    oneline nonumbers format(%9.2f) ;
#delimit cr

di _newline "  Balance tables saved to: $output"


*==============================================================================*
*                          END OF SAMPLE DO-FILE                               *
*==============================================================================*


log close _all

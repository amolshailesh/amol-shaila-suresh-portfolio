*==============================================================================*
* 00_master.do
*
* PROJECT : Backlash against independently acting Scheduled Caste mukhiyas
*           in Bihar. Quantitative arm: SC survey (n~150) + non-SC survey (n~150)
* AUTHOR  : Amol Shaila Suresh, MSc Social Research Methods, LSE
* PURPOSE : Sets paths, parameters, and analytical decisions. Calls all other
*           do-files in order. This is the ONLY file whose paths you edit.
*
* HOW TO RUN
*   1. Edit section 1 (paths) and section 4 (analytical decisions).
*   2. Set the run switches in section 6 to control which stages execute.
*   3. Run this file. Do not run the numbered files directly unless debugging,
*      because they assume the globals defined here are already in memory.
*
* DEPENDENCIES
*   ssc install estout      // esttab / eststo for regression tables
*   ssc install coefplot    // AMCE and marginal-means plots
*   ssc install reghdfe     // high-dimensional fixed effects
*   ssc install ftools      // required by reghdfe
*==============================================================================*

clear all
set more off
macro drop _all


*------------------------------------------------------------------------------*
* 1. SETTING PATHS
*------------------------------------------------------------------------------*
global root      "/Users/amolshailasuresh/Library/CloudStorage/Dropbox/LSE/3 Dissertation"


global raw       "$root/Data/Survey/0_raw_data"          // untouched Kobo exports + BSEC frame
global clean     "$root/Data/Survey/1_clean_data"        // analysis-ready .dta files
global dofiles   "$root/Data/Survey/2_do_files"	         // these do-files
global out       "$root/Data/Survey/3_output" 		     // tables and figures
global logs      "$root/Data/Survey/4_log_files"      	 // run logs


*--- raw input filenames ---*
global f_sc_raw     "$raw/sc_survey_export.csv"        	// Kobo export, SC mukhiyas
global f_nonsc_raw  "$raw/nonsc_survey_export.xlsx"     // Kobo export, non-SC mukhiyas
global f_frame      "$raw/frame_with_sample_flags.dta"  // sampling frame


*------------------------------------------------------------------------------*
* 2. REPRODUCIBILITY
*------------------------------------------------------------------------------*

global seed        2026
global bootreps    2000        // bootstrap replications where used


*------------------------------------------------------------------------------*
* 3. LOGGING
*------------------------------------------------------------------------------*
local stamp = subinstr("`c(current_date)'", " ", "_", .)
capture log close _all
log using "$logs/master_`stamp'.smcl", replace name(master)


*------------------------------------------------------------------------------*
* 4. ANALYTICAL DECISIONS
*------------------------------------------------------------------------------*

*--- 4a. Knowledge index: correct answers -------------------------------------*
*
* kn_pmayg : the analysis plan treats "survey_gs" as correct. This is the one
*            item where the plan expresses confidence.
* kn_cert  : verify against current Bihar practice for birth/death
*            registration at panchayat level.
* kn_15fc  : both tied and untied components exist under the 15th FC, so
*            "both" is arguably most accurate. Decide and document.
* kn_commit: verify the statutory number in the Bihar Panchayat Raj Act.
global kn_pmayg_correct  "survey_gs"     // <<< VERIFY
global kn_cert_correct   "secretary"     // <<< VERIFY. Alternatives: mukhiya, both
global kn_15fc_correct   "both"          // <<< VERIFY. Alternatives: tied, untied
global kn_commit_correct 4               // <<< VERIFY statutory number
global kn_commit_tol     0               // tolerance: accept answer within +/- this

*--- 4b. Knowledge index composition ------------------------------------------*
* IMPORTANT MEASUREMENT ISSUE (see notes). Two of the six "rights awareness"
* items are SELF-REPORTED AWARENESS, not demonstrated knowledge:
*   ra_gramsabha "Do you know whether the mukhiya has authority to call a
*                 Gram Sabha on their own?"      -> yes/no/not_sure
*   ra_gpdp      "Do you know what a GPDP is?"   -> yes/no/not_sure
* Neither asks the respondent to state the answer, so neither can be scored
* correct or incorrect. The remaining four items are substantive.
*
* Consequence: a single six-item "knowledge index" mixes two different
* constructs. The code therefore builds THREE measures and lets you choose
* which is primary:
*   kn_demo_idx   3 substantive items scored correct/incorrect
*   kn_claim_idx  2 self-report items scored claims-to-know
*   kn_all_idx    all five pooled, for comparability with the plan as written
global kn_primary "kn_all_idx"

*--- 4c. Microaggression taxonomy: placement of the caste-slur item -----------*
* ma_slur sits in the D2 (microinvalidation) block of the instrument, but a
* caste slur is a MICROASSAULT in Sue et al.'s taxonomy: overt, conscious,
* explicitly derogatory. 1 = reassign to microassault in analysis (footnote
* the instrument's block placement). 0 = keep as instrument-placed.
global slur_as_assault 1

*--- 4d. "Prefer not to say": primary treatment -------------------------------*
* 1 = treat as missing in the primary analysis and report Manski bounds separately.
* 0 = treat as "no". It assumes refusal means non-occurrence.
global pns_to_missing 1

*--- 4e. Conjoint reference categories ----------------------------------------*
* The caste reference is not innocuous; the plan asks you to report both.
* This global sets the reference used in the PRIMARY table; 08_conjoint_amce.do
* runs the alternative automatically as a robustness column.
global cj_caste_ref "yadav"     		// "yadav" | "rajput"
global cj_auth_ref  "follows_elders"    // the coefficient reads as
                                        // the effect of acting independently

*--- 4f. Clustering and fixed effects -----------------------------------------*
* Block-level clustering in the SC/non-SC surveys is only possible after the
* frame merge supplies block identifiers, and is only sensible if the sample
* contains multiple panchayats per block. 04_qc_paradata.do reports the
* number of panchayats per block so you can decide. Until then, robust SEs.
global use_block_cluster 0      // set to 1 after checking cluster counts
global use_district_fe   1      // set to 1 after confirming frame merge

*--- 4g. Non-SC sample: treatment of ST respondents ---------------------------*
* Your sampling frame excluded ST entirely, so this should be empty. The check
* exists because a misrouted call or a frame error could produce one.
* 1 = drop any ST respondent from the non-SC analysis sample and report count.
global drop_st 1

*--- 4h. Interview-quality robustness threshold ------------------------------*
* q_underst and q_sincere are reversed at cleaning so that HIGHER = BETTER.
* On the reversed 1-4 scale, 1 = the worst category ("Poorly" / "Doubtful").
* Robustness analyses exclude interviews at or below this reversed value.
global qual_min 2               // exclude reversed quality == 1


*------------------------------------------------------------------------------*
* 5. ANALYSIS-WIDE VARIABLE LISTS
*------------------------------------------------------------------------------*

*--- de facto authority: the seven task items (identical names in both forms) --*
global AUTHTASKS  auth_gs auth_bdo auth_block auth_works auth_griev
                  

* global AUTHTASKS7 auth_cheq auth_benef auth_gs auth_bdo auth_block ///
                  auth_works auth_griev
				  
				  
*--- self-efficacy (reflective scale; alpha is appropriate here) ---------------*
global EFF        eff_implem eff_obstac eff_goals eff_stand eff_repres

*--- rights and functional knowledge -----------------------------------------*
global KN_DEMO    kn_15fc kn_cert kn_pmayg			     // substantive
global KN_CLAIM   kn_gramsabha kn_gpdp                   // self-reported

*--- microaggression exposure (SC form) --------------------------------------*
* D1 verbal microinsults, all with frequency follow-ups
global MA_INSULT  ma_surprise ma_reserv ma_capacity ma_finance ma_flag
* D2 microinvalidations as placed in the instrument
global MA_INVAL   ma_bypass ma_ignored ma_wait
* D3 microassaults, both with frequency follow-ups
global MA_ASSAULT ma_food
* ma_slur is assigned to one of the two above by global slur_as_assault;
* 02_clean_recode.do writes the final lists into MA_INVAL_F and MA_ASSAULT_F.

*--- backlash exposure (SC form), by channel --------------------------------*
global BL_BUREAU  bl_meet bl_files bl_info bl_hostile     // Theme 1
global BL_INTERN  bl_exmukh bl_deputy bl_ward             // Theme 3
global BL_COMMUN  bl_cases bl_organise                    // Themes 2 and 3
global BL_SYMBOL  bl_symbols bl_rights                    // Theme 4
global BL_VIOLENT bl_threat bl_violence                   // boundary of the
                                                          // contested middle ground

*--- victim-blaming exposure (SC form) --------------------------------------*
global VB         vb_assert vb_notforyou vb_stepback vb_fault

*--- non-SC attitude battery -------------------------------------------------*
global AT_RES     att_res_bad att_res_miss att_res_incapable att_res_hamlets
global AT_STEREO  att_stereo_help att_stereo_officials att_stereo_nocaste     // at_nocaste reversed
global AT_POA     att_poa_unjust att_poa_fake
global AT_VB      att_vb_cooperate att_vb_misuse
global AT_ALL     $AT_RES $AT_STEREO $AT_POA $AT_VB

*--- wellbeing (modified five-point scale; NOT the validated WHO-5) ----------*
global WB         wb_cheer wb_calm wb_active wb_rested wb_interest

*--- covariate ladder for the association models -----------------------------*
* Ladder rungs are used cumulatively in 06_assoc_sc.do
global X_DEMOG    i.educ_ord n_terms n_stood i.mukh_sex_n i.income_n
global X_PANCH    i.gp_scshare_ord ln_gp_pop revenue_villages i.gp_mainvill_n
global X_POLIT    fam_any i.party_n
global X_ALL      $X_DEMOG $X_PANCH $X_POLIT


*------------------------------------------------------------------------------*
* 6. RUN SWITCHES
*------------------------------------------------------------------------------*
local run_import      1
local run_clean       1
local run_indices     1
local run_qc          1
local run_desc_sc     1
local run_assoc_sc    1
local run_cj_reshape  1
local run_cj_amce     1
local run_alloc       1
local run_compare     1
local run_power       1
local run_tabfig      1

if `run_import'     do "$dofiles/01_import_merge.do"
if `run_clean'      do "$dofiles/02_clean_recode.do"
if `run_indices'    do "$dofiles/03_indices.do"
if `run_qc'         do "$dofiles/04_qc_paradata.do"
if `run_desc_sc'    do "$dofiles/05_desc_sc.do"
if `run_assoc_sc'   do "$dofiles/06_assoc_sc.do"
if `run_cj_reshape' do "$dofiles/07_conjoint_reshape.do"
if `run_cj_amce'    do "$dofiles/08_conjoint_amce.do"
if `run_alloc'      do "$dofiles/09_alloc.do"
if `run_compare'    do "$dofiles/10_compare.do"
if `run_power'      do "$dofiles/11_power.do"
if `run_tabfig'     do "$dofiles/12_tables_figures.do"

log close master

display as result _n "=== MASTER RUN COMPLETE ==="
display as txt "Tables and figures: $out"
display as txt "Log: $logs"

*==============================================================================*
* END 00_master.do
*==============================================================================*

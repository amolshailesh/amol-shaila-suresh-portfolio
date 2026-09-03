*==============================================================================*
* 01_import_merge.do
*
* PURPOSE : Import the two Kobo exports, apply the agreed rename/label scheme,
*           merge the Bihar SEC sampling frame for geography, save raw-but-named
*           datasets.
*
* INPUT   : $f_sc_raw, $f_nonsc_raw, $f_frame
* OUTPUT  : $clean/sc_named.dta, $clean/nonsc_named.dta
*
* CRITICAL ENCODING NOTE
*   caste_jati and several free-text fields hold Devanagari. Import as UTF-8.
*   If importing CSV, the encoding("UTF-8") option is mandatory.
*==============================================================================*

*==============================================================================*
* PART A. SC SURVEY
*==============================================================================*

*------------------------------------------------------------------------------*
* A1. Import
*------------------------------------------------------------------------------*

import delimited using "$f_sc_raw", encoding("UTF-8") varnames(1) clear
* import excel using "$f_sc_raw", firstrow case(preserve) clear


* Record how many rows arrived, before any dropping.
count
local n_sc_import = r(N)
display as result "SC rows imported: `n_sc_import'"

*------------------------------------------------------------------------------*
* A2. Kobo system columns
*------------------------------------------------------------------------------*
capture rename _uuid            kobo_uuid
capture rename uuid             kobo_uuid
capture rename _submission_time submit_time
capture rename submission_time  submit_time

#delimit ;
drop 	username audit audit_url _id _index _validation_status _notes _status 
				_submitted_by _tags intro_script note_no_consent note_sensitive_b
				c1_intro c3_intro c4_intro d_intro d_ref d1_head d2_head d3_head
				d3_note e_intro e1_head e2_head e3_head e4_head e5_note f_intro
				g_intro h_thank h_enum_intro privacy note_reschedule 
				caste_jati_001 d2_accompany g_distress;
#delimit cr

*------------------------------------------------------------------------------*
* A3. Rename to analysis names
*------------------------------------------------------------------------------*

*--- metadata and consent ---*
capture rename start                    start_time
capture rename end                      end_time
capture rename today                    survey_date
capture rename deviceid                 device

*--- Module A: respondent and panchayat profile ---*
capture rename uid_dup								uid_check
capture rename respondent_type						resp_type
capture rename proxy_relationship					proxy_rel
capture rename proxy_relationship_other				proxy_rel_other
capture rename respondent_gender					resp_gender
capture rename panchayat_population					gp_pop
capture rename largest_village						gp_mainvill
capture rename dominant_caste						gp_domcaste
capture rename times_stood 							n_stood
capture rename terms_served							n_terms
capture rename education							educ
capture rename income_source						income

*--- Module B: political entry and pathway ---*
capture rename family_political						fam_office
capture rename family_politicalno_one				fam_office_noone
capture rename family_politicalfather				fam_office_father
capture rename family_politicalfather_in_law		fam_office_fil
capture rename family_politicalspouse				fam_office_spouse
capture rename family_politicalsibling				fam_office_sibling
capture rename family_politicalother_relative		fam_office_oth
capture rename contest_idea							entry_idea
capture rename contest_ideaown						entry_idea_own
capture rename contest_ideafamily					entry_idea_fam
capture rename contest_ideasc_community				entry_idea_sccomm
capture rename contest_ideauc_leader				entry_idea_uclead
capture rename contest_ideaex_mukhiya				entry_idea_exmukh
capture rename contest_ideadalit_org				entry_idea_scorg
capture rename contest_ideaparty					entry_idea_party
capture rename contest_ideaother					entry_idea_oth
capture rename contest_idea_other					entry_idea_specify
capture rename withdraw_whopolitical_elite			withdraw_who_elite
capture rename withdraw_whoopposition				withdraw_who_oppos
capture rename withdraw_whoparty_leader				withdraw_who_party
capture rename withdraw_whoown_family				withdraw_who_fam
capture rename withdraw_whoother					withdraw_who_oth
capture rename withdraw_who_other					withdraw_who_specify
capture rename benefit_offered						bribe_offer
capture rename election_threats						elec_threat
capture rename threat_type_other					threat_type_specify          

*--- Module C1: authority ---*
capture rename c1_cheques							auth_cheq
capture rename c1_cheques_other						auth_cheq_o
capture rename c1_beneficiary						auth_benef
capture rename c1_beneficiary_other					auth_benef_o
capture rename c1_gramsabha							auth_gs
capture rename c1_gramsabha_other					auth_gs_o
capture rename c1_meet_bdo							auth_bdo
capture rename c1_meet_bdo_other					auth_bdo_o
capture rename c1_block_rep							auth_block
capture rename c1_block_rep_other					auth_block_o
capture rename c1_dev_priority						auth_works
capture rename c1_dev_priority_other				auth_works_o
capture rename c1_grievances						auth_griev
capture rename c1_grievances_other					auth_griev_o
capture rename final_decision						auth_final

*--- Module C2: self-efficacy ---*
capture rename eff_implement						eff_implem
capture rename eff_obstacle							eff_obstac
capture rename eff_goals							eff_goals
capture rename eff_standground						eff_stand
capture rename eff_represent						eff_repres

*--- Module C3: rights and functional knowledge ---*
capture rename ra_gramsabha							kn_gramsabha
capture rename ra_gpdp								kn_gpdp
capture rename ra_15fc								kn_15fc
capture rename ra_committees						kn_commit
capture rename ra_certificate						kn_cert
capture rename ra_pmayg								kn_pmayg

*--- Module D: microaggressions ---*
capture rename d1_surprise							ma_surprise
capture rename d1_surprise_freq						ma_surprise_f
capture rename d1_reservation						ma_reserv
capture rename d1_reservation_freq					ma_reserv_f
capture rename d1_capacity							ma_capacity
capture rename d1_capacity_freq						ma_capacity_f
capture rename d1_financial							ma_finance
capture rename d1_financial_freq					ma_finance_f
capture rename d1_flag								ma_flag
capture rename d1_flag_freq							ma_flag_f
capture rename d2_bypass							ma_bypass
capture rename d2_slur								ma_slur
capture rename d2_ignored							ma_ignored
capture rename d3_food_seating						ma_food
capture rename d3_food_seating_freq					ma_food_f
capture rename d3_wait_separate						ma_wait
capture rename d3_wait_separate_freq				ma_wait_f
capture rename d4_common							ma_common

*--- Module E: backlash ---*
capture rename e1_refuse_meet						bl_meet
capture rename e1_refuse_meet_freq					bl_meet_f
capture rename e1_delay_files						bl_files
capture rename e1_delay_files_freq					bl_files_f
capture rename e1_withhold_info						bl_info
capture rename e1_withhold_info_freq				bl_info_f
capture rename e1_hostile_caste						bl_hostile
capture rename e1_hostile_caste_freq				bl_hostile_f
capture rename e1_comparison						bl_compare
capture rename e2_former_mukhiya					bl_exmukh
capture rename e2_deputy_secretary					bl_deputy
capture rename e2_ward_members						bl_ward
capture rename e3_false_cases						bl_cases
capture rename e3_organise_against					bl_organise
capture rename e4_symbols_damaged					bl_symbols
capture rename e4_rights_opposition					bl_rights
capture rename e5_threats							bl_threat
capture rename e5_violence							bl_violence
capture rename e6_severity							bl_severity

*--- Module F: victim-blaming exposure ---*
capture rename f_asked_for_it						vb_assert
capture rename f_not_for_you						vb_notforyou
capture rename f_step_back							vb_stepback
capture rename f_own_fault							vb_fault

*--- Module G: wellbeing ---*
capture rename who5_cheerful						wb_cheer
capture rename who5_calm							wb_calm
capture rename who5_active							wb_active
capture rename who5_rested							wb_rested
capture rename who5_interest						wb_interest
capture rename who5_raw_score						wb_sum

*--- Module H: closing and enumerator assessment ---*
capture rename h1_open								open_txt
capture rename h_understanding						q_underst
capture rename h_sincerity							q_sincere
capture rename h_independent						q_indep
capture rename enum_notes							q_notes


*------------------------------------------------------------------------------*
* A4. Verify the rename succeeded
*------------------------------------------------------------------------------*
local required uid consent resp_type mukhiya_gender caste_category sc_pop_share ///
               gp_pop revenue_villages n_terms n_stood educ income auth_final   ///
               $AUTHTASKS $EFF $KN_DEMO $KN_CLAIM                               ///
               $MA_INSULT $MA_INVAL $MA_ASSAULT ma_slur ma_common               ///
               $BL_BUREAU bl_compare $BL_INTERN $BL_COMMUN $BL_SYMBOL           ///
               $BL_VIOLENT $VB $WB q_underst q_sincere q_indep
			   
local missing_sc ""
foreach v of local required {
    capture confirm variable `v'
    if _rc local missing_sc "`missing_sc' `v'"
}
if "`missing_sc'" != "" {
    display as error "MISSING after rename (SC):`missing_sc'"
    display as error "Check the Kobo export for group-prefixed names, then fix A3."
    exit 111
}
display as result "SC rename verified: all required variables present."

*------------------------------------------------------------------------------*
* A5. Apply variable labels
*------------------------------------------------------------------------------*
label var uid          		"Unique respondent ID from sample frame"
label var uid_check    		"Unique ID re-entered for verification"
label var consent      		"Agreed to take part in the interview"
label var eligible        	"Eligible for interview (consent given)"
label var mukhiya_name   	"Name of the elected mukhiya"
label var resp_type    		"Respondent is the mukhiya or answering on their behalf"
label var mukhiya_gender    "Gender of the elected mukhiya"
label var proxy_rel    		"Proxy respondent's relationship to the mukhiya"
label var resp_gender     	"Gender of respondent, if answering on behalf"
label var caste_category    "Caste category of the elected mukhiya"
label var caste_jati        "Caste or jati of the elected mukhiya"
label var revenue_villages  "Number of revenue villages in the panchayat"
label var gp_pop    	   	"Approximate total population of the panchayat"
label var sc_pop_share   	"Approximate SC share of panchayat population"
label var gp_mainvill  		"Respondent belongs to the main village of the panchayat"
label var gp_domcaste  		"Most dominant or influential caste group in the panchayat"
label var n_stood      		"Number of times stood for mukhiya election"
label var n_terms      		"Number of terms served as mukhiya, including current"
label var educ         		"Highest level of education completed"
label var income       		"Main source of household income"

label var fam_office   		"Family member held a panchayat position before"
label var entry_idea   		"Whose idea it was to contest the election"
label var party_support     "Contested with support of a political party or leader"
label var withdraw_asked    "Was asked to withdraw nomination"
label var withdraw_who      "Who asked respondent to withdraw"
label var bribe_offer  		"Offered money, land or benefits to step aside or comply"
label var elec_threat  		"Faced threats or intimidation during the election"
label var threat_type  		"Type of threat faced during the election"

label var auth_cheq    		"Who prepares cheques and financial documents"
label var auth_benef   		"Who decides the scheme beneficiary lists"
label var auth_gs      		"Who chairs and runs the Gram Sabha meeting"
label var auth_bdo     		"Who meets the BDO and other officials"
label var auth_block   		"Who represents the panchayat at block-level meetings"
label var auth_works   		"Who decides which development works get priority"
label var auth_griev   		"Who attends to villagers' complaints and requests"
label var auth_final   		"Who makes the final call on important decisions"

label var eff_implem   		"Can get decisions implemented despite opposition"
label var eff_obstac   		"Can find a way to get work done when obstructed"
label var eff_goals    		"Confident of achieving most goals set for self"
label var eff_stand    		"Can stand ground when pressured on a decision"
label var eff_repres   		"Confident representing the panchayat before officials"

label var kn_gramsabha      "Claims to know mukhiya can call a Gram Sabha (self-report)"
label var kn_gpdp      		"Claims to know what a GPDP is (self-report)"
label var kn_15fc      		"Fund type reported under the 15th Finance Commission"
label var kn_commit    		"Number of GP standing committees reported"
label var kn_cert      		"Who issues birth and death certificates, as reported"
label var kn_pmayg     		"How PMAY-G beneficiaries are selected, as reported"

label var ma_surprise  		"People seemed surprised he or she can handle the duties"
label var ma_reserv    		"Told the position was obtained only through reservation"
label var ma_capacity  		"Education or capacity for the job was questioned"
label var ma_finance   		"Financial standing to be a leader was questioned"
label var ma_flag      		"Suggested someone else hoist the flag on national days"
label var ma_bypass    		"People took official work to the ex-mukhiya or secretary"
label var ma_slur      		"Caste-based slur used against respondent"
label var ma_ignored   		"Suggestions ignored in meetings for lack of schooling"
label var ma_food      		"Treated differently over food or seating at a function"
label var ma_wait      		"Made to wait or seated separately, unlike upper castes"
label var ma_common    		"Perceived prevalence of such treatment among SC mukhiyas"

label var bl_meet      		"Officials refused to meet or made him or her return"
label var bl_files     		"Files or approvals delayed without good reason"
label var bl_info      		"Kept in the dark about lists or entitled information"
label var bl_hostile   		"An official turned hostile on realising respondent's caste"
label var bl_compare   		"Treatment by officials vs upper-caste mukhiyas"
label var bl_exmukh    		"Former mukhiya interfered with or undermined the work"
label var bl_deputy    		"Deputy mukhiya or secretary worked against decisions"
label var bl_ward      		"Ward members or elected members refused to cooperate"
label var bl_cases     		"False accusations, complaints or cases filed"
label var bl_organise  		"Upper-caste elites tried to organise people against him"
label var bl_symbols   		"Ambedkar statue or community symbols damaged or opposed"
label var bl_rights    		"Faced opposition for making people aware of their rights"
label var bl_threat    		"Received threats because of the work or the caste"
label var bl_violence  		"Respondent or family faced physical harm or violence"
label var bl_severity  		"Overall severity of caste-related difficulties"

label var vb_assert    		"Told troubles were self-inflicted by being too assertive"
label var vb_notforyou 		"Told politics is not for people like you"
label var vb_stepback  		"Told to step back or stay quiet to avoid trouble"
label var vb_fault     		"Told problems are own fault for not cooperating"

label var wb_cheer     		"Felt cheerful and in good spirits, last two weeks"
label var wb_calm      		"Felt calm and relaxed, last two weeks"
label var wb_active    		"Felt active and vigorous, last two weeks"
label var wb_rested    		"Woke up feeling fresh and rested, last two weeks"
label var wb_interest  		"Daily life filled with things of interest, last two weeks"
capture label var wb_sum 	"Wellbeing raw sum 5-25 (modified 5-point, not WHO-5 norm)"

label var open_txt     		"Open response: anything important not asked"
label var q_underst    		"Enumerator: how well the respondent understood"
label var q_sincere    		"Enumerator: how sincerely the respondent answered"
label var q_indep      		"Enumerator: was the respondent independently acting"
label var q_notes      		"Enumerator: other comments on the interview"

* frequency follow-ups: label programmatically from the parent label
foreach v of varlist ma_*_f bl_*_f {
    local parent = subinstr("`v'", "_f", "", 1)
    capture local pl : variable label `parent'
    capture label var `v' "Frequency: `pl'"
}

*------------------------------------------------------------------------------*
* A6. Flag the sample and save
*------------------------------------------------------------------------------*
gen byte sc_sample = 1
label var sc_sample "Respondent is an SC mukhiya (1) or non-SC (0)"


* Corrections: data-entry mistakes (wrong uid)
replace uid = 100391 if uid == 10039


compress
save "$clean/sc_cleaned.dta", replace
display as result "Saved: $clean/sc_cleaned.dta"


*==============================================================================*
* PART B. NON-SC SURVEY
*==============================================================================*

*------------------------------------------------------------------------------*
* B1. Import
*------------------------------------------------------------------------------*

* import delimited using "$f_nonsc_raw", encoding("UTF-8") varnames(1) clear
import excel using "$f_nonsc_raw", firstrow case(preserve) clear

count
local n_ns_import = r(N)
display as result "Non-SC rows imported: `n_ns_import'"

*------------------------------------------------------------------------------*
* B2. Kobo system columns
*------------------------------------------------------------------------------*
capture rename _uuid            	kobo_uuid
capture rename uuid             	kobo_uuid
capture rename _submission_time 	submit_time
capture rename submission_time  	submit_time

#delimit ;
drop 	username audit audit_URL _id _index _validation_status _notes 
				_status _submitted_by _tags
				intro_script note_no_consent b1_intro b2_intro_001
				b4_intro c_intro d_intro read_profiles_t1 read_profiles_t2 
				read_profiles_t3 read_profiles_t4 read_profiles_t5 e_intro 
				f_intro g_thank g_enum_intro e_reason ts_sec_mod_g g_guarded 
				ts_survey_end survey_duration_min enum_id ts_sec_mod0 privacy 
				note_reschedule ts_sec_mod_a ts_sec_mod_b b3_intro ts_sec_mod_c 
				att_poa_heard att_vb_aggressive ts_sec_mod_d gender_A_t1 
				gender_B_t1 education_B_raw_t1 gender_A_t2 gender_B_t2 
				education_B_raw_t2 gender_A_t3 gender_B_t3 education_B_raw_t3 
				gender_A_t4 gender_B_t4 education_B_raw_t4 gender_A_t5 
				gender_B_t5 education_B_raw_t5 ts_sec_mod_e f_distress;
#delimit cr

*------------------------------------------------------------------------------*
* B3. Drop conjoint and allocation intermediate calculations
*------------------------------------------------------------------------------*
foreach t in 1 2 3 4 5 {
    capture drop caste_u_A_t`t'
    capture drop caste_u_B_t`t'
    capture drop caste_B_dup_t`t'
    capture drop prof_A_hi_t`t' prof_A_en_t`t'
    capture drop prof_B_hi_t`t' prof_B_en_t`t'
}

foreach k in 1 2 3 4 {
    capture drop e_k`k'
    capture drop e_rank_p`k'
    capture drop e_slot`k'_desc_hi
    capture drop e_slot`k'_desc_en
}

*------------------------------------------------------------------------------*
* B4. Rename to analysis names
*------------------------------------------------------------------------------*

*--- metadata and consent ---*
capture rename start                    start_time
capture rename end                      end_time
capture rename today                    survey_date
capture rename deviceid                 device

*--- Module A: respondent and panchayat profile ---*
capture rename uid_dup								uid_check
capture rename respondent_type						resp_type
capture rename proxy_relationship					proxy_rel
capture rename proxy_relationship_other				proxy_rel_other
capture rename respondent_gender					resp_gender
capture rename panchayat_population					gp_pop
capture rename largest_village						gp_mainvill
capture rename dominant_caste						gp_domcaste
capture rename times_stood 							n_stood
capture rename terms_served							n_terms
capture rename education							educ
capture rename income_source						income

capture rename family_political						fam_office
capture rename family_politicalno_one				fam_office_noone
capture rename family_politicalfather				fam_office_father
capture rename family_politicalfather_in_law		fam_office_fil
capture rename family_politicalspouse				fam_office_spouse
capture rename family_politicalsibling				fam_office_sibling
capture rename family_politicalother_relative		fam_office_oth

              

*--- Module B1: authority ---*
capture rename auth_cheques							auth_cheq
capture rename auth_cheques_other					auth_cheq_o
capture rename auth_beneficiary						auth_benef
capture rename auth_beneficiary_other				auth_benef_o
capture rename auth_gramsabha						auth_gs
capture rename auth_gramsabha_other					auth_gs_o
capture rename auth_meet_bdo						auth_bdo
capture rename auth_meet_bdo_other					auth_bdo_o
capture rename auth_block_rep						auth_block
capture rename auth_block_rep_other					auth_block_o
capture rename auth_dev_priority					auth_works
capture rename auth_dev_priority_other				auth_works_o
capture rename auth_grievances						auth_griev
capture rename auth_grievances_other				auth_griev_o
capture rename final_decision						auth_final

*--- Module B2: self-efficacy ---*
capture rename eff_implement						eff_implem
capture rename eff_obstacle							eff_obstac
capture rename eff_goals							eff_goals
capture rename eff_standground						eff_stand
capture rename eff_represent						eff_repres

*--- Module B3: rights and functional knowledge ---*
capture rename ra_gramsabha							kn_gramsabha
capture rename ra_gpdp								kn_gpdp
capture rename ra_15fc								kn_15fc
capture rename ra_committees						kn_commit
capture rename ra_certificate						kn_cert
capture rename ra_pmayg								kn_pmayg

*--- Module D: conjoint experiment ---*
foreach t in 1 2 3 4 5 {
    capture rename caste_A_t`t'      				cj_caste_a`t'
    capture rename caste_B_t`t'      				cj_caste_b`t'
    capture rename authority_A_t`t'  				cj_auth_a`t'
    capture rename authority_B_t`t'  				cj_auth_b`t'
    capture rename economic_A_t`t'   				cj_econ_a`t'
    capture rename economic_B_t`t'   				cj_econ_b`t'
    capture rename education_A_t`t'  				cj_educ_a`t'
    capture rename education_B_t`t'  				cj_educ_b`t'
    capture rename same_flag_t`t'    				cj_flip`t' 
	capture rename coop_t`t'						cj_coop`t'
	capture rename elect_t`t'						cj_elect`t'
}

*--- Module E: resource allocation experiment ---*
foreach k in 1 2 3 4 {
    capture rename e_slot`k'_profile  				al_prof`k'
    capture rename e_alloc_slot`k'					al_amt`k'
}

*--- Module F: wellbeing ---*
capture rename who5_cheerful						wb_cheer
capture rename who5_calm							wb_calm
capture rename who5_active							wb_active
capture rename who5_rested							wb_rested
capture rename who5_interest						wb_interest
capture rename who5_raw_score						wb_sum
capture rename ts_sec_mod_f              			ts_wb

*--- Module G: closing and enumerator assessment ---*
capture rename g1_open								open_txt
capture rename g_understanding						q_underst
capture rename g_sincerity							q_sincere
capture rename g_conjoint_understood				q_conjoint
capture rename enum_notes							q_notes


*------------------------------------------------------------------------------*
* B5. Verify
*------------------------------------------------------------------------------*
local required uid consent resp_type mukhiya_gender caste_category sc_pop_share ///
               gp_pop revenue_villages n_terms n_stood educ income auth_final   ///
               $AUTHTASKS $EFF $KN_DEMO $KN_CLAIM $AT_ALL $WB                	///
               q_underst q_sincere q_conjoint

foreach t in 1 2 3 4 5 {
    local required "`required' cj_caste_a`t' cj_caste_b`t' cj_auth_a`t' cj_auth_b`t'"
    local required "`required' cj_econ_a`t' cj_econ_b`t' cj_educ_a`t' cj_educ_b`t'"
    local required "`required' cj_flip`t' cj_coop`t' cj_elect`t'"
}

foreach k in 1 2 3 4 {
    local required "`required' al_prof`k' al_amt`k'"
}

local missing_ns ""
foreach v of local required {
    capture confirm variable `v'
    if _rc local missing_ns "`missing_ns' `v'"
}
if "`missing_ns'" != "" {
    display as error "MISSING after rename (non-SC):`missing_ns'"
    exit 111
}
display as result "Non-SC rename verified: all required variables present."

*------------------------------------------------------------------------------*
* B6. Labels
*------------------------------------------------------------------------------*
label var uid          			"Unique respondent ID from sample frame"
label var consent      			"Agreed to take part in the interview"
label var resp_type    			"Respondent is the mukhiya or answering on their behalf"
label var mukhiya_gender    	"Gender of the elected mukhiya"
label var caste_category    	"Caste category of the elected mukhiya"
label var revenue_villages  	"Number of revenue villages in the panchayat"
label var gp_pop       			"Approximate total population of the panchayat"
label var sc_pop_share   		"Approximate SC share of panchayat population"
label var gp_mainvill  			"Respondent belongs to the main village of the panchayat"
label var n_stood      			"Number of times stood for mukhiya election"
label var n_terms      			"Number of terms served as mukhiya, including current"
label var educ         			"Highest level of education completed"
label var income       			"Main source of household income"
label var party_support     	"Contested with support of a political party or leader"
label var auth_cheq    			"Who prepares cheques and financial documents"
label var auth_benef   			"Who decides the scheme beneficiary lists"
label var auth_gs      			"Who chairs and runs the Gram Sabha meeting"
label var auth_bdo     			"Who meets the BDO and other officials"
label var auth_block   			"Who represents the panchayat at block-level meetings"
label var auth_works   			"Who decides which development works get priority"
label var auth_griev   			"Who attends to villagers' complaints and requests"
label var auth_final   			"Who makes the final call on important decisions"
label var eff_implem   			"Can get decisions implemented despite opposition"
label var eff_obstac   			"Can find a way to get work done when obstructed"
label var eff_goals    			"Confident of achieving most goals set for self"
label var eff_stand    			"Can stand ground when pressured on a decision"
label var eff_repres   			"Confident representing the panchayat before officials"
label var kn_gramsabha        	"Claims to know mukhiya can call a Gram Sabha (self-report)"
label var kn_gpdp      			"Claims to know what a GPDP is (self-report)"
label var kn_15fc      			"Fund type reported under the 15th Finance Commission"
label var kn_commit    			"Number of GP standing committees reported"
label var kn_cert      			"Who issues birth and death certificates, as reported"
label var kn_pmayg     			"How PMAY-G beneficiaries are selected, as reported"

label var att_res_bad	    	"Reservation of mukhiya seats for SCs is bad for democracy"
label var att_res_miss	    	"Capable people miss the chance because the seat is reserved"
label var att_res_incapable 	"SC mukhiyas via reservation are usually not capable"
label var att_res_hamlets		"SC mukhiyas via reservation only work in SC/ST hamlets"
label var att_stereo_help   	"SC mukhiyas need more help running the panchayat"
label var att_stereo_officials  "SC mukhiyas find it harder to deal with officials"
label var att_stereo_nocaste    "Being a good mukhiya has nothing to do with caste (rev)"
label var att_poa_unjust		"SC/ST Atrocities Act is unjust for non-SC/ST communities"
label var att_poa_fake		    "Many fake cases are filed under the SC/ST Atrocities Act"
label var att_vb_cooperate   	"SC mukhiyas would face fewer problems if they cooperated"
label var att_vb_misuse		  	"SC mukhiyas usually misuse their position"

label var wb_cheer     			"Felt cheerful and in good spirits, last two weeks"
label var wb_calm      			"Felt calm and relaxed, last two weeks"
label var wb_active    			"Felt active and vigorous, last two weeks"
label var wb_rested    			"Woke up feeling fresh and rested, last two weeks"
label var wb_interest  			"Daily life filled with things of interest, last two weeks"
capture label var wb_sum 		"Wellbeing raw sum 5-25 (modified 5-point, not WHO-5 norm)"

foreach t in 1 2 3 4 5 {
    label var cj_caste_a`t' 	"Conjoint task `t': caste of profile A"
    label var cj_caste_b`t' 	"Conjoint task `t': caste of profile B"
    label var cj_auth_a`t'  	"Conjoint task `t': authority style of profile A"
    label var cj_auth_b`t' 		"Conjoint task `t': authority style of profile B"
    label var cj_econ_a`t'  	"Conjoint task `t': economic status of profile A"
    label var cj_econ_b`t'  	"Conjoint task `t': economic status of profile B"
    label var cj_educ_a`t'  	"Conjoint task `t': education of profile A"
    label var cj_educ_b`t'  	"Conjoint task `t': education of profile B"
    label var cj_flip`t'    	"Conjoint task `t': flip guard fired"
    label var cj_coop`t'    	"Conjoint task `t': profile easier to cooperate with"
    label var cj_elect`t'   	"Conjoint task `t': profile preferred as own mukhiya"
}

foreach k in 1 2 3 4 {
    label var al_prof`k' 		"Allocation slot `k': which profile P1-P4 was presented"
    label var al_amt`k'  		"Allocation slot `k': rupees spent to block this profile"
}

label var q_underst   			"Enumerator: how well the respondent understood"
label var q_sincere   			"Enumerator: how sincerely the respondent answered"
label var q_conjoint  			"Enumerator: how well the conjoint task was grasped"
label var q_notes     			"Enumerator: other comments on the interview"
label var open_txt    			"Open response: anything important not asked"

gen byte sc_sample = 0
label var sc_sample "Respondent is an SC mukhiya (1) or non-SC (0)"

compress
save "$clean/nonsc_cleaned.dta", replace
display as result "Saved: $clean/nonsc_cleaned.dta"


*==============================================================================*
* PART C. MERGE THE SAMPLING FRAME
*==============================================================================*

*------------------------------------------------------------------------------*
* C1. Prepare the frame
*------------------------------------------------------------------------------*
use "$f_frame", clear

label var strata				"Strata"
label var district				"District"
label var block					"Block"
label var gp					"Gram Panchayat"
label var seat_resv				"Reservation status"

local framevars uid strata district block gp sample_group seat_resv
capture keep `framevars'
if _rc {
    display as error "One of `framevars' is absent from the frame file."
    display as error "Run  describe using \"$f_frame\"  and edit the keeplist in C1."
    exit 111
}

* the merge key must be unique in the frame
isid uid

tempfile frame
save `frame'

*------------------------------------------------------------------------------*
* C2. Merge onto each survey
*------------------------------------------------------------------------------*
foreach s in sc nonsc {

    use "$clean/`s'_cleaned.dta", clear

    * uid must be numeric in both files for the merge to work
    capture confirm numeric variable uid
    if _rc {
        display as txt "uid is string in `s'; destringing."
        destring uid, replace force
        count if missing(uid)
        if r(N) > 0 display as error "`r(N)' records have non-numeric uid. Inspect."
    }

    merge m:1 uid using `frame', gen(_merge)

    * Diagnose the merge rather than silently keeping matches.
    display as txt _n "=== Frame merge diagnostics: `s' ==="
    tab _merge

    * _merge==1: a survey record whose uid is not in the frame
    count if _merge == 1
    if r(N) > 0 {
        display as error "`r(N)' survey records did not match the frame."
        preserve
            keep if _merge == 1
            keep uid mukhiya_name caste_category
            list, clean noobs
            export excel using "$out/qc_unmatched_uid_`s'.xlsx", ///
                firstrow(variables) replace
        restore
    }

    * _merge==2: frame records with no survey
    preserve
        keep if _merge == 2
        count
        if r(N) > 0 {
            keep uid strata district block gp sample_group
            save "$clean/`s'_nonresponse.dta", replace
            display as txt "Saved non-response list: $clean/`s'_nonresponse.dta"
        }
    restore

    drop if _merge == 1
	drop if _merge == 2
    drop _merge

    compress
    save "$clean/`s'_merged.dta", replace
    display as result "Saved: $clean/`s'_merged.dta"
}

display as result _n "=== 01_import_merge.do complete ==="

*==============================================================================*
* END 01_import_merge.do
*==============================================================================*

/*------------------------------------------------------------------------------
Project: Bihar NREGA Union
Purpose: Insheeting raw data, cleaning variables names and values for 
Round 1, Wave 2 surveys in Oct-Dec 2022.
------------------------------------------------------------------------------*/

clear
set more off 
 
cap cd "~/Dropbox/Bihar Union Research/Data_All/"

*------------------------------------------------------------------------------*
							* LOAD FILE *
*------------------------------------------------------------------------------*	

	use "./0_raw_surveys/round1_wave2/round1_wave2_npii", clear

*------------------------------------------------------------------------------*
					*  RECODE and RENAME VARIABLES * 
*------------------------------------------------------------------------------*
/* recode variables that were skipped and don't knows */ 

* section 1

	#delimit;
	ds resp_age educ marital_status family_member_male family_member_female 
		hh_male_age15 resp_female_age15 resp_land_owner resp_agri_last_year
		resp_family_business 
		resp_caste_cat resp_jati resp_jati_list_yn resp_jati_others, has(type numeric);
	#delimit cr	

	foreach x in `r(varlist)' {

		replace  `x' = . if `x' == 99 | `x' == -99

	}

* section 2

	replace hh_jobcard_mnrega = 0 if heard_mnrega == 0 
	replace hh_jobcard_mnrega = . if hh_jobcard_mnrega==99 

	//g how_work_mnrega_c = inlist(how_work_mnrega,2,3)
	//order how_work_mnrega_c,after(how_work_mnrega)

	replace hh_rec_oldagepension = 0 if heard_oldagepension == 0 
	replace hh_rec_oldagepension = . if hh_rec_oldagepension == 99

	replace hh_participate_jeevika = 0 if heard_jeevika==0 
	replace hh_participate_jeevika = . if hh_participate_jeevika==99
	
	replace aware_org_name = "." if aware_org_name == "-99"
	replace involved_org_name = . if involved_org_name == -99

	replace hh_involved_organization  = . if hh_involved_organization==99
	replace hh_paid_organization = . if hh_paid_organization==99

	replace hh_involved_organization = 0 if aware_organization == 0 
	replace hh_paid_organization = 0 if aware_organization == 0 

	rename aware_organization aware_org 
	rename hh_paid_organization hh_paid_dues
	rename hh_involved_organization hh_participate_org
	
	g org_name_id_spss = (involved_org_name_1 == 1 | aware_org_name == "1")

* section 3 

	replace work_mnrega_afterholi = 0 if work_mnrega_afterchhath == 0
	
	rename name_hh_work_days mnrega_work_days
	rename hh_work_wages 	mnrega_work_wages
	
	recode  mnrega_work_days mnrega_work_wages (-99=.)
	
// if did not work after holi, days and wages are 0
	replace mnrega_work_days = 0 	if work_mnrega_afterholi==0
	replace mnrega_work_wages = 0 	if work_mnrega_afterholi==0
	
	rename hh_work_wages_pending mnrega_wages_pending
	replace mnrega_wages_pending = 0 	if work_mnrega_afterholi==0

	g mnrega_wages_pending_any = (mnrega_wages_pending > 0 & mnrega_wages_pending != .)
	
	replace work_mnrega_afterholi_hh_count = 0 if work_mnrega_afterchhath_hh == 0 
	replace work_mnrega_afterholi_hh_count =. if work_mnrega_afterchhath_hh == 99 // don't know
	
	drop member_detail
	
	ds appl_jobcard demand_work days_hh_work* wages_hh_work*, has(type numeric)
	foreach x in `r(varlist)' {
		replace  `x' = . if `x' == 99 | `x' == -99
		replace  `x' = . if `x' < 0

	}
	
	egen mnrega_hh_total_days = rowtotal(mnrega_work_days days_hh_work_*),m
	egen mnrega_hh_total_wages = rowtotal(mnrega_work_wages wages_hh_work_*),m
	
	la var mnrega_hh_total_days "Total NREGA HH person days since holi"
	la var mnrega_hh_total_wages "Total NREGA HH wages since holi"
		
	foreach x in mnrega_work_deny hh_participation_act community_participation_act {
		replace `x' = . if `x' == 99 | `x' == -99
	}
	
	rename mnrega_work_deny denied_mnrega
	rename hh_participation_act  hh_participate_action
	rename community_participation_act other_participate_action
	
	replace wage_recent = . if wage_recent < 0 | wage_recent == 98 | wage_recent == 99
	replace workdays_future_nrega = . if workdays_future_nrega < 0
	

* section 4
		
	replace non_nrega_work_days_others_holi = . if non_nrega_work_days_others_holi == -99
	replace total_income_holi = . if total_income_holi==-99
	
	rename non_nrega_work_days_others_holi non_nrega_work_days
	rename total_income_holi non_nrega_work_wages
	
	replace work_offered_private = . if work_offered_private == -99
	replace work_with_private = . if work_with_private == -99
	
	rename (freq_discussed_work freq_discussed_wages) (freq_discuss_work freq_negotiate)
	
	replace workdays_future_priv = . if workdays_future_priv == -99
	
	g min_wage_97 = 1 if minimum_wages == -97
	la var min_wage_97 "not willing to work at all"
	replace minimum_wages = . if minimum_wages == -97 | minimum_wages == -99
	
	rename minimum_wages min_wage
	rename minimum_wages_* min_wage_*

	foreach x in freq_discussed_whom_1 freq_discussed_whom_2 freq_discussed_whom_3 freq_discussed_whom_4 freq_discussed_whom_98 {
		replace `x' = 0 if freq_discuss_work == 1
	}
	
	replace work_offered_private = . if work_offered_private < 0
	replace work_with_private = . if work_with_private < 0
	
	replace non_nrega_work_days = 0 if non_nrega_work_holi == 0
	replace non_nrega_work_wages = 0 if non_nrega_work_holi == 0
	
	
* section 5
 
  	replace friends_social =. if friends_social==-99
	replace friends_work	=. if friends_work==-99
		
	replace scaling_people_badspeak =. if scaling_people_badspeak==-99
	
* Section 6
 
	replace threat_faced =. if threat_faced ==99
	replace threat_faced_nrega =. if threat_faced_nrega ==99


*------------------------------------------------------------------------------*
                       *  SAVE FILE * 
*------------------------------------------------------------------------------*

	save "./1_clean_surveys/2_data/round1_wave2_data", replace
	

*------------------------------------------------------------------------------*
                       *  QUICK DATA CHECKS * 
*------------------------------------------------------------------------------*

	count if enddate >= mdy(12, 23, 2023)					//Count observations for the week
	bys enum_code: count if enddate >= mdy(12, 23, 2023)	//Count calls by enumerators

	bys ugp: egen countHH = count(rc_number)
	egen utag= tag(ugp)

*	egen gp40 = tag(ugp) if countHH>=40
	egen gp50 = tag(ugp) if countHH>=50


cap log close _all
local date "`c(current_date)'"

	log using "./1_clean_surveys/3_logs/round1_wave2_`date'", replace

*	sum utag if utag == 1			//Number of unique GPs covered in survey
	sum gp50 if gp50 == 1			//Number of GPs with more than 50 HHs covered in survey
*	sum gp40 if gp40 == 1			//Number of GPs with more than 40 HHs covered in survey
	
	ta panchayat if countHH<30 		//GPs with less than 30 surveys
	
	ta sample_type
*	ta sample_type if countHH>=40	//Comparison between GPs with more than 40 HHs surveyed
	ta sample_type treatment	
	
	ta share_contact_consent, m

	sum resp_age
*	sum resp_age if countHH>=40

	tabstat heard_mnrega aware_org hh_participate_org hh_paid_dues org_name_id_spss, by(treatment)
*	tabstat heard_mnrega aware_org hh_participate_org hh_paid_dues org_name_id_spss if countHH>=40, by(treatment)
	
	tabstat appl_jobcard demand_work work_mnrega_afterholi, by(treatment)
*	tabstat appl_jobcard demand_work work_mnrega_afterholi if countHH>=40, by(treatment)
	
	tabstat hh_participate_action  other_participate_action, by(treatment)
*	tabstat hh_participate_action  other_participate_action if countHH>=40, by(treatment)

		
	//need to do this by enumerator 
	tab interest_in_sangathan
	bys enum_code: tab interest_in_sangathan
	
	tab1 workdays_future_*
	bys enum_code: tab1 workdays_future_*
	
	//Completed GPs (50 surveys complete)
	tab panchayat if gp50 == 1
	tab block if gp50 == 1
	tab district if gp50 == 1
	
log close

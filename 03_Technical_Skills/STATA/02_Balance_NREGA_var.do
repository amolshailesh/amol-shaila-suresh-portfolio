/*------------------------------------------------------------------------------
Project: Bihar NREGA Union
Purpose: Balance tables for NREGA variables
Author: Amol
Date: 6 July, 2024; Edited by Amol
Note: Input file (individual level NREGA data without UGP matching) is taken
from "Dropbox/Bihar_NREGA"
------------------------------------------------------------------------------*/

clear
set more off

cap cd "~\Dropbox\Bihar Union Research\Data_All"

*------------------------------------------------------------------------------*
						* LOAD THE DATA FILE *
*------------------------------------------------------------------------------*

	use "3_analyze_AS\0_data\BR_GP_Quarter_Year_vars.dta", clear

*------------------------------------------------------------------------------*
				* PREPARE THE DATA FOR BALANCE TABLE *
*------------------------------------------------------------------------------*

	rename (Wave1 Wave2 Treatment) (wave1 wave2 treatment)
	

/* Creating strata based on median SC population and waves */
	gen strataFE = 1 if AboveMedian == 1 & wave1 == 1
		replace strataFE = 2 if AboveMedian == 0 & wave1 == 1
		replace strataFE = 3 if AboveMedian == 1 & wave2 == 1
		replace strataFE = 4 if AboveMedian == 0 & wave2 == 1
	
	la def strataFE_l 1 "Wave1 & Above Median SC" 2 "Wave1 & Below Median SC"		///
		3 "Wave2 & Above Median SC" 4 "Wave2 & Below Median SC"
	la val strataFE strataFE_l
	
	la var strataFE			"Strata"

// Keep data of first three quarters of the year 2021, as baseline year
	keep if Year 		== 2021
	keep if Quarter 	!= 4
	count							// 380
	* 127 Sample GPs x 3 Quarters 	=  381
	* Q1 data missing for Madhopur Susta (4263)
	
// Collapse on UGP to get year-wise data, instead of quarter-wise

#delimit ;
	collapse
		(first)		Year
					PanchayatName
					BlockName 
					DistrictName 
					N_GramPanchayatName 
					N_SubDistrictName
					N_DistrictName 
					wave1 
					wave2
					strataFE
					treatment
		(mean)		total_hh_working_gp_year
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
		(count)		Quarter, by(UGP);
#delimit cr

// Rename the variable
rename Quarter NofQuarters
rename total_active_wmen_gp_year total_active_women_gp_year


// Generate some variables for balance test
g P_RequestDayCount_sc 	= RequestDayCount_q_v_sc/ RequestDayCount_q_v
g P_RequestDayCount_fem = RequestDayCount_fem_q_v/ RequestDayCount_q_v
g P_DayCount_sc 		= DayCount_q_v_sc/ DayCount_q_v
g P_DayCount_fem 		= DayCount_fem_q_v/ DayCount_q_v
*g log_PaymentReceived	= log(PaymentReceived_q_v)


// Label GP level variables
la var total_cards_gp						"Total Jobcards in GP"
la var total_cards_gp_sc					"Total Jobcards (Scheduled Castes)"
la var total_active_cards_gp_year			"Total Active Jobcards"
la var total_act_sc_cards_gp_year			"Total Active Jobcards (Scheduled Castes)"
la var total_active_women_gp_year			"Total Active Women Members"
la var total_active_SCfem_gp_year			"Total Active Women Members (Scheduled Castes)"

la var RequestDayCount_q_v 					"Total Work Days Requested"
la var RequestDayCount_q_v_sc 				"Total Work Days (Scheduled Castes) Requested"
la var RequestDayCount_fem_q_v 				"Total Work Days (Women) Requested"
la var DayCount_q_v							"Total Days Worked"
la var DayCount_q_v_sc 						"Total Days (Scheduled Castes) Worked"
la var DayCount_fem_q_v						"Total Days (Women) Worked"
la var PaymentReceived_q_v					"Total Payment Received"
la var total_hh_working_gp_year				"Total Households Worked"
la var total_hh_work100_gp_year				"Households Completed 100 Work Days"

la var P_RequestDayCount_sc					"Proportion of Work Days Requested by SCs"
la var P_RequestDayCount_fem				"Proportion of Work Days Requested by Women"
la var P_DayCount_sc						"Proportion of Days Worked by SCs"
la var P_DayCount_fem						"Proportion of Days Worked by Women"


// Save village-level Census data for sample GPs
	save "3_analyze_AS\0_data\GPSample_NREGA_Q", replace

*------------------------------------------------------------------------------*
						* RUN BALANCE TESTS *
*------------------------------------------------------------------------------*

/* Balance table (Only NREGA variables) using Niharika's code	*/

local TableCensus			1

// Save controls in a local macro
	#delimit ;
	local gpcontrols total_cards_gp total_active_cards_gp_year total_act_sc_cards_gp_year
	total_active_women_gp_year RequestDayCount_q_v P_RequestDayCount_sc total_hh_working_gp_year
	DayCount_q_v P_DayCount_sc P_DayCount_fem PaymentReceived_q_v total_hh_work100_gp_year;
	#delimit cr

    
	clear matrix
	mat table = J(24, 5,.)
	
	local row = 1
	
	foreach x in `gpcontrols'	{
	    
		qui sum `x' if treatment 	== 0, d
		mat table[`row', 1] 		= r(mean)
		
		qui sum `x' if treatment 	== 1, d
		mat table[`row', 2] 		= r(mean)
		
		areg `x' treatment, r absorb(strataFE)

		mat table[`row', 3] 		= _b[treatment]
		mat table[`row'+1, 3] 		= _se[treatment]
		
		mat table[`row', 4]			= e(N)
		
		test treatment 				= 0
		mat table[`row'+1, 5] 		= `r(p)'
			
		local row = `row'+2
		
	}

	
	#delimit;
	xml_tab table, save("3_analyze_AS\2_out\BalanceGPNREGA.xml")
		replace sheet(balance) showeq 
		cnames(	"Control" "Treatment" "Difference" "N" "Joint Test")
		rnames(	"Total Jobcards in GP" ""
				"Total Active Jobcards" ""
				"Total Active Jobcards (Scheduled Castes)" ""
				"Total Active Women Members" ""
				"Total Work Days Requested" ""
				"Proportion of Work Days Requested by SCs" ""
				"Total Households Worked" ""
				"Total Days Worked" ""
				"Proportion of Days Worked by SCs" ""
				"Proportion of Days Worked by Women" ""
				"Total Payment Received" ""
				"Households Completed 100 Work Days" ""	)
		format(N2203 N2203 N2203 N2200 N2203);
	#delimit cr
	
	
********************************************************************************

/* Balance table using balancetable command	*/

// Balance tables at GP level - All Sample
	#delimit ;
	balancetable treatment `gpcontrols' using "3_analyze_AS\2_out\BalanceGPNREGA.tex",
		vce(robust) fe(strataFE) ctitles("Control" "Treatment" "Difference") replace varlabels
		observationscolumn oneline nonumbers format(%9.2f);
	#delimit cr
	
	
// Balance tables at GP level - Wave 1
	preserve
	keep if wave1 == 1
	#delimit ;
	balancetable treatment `gpcontrols' using "3_analyze_AS\2_out\BalanceGPNREGA_W1.tex",
		vce(robust) ctitles("Control" "Treatment" "Difference") replace varlabels
		format(%9.2f);
	#delimit cr
	restore

	
// Balance tables at GP level - Wave 2
	preserve
	keep if wave2 == 1
	#delimit ;
	balancetable treatment `gpcontrols' using "3_analyze_AS\2_out\BalanceGPNREGA_W2.tex",
		vce(robust) ctitles("Control" "Treatment" "Difference") replace varlabels
		format(%9.2f);
	#delimit cr
	restore
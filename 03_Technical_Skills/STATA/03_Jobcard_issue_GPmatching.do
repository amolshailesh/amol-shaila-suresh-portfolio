/*------------------------------------------------------------------------------
Project: Bihar NREGA Union
Purpose: Matching and Merging District, Block and Panchayat names with job cards.
Created by: Amol, 20-Aug-24
Edited by: Amol, 29-Aug-24
------------------------------------------------------------------------------*/

clear
set more off 

cap cd "D:\Work\Worker Collective Action Project\0_raw_admin\NREGA_data\WebScrape\Job Card"


*------------------------------------------------------------------------------*
					* Panchayat, Block and District Codes *
*------------------------------------------------------------------------------*
// Import the file with correct codes of Panchayat, Block and Districts
	import excel "input.xlsx", clear sheet("Sheet1") firstrow
	rename H GP_name
	keep Dis_name Block_name GP_name pan_code

// Generate IDs of Panchayat	
	gen panchid_str = substr(pan_code, 5, .)
	
	destring panchid_str, gen(panchid)
	format panchid %10.0f
	
//Save the file temporarily 
	tempfile input
	save `input', replace


*------------------------------------------------------------------------------*
						* NREGA Job Card Table *
*------------------------------------------------------------------------------*
// Import the job card table data
	drop _all
	tempfile job_card
	qui save `job_card', emptyok
	foreach x in job_card missing_job_card {
		import excel using "MUZAFFARPUR/`x'.xlsx", clear firstrow
*		gen str source = "`i'.xlsx"
		append using `job_card'
		qui save `job_card', replace
	}
	
	count if job_card_no == ""							// 617 job cards missing
	count if name_head_household == ""					// 16 HH head names missing

// Separate the district, block and panchayat ids from the job card number
	gen id1 = substr(job_card_no, 4, 2)
	gen id2 = substr(job_card_no, 7, 3)
	gen id3 = substr(job_card_no, 11, 3)

	gen id0_n = 05										// Component of State ID
	tostring id0_n, gen(id0) format(%02.0f)
	drop id0_n

// Generate IDs of Panchayat, Block and District
	egen panchid_str = concat(id0 id1 id2 id3)			// Generate Panchayat ID
	gen blockid_str = substr(panchid_str, 1, 7)			// Generate Block ID
	gen distid_str = substr(panchid_str, 1, 4)			// Generate District ID
	
	destring panchid_str, gen(panchid)
	format panchid %10.0f

// Merge the District, Block and GP names using Panchayat IDs
	merge m:1 panchid using `input'
	keep if _merge == 3
	drop url address panchayat block district id1 id2 id3 id0 pan_code _merge
	
	rename Dis_name district
	rename Block_name block
	rename GP_name GP
	
// Clean GP names
	gen GP_name = subinstr(GP, "/", "", .)
	
	forval n = 0/9			{
		replace GP_name = subinstr(GP_name, "`n'", "",.)
	}

	replace GP_name = trim(upper(GP_name))

// Drop duplicate job cards
	duplicates drop job_card_no, force

// Save the file
	save "MUZAFFARPUR\intermediate\MZ_jobcard_corrected", replace


*------------------------------------------------------------------------------*
						* Merge Applicant Details *
*------------------------------------------------------------------------------*
preserve

// Import the applicant details data
	drop _all
	tempfile applicant_details
	qui save `applicant_details', emptyok
	foreach x in applicant_details missing_applicant_details {
		import excel using "MUZAFFARPUR/`x'.xlsx", clear firstrow
*		gen str source = "`i'.xlsx"
		append using `applicant_details'
		qui save `applicant_details', replace
	}
	
	count if job_card_no == ""			// 904 job cards missing
*	drop if job_card_no == ""

//Save the file temporarily
	tempfile applicant_details
	save `applicant_details', replace

restore
	
// Merge applicant details
	merge 1:m job_card_no using `applicant_details'
	
	save "MUZAFFARPUR\output\MZ_jobcard_appdetails_merged", replace

*------------------------------------------------------------------------------*
						* Append Employment Files *
*------------------------------------------------------------------------------*

						** Employment Requested **
// Import and append employment requested data
	drop _all
	tempfile employment_requested
	qui save `employment_requested', emptyok
	forvalues i = 1/4 {
		import excel using "MUZAFFARPUR\employment_requested`i'.xlsx", clear firstrow
*		gen str source = "employment_requested`i'.xlsx"
		append using `employment_requested'
		qui save `employment_requested', replace
	}
	
		import excel using "MUZAFFARPUR\missing_employment_requested.xlsx", clear firstrow
		append using `employment_requested'
		qui save `employment_requested', replace
	
	
	count if job_card_no == ""
	drop if job_card_no == ""
	
// Save the file
	save "MUZAFFARPUR\intermediate\employment_requested", replace


	
						** Employment Offered **
// Import and append employment offered data
	drop _all
	tempfile employment_offered
	qui save `employment_offered', emptyok
	forvalues i = 1/4 {
		import excel using "MUZAFFARPUR\employment_offered`i'.xlsx", clear firstrow
*		gen str source = "employment_offered`i'.xlsx"
		append using `employment_offered'
		qui save `employment_offered', replace
	}
	
		import excel using "MUZAFFARPUR\missing_employment_offered.xlsx", clear firstrow
		append using `employment_offered'
		qui save `employment_offered', replace
	
		
	count if job_card_no == ""
	drop if job_card_no == ""
	
// Save the file
	save "MUZAFFARPUR\intermediate\employment_offered", replace
	
	
	
						** Employment Given **
// Import and append employment given data
	drop _all
	tempfile employment_given
	qui save `employment_given', emptyok
	forvalues i = 1/4 {
		import excel using "MUZAFFARPUR\employment_given`i'.xlsx", clear firstrow
*		gen str source = "employment_given`i'.xlsx"
		append using `employment_given'
		qui save `employment_given', replace
	}
	
		import excel using "MUZAFFARPUR\missing_employment_given.xlsx", clear firstrow
		append using `employment_given'
		qui save `employment_given', replace
	
		
	count if job_card_no == ""
	drop if job_card_no == ""
	
// Save the file
	save "MUZAFFARPUR\intermediate\employment_given", replace	
	
	
*------------------------------------------------------------------------------*
						* Merge Employment Data *
*------------------------------------------------------------------------------*

use "MUZAFFARPUR\intermediate\MZ_jobcard_corrected", clear
preserve

// Merge job card data with employment requested
	merge 1:m job_card_no using "MUZAFFARPUR\intermediate\employment_requested"
	save "MUZAFFARPUR\output\MZ_jobcard_emprequested_merged", replace

restore, preserve
// Merge job card data with employment requested
	merge 1:m job_card_no using "MUZAFFARPUR\intermediate\employment_offered"
	save "MUZAFFARPUR\output\MZ_jobcard_empoffered_merged", replace

restore
// Merge job card data with employment requested
	merge 1:m job_card_no using "MUZAFFARPUR\intermediate\employment_given"
	save "MUZAFFARPUR\output\MZ_jobcard_empgiven_merged", replace
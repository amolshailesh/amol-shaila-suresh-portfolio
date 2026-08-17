*==============================================================================*
* 03_indices.do
*
* PURPOSE : Build indices used in estimation
*
* INPUT   : $clean/sc_recoded.dta, $clean/nonsc_recoded.dta
* OUTPUT  : $clean/sc_analysis.dta, $clean/nonsc_analysis.dta
*           $out/tab_alpha_efficacy.txt, $out/tab_attitude_pca.txt
*           $out/tab_interitem_corr_*.txt
*
* THE MEASUREMENT ARGUMENT (worth making explicitly in the dissertation)
*
*   SELF-EFFICACY is a REFLECTIVE construct. Five items are noisy indicators of
*   one underlying trait, so they should correlate highly and Cronbach's alpha
*   is a meaningful validity check. Alpha is reported for this scale only.
*
*   BACKLASH and MICROAGGRESSION exposure are FORMATIVE (causal-indicator)
*   constructs. The items are not interchangeable measurements of a latent
*   quantity; they are distinct component events that jointly CONSTITUTE the
*   phenomenon. A mukhiya can face systematic file delays and never be excluded
*   from a wedding feast. Those are different mechanisms enacted by different
*   actors, and neither is a noisy proxy for the other.
*
*   The practical implication, frequently botched in applied work: for a
*   formative index a LOW alpha is not a validity problem and a HIGH alpha is
*   not validation. Alpha measures internal consistency, which is the wrong
*   criterion when items are meant to capture non-substitutable components.
*   Reporting alpha as if it licensed these indices would be a category error.
*
*   This file therefore reports alpha for efficacy, and for the formative
*   indices reports the inter-item correlation matrix for transparency while
*   justifying aggregation on conceptual grounds.
*
* INDEX FORMULA (Kling, Liebman and Katz 2007)
*   z-score each component within the analysis sample, average the z-scores
*   over NON-MISSING components, then restandardise so the index has mean 0 and
*   SD 1 in the full sample. This handles the mixed binary/ordinal item scales
*   without pretending they share a metric.
*==============================================================================*

*==============================================================================*
* HELPER PROGRAMME: build a Kling-Liebman-Katz standardised index
*==============================================================================*
capture program drop klkindex
program define klkindex
    * Usage: klkindex newname "item1 item2 item3" "Label text"
    * Creates:
    *   <newname>       standardised index, mean 0 SD 1
    *   <newname>_n     number of non-missing components per observation
    *   <newname>_cnt   raw count of items endorsed (binary items only)
    args newvar items lbl

    tempvar sumz nz
    quietly gen double `sumz' = 0
    quietly gen byte   `nz'   = 0

    * z-score each component, accumulating sum and count of non-missing
    foreach it of local items {
        tempvar z
        quietly summarize `it'
        if r(sd) == 0 | missing(r(sd)) {
            display as error "  `it' has zero or missing SD; excluded from `newvar'."
            continue
        }
        quietly gen double `z' = (`it' - r(mean)) / r(sd)
        quietly replace `sumz' = `sumz' + `z' if !missing(`z')
        quietly replace `nz'   = `nz'   + 1   if !missing(`z')
    }

    * mean of available z-scores, then restandardise
    quietly gen double `newvar'_raw = `sumz' / `nz' if `nz' > 0
    quietly summarize `newvar'_raw
    quietly gen double `newvar' = (`newvar'_raw - r(mean)) / r(sd)
    quietly drop `newvar'_raw

    quietly gen byte `newvar'_n = `nz'

    label var `newvar'   "`lbl' (standardised index)"
    label var `newvar'_n "Items contributing to `newvar'"

    * flag observations built on fewer than half the components
    local k : word count `items'
    local half = ceil(`k' / 2)
    quietly gen byte `newvar'_thin = (`newvar'_n < `half')
    label var `newvar'_thin "Fewer than half the components present for `newvar'"

    display as txt "  Built `newvar' from `k' items: " _continue
    quietly count if `newvar'_thin == 1
    display as txt "`r(N)' observations built on <half the items."
end

capture program drop rawcount
program define rawcount
    * Simple count of binary items endorsed. This is the number to quote in
    * prose: "the median SC mukhiya reported 4 of 9 forms of backlash" is far
    * more legible to a reader than a z-score.
    args newvar items lbl
    egen `newvar' = rowtotal(`items'), missing
    egen byte `newvar'_k = rownonmiss(`items')
    label var `newvar'   "`lbl' (count of items endorsed)"
    label var `newvar'_k "Non-missing items in `newvar'"
end


*==============================================================================*
* PART A. SC SURVEY INDICES
*==============================================================================*
use "$clean/sc_recoded.dta", clear

*------------------------------------------------------------------------------*
* A1. De facto authority index (the behavioural core of "independence")
* Primary: mean of standardised task ordinals plus standardised auth_final_ord.
*------------------------------------------------------------------------------*
local authitems ""
foreach v of global AUTHTASKS {
    local authitems "`authitems' `v'_ord"
}
local authitems "`authitems' auth_final_ord"

display as txt _n "=== Building de facto authority index ==="
klkindex auth_idx "`authitems'" "De facto authority"

* Task-count version: number of the seven core functions personally performed.
* This is the descriptive measure to quote in prose.
local selfitems ""
foreach v of global AUTHTASKS {
    local selfitems "`selfitems' `v'_self"
}
egen byte auth_tasks = rowtotal(`selfitems'), missing
label var auth_tasks "Number of the 7 core functions self-executed (0-7)"

egen byte auth_tasks_k = rownonmiss(`selfitems')
label var auth_tasks_k "Non-missing authority task items"

summarize auth_idx auth_tasks, detail

*------------------------------------------------------------------------------*
* A2. Self-efficacy
*
* Five items, reflective construct, so alpha and a single dominant factor are
* the right diagnostics. If alpha < 0.70, report item-level results instead of
* an index and say why.
*------------------------------------------------------------------------------*
local effitems ""
foreach v of global EFF {
    local effitems "`effitems' `v'_n"
}

capture log close alphalog
log using "$out/tab_alpha_efficacy.txt", replace text name(alphalog)

display _n "=== SELF-EFFICACY SCALE: reliability (reflective construct) ==="
* display    "Alpha is appropriate HERE and only here. See the header of this"
* display    "do-file for why it is not reported for the backlash indices."
display _n
alpha `effitems', item std

display _n "=== Principal-factor solution: expect one dominant factor ==="
factor `effitems', pf
* eigenvalues: the first should dominate. If two factors have eigenvalue > 1,
* the scale is not unidimensional and should be reported item-level.
estat kmo

log close alphalog

* store alpha for the decision rule below
quietly alpha `effitems', std
local eff_alpha = r(alpha)
display as result "Self-efficacy standardised alpha = " %5.3f `eff_alpha'
if `eff_alpha' < 0.70 {
    display as error "ALPHA BELOW 0.70. The plan specifies: report item-level"
    display as error "results instead of an index, and state why."
}

display as txt _n "=== Building self-efficacy index ==="
klkindex eff_idx "`effitems'" "Self-efficacy"

* simple mean version for interpretability on the original 1-5 metric
egen double eff_mean = rowmean(`effitems')
label var eff_mean "Self-efficacy, mean of 5 items (1-5 scale)"

*------------------------------------------------------------------------------*
* A3. Knowledge indices
*------------------------------------------------------------------------------*
* demonstrated knowledge: share of the 4 substantive items answered correctly
egen double kn_demo_idx = rowmean(kn_15fc_c kn_cert_c kn_pmayg_c)
label var kn_demo_idx "Demonstrated knowledge: share of 4 items correct (0-1)"

* claimed awareness: share of the 2 self-report items claimed known
egen double kn_claim_idx = rowmean(kn_gramsabha_claim kn_gpdp_claim)
label var kn_claim_idx "Claimed awareness: share of 2 self-report items (0-1)"

* pooled six-item version, for comparability with the plan as written.
* NOTE this pools two different constructs; kn_demo_idx is recommended primary.
egen double kn_all_idx = rowmean(kn_15fc_c kn_cert_c kn_pmayg_c			 ///
                                 kn_gramsabha_claim kn_gpdp_claim)
label var kn_all_idx "Pooled knowledge, 6 items (mixes two constructs)"

* "not sure" rate: epistemically distinct from a wrong answer, and worth
* reporting separately. Someone who says "not sure" knows they do not know.
egen double kn_ns_rate = rowmean(kn_15fc_ns kn_cert_ns kn_pmayg_ns ///
                                 kn_gramsabha_ns kn_gpdp_ns)
label var kn_ns_rate "Share of knowledge items answered 'not sure'"

* the index used downstream
clonevar kn_idx = $kn_primary
label var kn_idx "Knowledge index used in estimation ($kn_primary)"

summarize kn_demo_idx kn_claim_idx kn_all_idx kn_ns_rate

*------------------------------------------------------------------------------*
* A4. Testing whether rights awareness a proxy for independence?
*
* This is an empirical question and EITHER ANSWER IS A FINDING.
*   Substantial correlation -> knowledge functions as a capacity channel and
*     can serve as a mediator or control.
*   Weak or null correlation -> arguably the MORE interesting result, and it
*     supports the structural account directly: a mukhiya can know exactly what
*     powers his position carries and still be unable to exercise them, which is
*     what a de jure/de facto gap MEANS.
*
* POWER CONSTRAINT: at n = 150 the smallest correlation detectable at 80% power
* is approximately r = 0.23. A null must therefore be reported as "no
* DETECTABLE association", never as "no association".
*------------------------------------------------------------------------------*
display as txt _n "=== Knowledge vs de facto authority ==="
correlate auth_idx kn_demo_idx kn_claim_idx eff_idx

* correlation with a confidence interval, via Fisher's z transformation.
quietly correlate auth_idx kn_demo_idx
local r  = r(rho)
local nn = r(N)
if `nn' > 3 {
    local zr    = 0.5 * ln((1 + `r') / (1 - `r'))       // Fisher's z
    local se    = 1 / sqrt(`nn' - 3)
    local lo_z  = `zr' - 1.96 * `se'
    local hi_z  = `zr' + 1.96 * `se'
    local lo    = (exp(2 * `lo_z') - 1) / (exp(2 * `lo_z') + 1)
    local hi    = (exp(2 * `hi_z') - 1) / (exp(2 * `hi_z') + 1)
    display as result "r(auth_idx, kn_demo_idx) = " %5.3f `r' ///
        "   95% CI [" %5.3f `lo' ", " %5.3f `hi' "]   n = `nn'"
    display as txt "MDE at n=`nn' is roughly r = 0.23; interpret a null as" ///
        " 'no detectable association'."
}

*------------------------------------------------------------------------------*
* A5. Microaggression indices, by Sue et al. subtype
*
* Built on the BINARY OCCURRENCE items, which are available for all items.
* Frequency follow-ups exist only for D1 and D3, so the frequency-weighted
* intensity index is restricted to that subset and the restriction is stated.
*------------------------------------------------------------------------------*
display as txt _n "=== Building microaggression indices ==="
klkindex ma_insult_idx  "$MA_INSULT_F"  "Microinsults (verbal)"
klkindex ma_inval_idx   "$MA_INVAL_F"   "Microinvalidations"
klkindex ma_assault_idx "$MA_ASSAULT_F" "Microassaults"

* pooled microaggression index: the primary index for hypothesis tests
local ma_all "$MA_INSULT_F $MA_INVAL_F $MA_ASSAULT_F"
klkindex ma_idx "`ma_all'" "Microaggression exposure (all subtypes)"

* raw counts for prose
rawcount ma_insult_cnt  "$MA_INSULT_F"  "Microinsults"
rawcount ma_inval_cnt   "$MA_INVAL_F"   "Microinvalidations"
rawcount ma_assault_cnt "$MA_ASSAULT_F" "Microassaults"
rawcount ma_cnt         "`ma_all'"      "Microaggressions, any type"

* frequency-weighted intensity, D1 + D3 ONLY.
* 0 if the event did not occur, 1-4 if it occurred, taking the reported frequency.
foreach v in ma_surprise ma_reserv ma_capacity ma_finance ma_flag ma_food ma_wait {
    gen byte `v'_int = 0 if `v'_b == 0
    replace  `v'_int = `v'_f_n if `v'_b == 1
    local lab : variable label `v'
    label var `v'_int "Intensity 0-4: `lab'"
}
local intitems ma_surprise_int ma_reserv_int ma_capacity_int ma_finance_int ///
               ma_flag_int ma_food_int ma_wait_int
klkindex ma_intens_idx "`intitems'" "Microaggression intensity (D1+D3 only)"

* the perception-experience gap. d4_common asks about SC mukhiyas GENERALLY;
* the binary items ask about the respondent's OWN experience. A systematic gap
* in either direction is substantively interesting; under-reporting of own
* experience relative to perceived general prevalence is a recognised pattern
* in discrimination research.
egen double ma_own_rate = rowmean(`ma_all')
label var ma_own_rate "Share of microaggression items experienced personally (0-1)"

gen double ma_perc_scaled = (ma_common_r - 1) / 3
label var ma_perc_scaled "Perceived general prevalence rescaled to 0-1"

gen double ma_gap = ma_perc_scaled - ma_own_rate
label var ma_gap "Perception minus own experience (positive = perceives more than reports)"

*------------------------------------------------------------------------------*
* A6. Backlash indices
*
* Deliberately NOT collapsed into one score. The dissertation's contribution is
* the CONTESTED MIDDLE GROUND between elite capture and physical violence, so a
* single undifferentiated "backlash score" would erase the distinction the
* project exists to make. Channel-specific profiles are the headline; the
* pooled index is secondary.
*------------------------------------------------------------------------------*
global BL_BUREAU_F  "bl_meet_b bl_files_b bl_info_b bl_hostile_b"
global BL_INTERN_F  "bl_exmukh_b bl_deputy_b bl_ward_b"
global BL_COMMUN_F  "bl_cases_b bl_organise_b"
global BL_SYMBOL_F  "bl_symbols_b bl_rights_b"
global BL_VIOLENT_F "bl_threat_b bl_violence_b"

display as txt _n "=== Building backlash indices ==="
klkindex bl_bureau_idx  "$BL_BUREAU_F"  "Bureaucratic backlash (Theme 1)"
klkindex bl_intern_idx  "$BL_INTERN_F"  "Panchayat-internal backlash (Theme 3)"
klkindex bl_commun_idx  "$BL_COMMUN_F"  "Community and elite backlash (Themes 2,3)"
klkindex bl_symbol_idx  "$BL_SYMBOL_F"  "Symbolic backlash (Theme 4)"
klkindex bl_violent_idx "$BL_VIOLENT_F" "Overt threat or violence"

* "social/elite" backlash: the community and panchayat-internal channels combined.
local bl_social "$BL_INTERN_F $BL_COMMUN_F"
klkindex bl_social_idx "`bl_social'" "Social and elite backlash"

* pooled, reported as secondary
local bl_all "$BL_BUREAU_F $BL_INTERN_F $BL_COMMUN_F $BL_SYMBOL_F $BL_VIOLENT_F"
klkindex bl_idx "`bl_all'" "Backlash exposure, all channels"

rawcount bl_bureau_cnt "$BL_BUREAU_F" "Bureaucratic backlash"
rawcount bl_social_cnt "`bl_social'"  "Social and elite backlash"
rawcount bl_cnt        "`bl_all'"     "Backlash, any channel"

* bureaucratic intensity from the E1 frequency follow-ups
foreach v in bl_meet bl_files bl_info bl_hostile {
    gen byte `v'_int = 0 if `v'_b == 0
    replace  `v'_int = `v'_f_n if `v'_b == 1
    local lab : variable label `v'
    label var `v'_int "Intensity 0-4: `lab'"
}
klkindex bl_bur_intens_idx "bl_meet_int bl_files_int bl_info_int bl_hostile_int" ///
    "Bureaucratic backlash intensity"

*------------------------------------------------------------------------------*
* A7. Victim-blaming exposure index
*------------------------------------------------------------------------------*
global VB_F "vb_assert_b vb_notforyou_b vb_stepback_b vb_fault_b"
display as txt _n "=== Building victim-blaming exposure index ==="
klkindex vb_idx "$VB_F" "Victim-blaming exposure"
rawcount vb_cnt "$VB_F" "Victim-blaming exposure"

*------------------------------------------------------------------------------*
* A8. Wellbeing index
*------------------------------------------------------------------------------*
local wbitems ""
foreach v of global WB {
    local wbitems "`wbitems' `v'_n"
}
klkindex wb_idx "`wbitems'" "Wellbeing (modified 5-point scale)"

* alpha reported for wellbeing too, since the five WHO-5-derived items are a
* reflective scale in their original validated form.
display as txt _n "=== Wellbeing scale reliability (reflective) ==="
alpha `wbitems', item std

*------------------------------------------------------------------------------*
* A9. Inter-item correlation matrices for the FORMATIVE indices
*------------------------------------------------------------------------------*
capture log close corrlog
log using "$out/tab_interitem_corr_sc.txt", replace text name(corrlog)

display _n "=================================================================="
display    " INTER-ITEM CORRELATIONS: FORMATIVE INDICES"
display    ""
display    " Reported for transparency, not as validation. These indices are"
display    " FORMATIVE: the items are distinct component events that jointly"
display    " constitute the phenomenon, not interchangeable indicators of a"
display    " latent trait. Low correlations are therefore expected and are not"
display    " a validity problem. Cronbach's alpha is deliberately NOT reported"
display    " for these scales."
display    "=================================================================="

display _n "--- Microaggression items (all subtypes) ---"
correlate $MA_INSULT_F $MA_INVAL_F $MA_ASSAULT_F

display _n "--- Backlash items (all channels) ---"
correlate $BL_BUREAU_F $BL_INTERN_F $BL_COMMUN_F $BL_SYMBOL_F $BL_VIOLENT_F

display _n "--- Victim-blaming items ---"
correlate $VB_F

display _n "--- Index intercorrelations ---"
correlate auth_idx ma_idx bl_bureau_idx bl_social_idx bl_symbol_idx vb_idx ///
          eff_idx kn_demo_idx wb_idx

log close corrlog

*------------------------------------------------------------------------------*
* A10. Save
*------------------------------------------------------------------------------*
compress
save "$clean/sc_analysis.dta", replace
display as result "Saved: $clean/sc_analysis.dta"


*==============================================================================*
* PART B. NON-SC SURVEY INDICES
*==============================================================================*
use "$clean/nonsc_recoded.dta", clear

*------------------------------------------------------------------------------*
* B1. Authority, efficacy, knowledge, wellbeing
*------------------------------------------------------------------------------*
local authitems ""
foreach v of global AUTHTASKS {
    local authitems "`authitems' `v'_ord"
}
local authitems "`authitems' auth_final_ord"
display as txt _n "=== Non-SC: building de facto authority index ==="
klkindex auth_idx "`authitems'" "De facto authority"

local selfitems ""
foreach v of global AUTHTASKS {
    local selfitems "`selfitems' `v'_self"
}
egen byte auth_tasks = rowtotal(`selfitems'), missing
label var auth_tasks "Number of the 7 core functions self-executed (0-7)"
egen byte auth_tasks_k = rownonmiss(`selfitems')
label var auth_tasks_k "Non-missing authority task items"

local effitems ""
foreach v of global EFF {
    local effitems "`effitems' `v'_n"
}
klkindex eff_idx "`effitems'" "Self-efficacy"
egen double eff_mean = rowmean(`effitems')
label var eff_mean "Self-efficacy, mean of 5 items (1-5 scale)"

display as txt _n "=== Non-SC: self-efficacy reliability ==="
alpha `effitems', item std

egen double kn_demo_idx = rowmean(kn_15fc_c kn_cert_c kn_pmayg_c)
label var kn_demo_idx "Demonstrated knowledge: share of 4 items correct (0-1)"
egen double kn_claim_idx = rowmean(kn_gramsabha_claim kn_gpdp_claim)
label var kn_claim_idx "Claimed awareness: share of 2 self-report items (0-1)"
egen double kn_all_idx = rowmean(kn_15fc_c kn_cert_c kn_pmayg_c		 ///
                                 kn_gramsabha_claim kn_gpdp_claim)
label var kn_all_idx "Pooled knowledge, 6 items (mixes two constructs)"
egen double kn_ns_rate = rowmean(kn_15fc_ns kn_cert_ns kn_pmayg_ns ///
                                 kn_gramsabha_ns kn_gpdp_ns)
label var kn_ns_rate "Share of knowledge items answered 'not sure'"
clonevar kn_idx = $kn_primary
label var kn_idx "Knowledge index used in estimation ($kn_primary)"

local wbitems ""
foreach v of global WB {
    local wbitems "`wbitems' `v'_n"
}
klkindex wb_idx "`wbitems'" "Wellbeing (modified 5-point scale)"

*------------------------------------------------------------------------------*
* B2. Attitude battery: dimensionality
*
* The plan asks whether the eleven items form one prejudice dimension or
* several, and pre-specifies that the PRIMARY moderator for the conjoint
* heterogeneity analysis is the FIRST PRINCIPAL COMPONENT. That pre-specification
* is honoured here: prej_pc1 is created regardless of what the factor structure
* turns out to be, so the moderator is not chosen after seeing the data.
*
* The rotated factor solution is reported alongside, because if a clean
* multi-factor structure emerges that is itself a finding worth reporting.
*------------------------------------------------------------------------------*
capture log close pcalog
log using "$out/tab_attitude_pca.txt", replace text name(pcalog)

display _n "=================================================================="
display    " NON-SC ATTITUDE BATTERY: DIMENSIONALITY"
display    ""
display    " att_stereo_nocaste_r enters REVERSED because agreement with"
display    " 'being a good mukhiya has nothing to do with caste' indicates LESS"
display    " prejudice, opposite in direction to every other item."
display    "=================================================================="

display _n "--- Item means and refusal rates ---"
summarize $AT_IDX
display _n "Refusal ('prefer not to say') rate per item:"
summarize att_res_bad_pns att_res_miss_pns att_res_incapable_pns att_res_hamlets_pns ///
          att_stereo_help_pns att_stereo_officials_pns att_stereo_nocaste_pns		 ///
          att_poa_unjust_pns att_poa_fake_pns att_vb_cooperate_pns att_vb_misuse_pns

display _n "--- Suitability for factor analysis ---"
* Bartlett's test of sphericity and KMO. KMO > 0.60 is usually taken as
* adequate; below that, a factor solution should be treated cautiously.
quietly factor $AT_IDX, pcf
estat kmo

display _n "--- Principal components: eigenvalues ---"
pca $AT_IDX

display _n "--- Rotated principal-component solution (varimax) ---"
* Number of retained components: Kaiser criterion (eigenvalue > 1). Inspect the
* scree plot before committing; the criterion is a rule of thumb, not a test.
pca $AT_IDX, components(3)
rotate, varimax blanks(0.30)

display _n "--- Scree plot saved to $out/fig_attitude_scree.png ---"

log close pcalog

* screeplot requires the pca estimates to be current
quietly pca $AT_IDX
screeplot, yline(1) ///
    title("Attitude battery: eigenvalues", size(medium)) ///
    note("Horizontal line at eigenvalue = 1 (Kaiser criterion)")
graph export "$out/fig_attitude_scree.png", replace width(1600)

*--- the pre-specified moderator: first principal component ---*
quietly pca $AT_IDX
predict double prej_pc1 prej_pc2 prej_pc3, score
label var prej_pc1 "Prejudice: first principal component (pre-specified moderator)"
label var prej_pc2 "Prejudice: second principal component"
label var prej_pc3 "Prejudice: third principal component"

* SIGN CONVENTION. Principal component signs are arbitrary, so the direction
* must be fixed deliberately or a heterogeneity coefficient could read
* backwards. Orient pc1 so that HIGHER = MORE PREJUDICED by anchoring on
* att_res_incapable ("SC mukhiyas elected through reservation are usually not
* capable"), which is unambiguously prejudicial.
quietly correlate prej_pc1 att_res_incapable_n
if r(rho) < 0 {
    replace prej_pc1 = -prej_pc1
    display as txt "prej_pc1 sign flipped so that higher = more prejudiced."
}
quietly summarize prej_pc1
replace prej_pc1 = (prej_pc1 - r(mean)) / r(sd)
label var prej_pc1 "Prejudice index, standardised (higher = more prejudiced)"

* simple additive alternative, reported as a robustness moderator. Being on the
* raw 1-5 metric it is easier to describe in prose than a component score.
egen double prej_mean = rowmean($AT_IDX)
label var prej_mean "Attitude battery mean, 1-5 (higher = more prejudiced)"
quietly summarize prej_mean
gen double prej_z = (prej_mean - r(mean)) / r(sd)
label var prej_z "Attitude battery mean, standardised"

display as txt _n "=== Correlation of the two prejudice measures ==="
correlate prej_pc1 prej_z

*--- cluster sub-indices, for the item-cluster reporting in the tables ---*
klkindex at_res_idx "att_res_bad_n att_res_miss_n att_res_incapable_n att_res_hamlets_n" ///
						"Anti-reservation attitudes"
* at_reshamlet_n
    
klkindex at_stereo_idx "att_stereo_help_n att_stereo_officials_n att_stereo_nocaste_r" ///
    "Capability stereotypes"
klkindex at_poa_idx    "att_poa_unjust_n att_poa_fake_n" ///
    "Attitudes to the SC/ST Atrocities Act"
klkindex at_vb_idx     "att_vb_cooperate_n att_vb_misuse_n" ///
    "Victim-blaming endorsement"

	
*------------------------------------------------------------------------------*
* B3. Inter-item correlations
*------------------------------------------------------------------------------*
capture log close corrlogns
log using "$out/tab_interitem_corr_nonsc.txt", replace text name(corrlogns)
display _n "--- Attitude item correlations ---"
correlate $AT_IDX
display _n "--- Index intercorrelations ---"
correlate auth_idx eff_idx kn_demo_idx wb_idx prej_pc1 at_res_idx ///
          at_stereo_idx at_poa_idx at_vb_idx
log close corrlogns

*------------------------------------------------------------------------------*
* B4. Save
*------------------------------------------------------------------------------*
compress
save "$clean/nonsc_analysis.dta", replace
display as result "Saved: $clean/nonsc_analysis.dta"

display as result _n "=== 03_indices.do complete ==="
display as txt "Alpha (efficacy only): $out/tab_alpha_efficacy.txt"
display as txt "Attitude PCA:          $out/tab_attitude_pca.txt"
display as txt "Inter-item matrices:   $out/tab_interitem_corr_*.txt"

*==============================================================================*
* END 03_indices.do
*==============================================================================*

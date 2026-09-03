# Stata analysis pipeline

Backlash against independently acting Scheduled Caste mukhiyas in Bihar.
Quantitative arm: SC survey and non-SC survey.

Built against `Data_Analysis_Plan_SC_NonSC_Mukhiya_Surveys.md`,
`Variable_Rename_Labels_SC_NonSC.md`, and the two deployed XLSForms.

---

## File order

| File | Purpose | Key output |
|---|---|---|
| `00_master.do` | Paths, parameters, analytical decisions, run switches | — |
| `01_import_merge.do` | Import Kobo exports, rename, label, merge BSEC frame | `sc_named`, `nonsc_named`, `*_merged` |
| `02_clean_recode.do` | Recode table: reversals, PNS handling, ordinals | `*_recoded`, `qc_recode_check_*.txt` |
| `03_indices.do` | Indices, alpha for efficacy, PCA for attitudes | `*_analysis`, `tab_alpha_efficacy.txt` |
| `04_qc_paradata.do` | QC, refusal rates, enumerator variance, non-response | `qc_report.txt` |
| `05_desc_sc.do` | De jure/de facto gap; prevalence with Wilson CIs and Manski bounds | `prevalence_estimates.dta` |
| `06_assoc_sc.do` | Specification ladder, reverse specification, FDR appendix | `tab_assoc_*` |
| `07_conjoint_reshape.do` | Two-step wide→long, randomisation diagnostics | `conjoint_long.dta` |
| `08_conjoint_amce.do` | AMCEs, marginal means, the central interaction, heterogeneity | `tab_amce_*` |
| `09_alloc.do` | Allocation reshape, respondent FE, two-part model, Wilcoxon | `alloc_long.dta` |
| `10_compare.do` | SC vs non-SC, stereotype refutation, joint display | `pooled_analysis.dta` |
| `11_power.do` | Realised MDEs including conjoint simulation | `tab_power_realised.txt` |
| `12_tables_figures.do` | Final numbered exhibits | `EXHIBIT_*` |

Run `00_master.do` only. The numbered files assume its globals are in memory.

---

## Before the first run

1. **Edit section 1 of `00_master.do`** — every path and the four input filenames.
2. **Edit section 4a** — the four knowledge-index correct answers. All are
   placeholders. See "Open decisions" below.
3. **Export Kobo without group headers.** With headers on, every variable arrives
   prefixed with its group path and no rename in `01` will match.
4. **Install** `estout`, `coefplot`, `reghdfe`, `ftools` from SSC. Every use is
   guarded with `capture which`, and official-Stata fallbacks run where one
   exists, so the pipeline completes without them — but tables will not export.

## After `02_clean_recode.do`

Read `$out/qc_recode_check_sc.txt` and `qc_recode_check_nonsc.txt` in full.
Every reversal is cross-tabulated raw against recoded. A reversal error produces
perfectly plausible output and will not announce itself anywhere else in the
pipeline.

## After `04_qc_paradata.do`

Three switches in `00_master.do` can only be set from that report:

- `use_block_cluster` — from the panchayats-per-block distribution (A1.2)
- `use_district_fe` — from district coverage (A1.2)
- `speed_min` — from the realised duration distribution (A4)

---

## Things found in the forms that differ from the analysis plan

**1. The allocation module is not a shared budget.** Each `e_alloc_slot*` is an
independent 0–100,000 range with no cross-slot constraint, and the Hindi hint
instructs the respondent explicitly not to subtract amounts already spent. So
these are four independent willingness-to-spend measures, each out of a fresh
₹1,00,000. The four amounts can legitimately sum to more than ₹1,00,000.

Consequences: do not describe this as a budget allocation or compute shares of a
shared budget. The plan's §7.3 "allocation as share of budget (0–1)" is
implemented as a rescaling of each independent measure by 100,000, which is fine,
but the write-up language must be "amount, rescaled". The within-respondent DiD
(β₃) is unaffected and remains cleanly identified.

**2. Two of the six knowledge items cannot be scored correct or incorrect.**
`ra_gramsabha` ("Do you know whether the mukhiya has authority to call a Gram
Sabha on their own?") and `ra_gpdp` ("Do you know what a GPDP is?") are
self-reported awareness. Neither asks the respondent to state the answer, so
neither has answer content to score. The plan's instruction to score each item
correct/incorrect/not-sure is not applicable to these two.

`03_indices.do` therefore builds three measures — `kn_demo_idx` (4 substantive
items), `kn_claim_idx` (2 self-report items), and `kn_all_idx` (all six pooled) —
and `$kn_primary` selects which is used downstream. Default is `kn_demo_idx`.

This matters for the stereotype-refutation argument in §8.2, which rests on SC
and non-SC mukhiyas scoring comparably on knowledge. That comparison is stronger
on demonstrated knowledge than on claimed awareness, since a claim to know is
itself susceptible to the confidence differences the argument is trying to hold
constant.

**3. String import.** Any Kobo choice list containing a non-numeric value forces
the whole column to string. Two lists do this: `yesnopns` (all SC modules D, E,
F) and `likert_agree_pns` (non-SC module C). So the attitude Likert items arrive
as strings like `"4"` and `"prefer_not"`. `02_clean_recode.do` handles this with
the `pnsbinary` and `pnslikert` helper programmes; anything that treats those
columns as numeric without conversion will silently produce missing values.

---

## Open decisions, flagged rather than made

**Knowledge-index correct answers (`00_master.do` §4a).** All four defaults are
placeholders that make the code run. Each depends on a Bihar administrative fact
I cannot verify:

- `kn_pmayg_correct` — set to `survey_gs`. The plan expresses confidence here.
- `kn_cert_correct` — set to `secretary`. Verify against current Bihar practice
  for birth and death registration at panchayat level; the responsibility has
  changed over time.
- `kn_15fc_correct` — set to `both`. Both tied and untied components exist under
  the 15th Finance Commission, so `both` is arguably most accurate, but this is
  a coding decision you should document rather than inherit.
- `kn_commit_correct` — set to 6. Verify the statutory number in the Bihar
  Panchayat Raj Act.

These determine every knowledge-index score, so they should rest on the statute
rather than on anyone's recollection.

**Frame variables (`01_import_merge.do` part C1).** The keeplist assumes your
frame holds `uid strata district block gp sample_group`. If it also holds the
seat reservation category, add it: frame-recorded reservation is a better control
than self-reported `gp_scshare` for the reservation confound in §8.3, because it
is measured independently of the survey and is the actual assignment variable.

**Enumerator identification (§1.2 of the plan).** Neither form has an `enum_id`
field. `username` records the device or account, not the interviewer. If
enumerators shared accounts, enumerator effects are unidentifiable, and
interviewer effects on sensitive caste items are typically large. `04` runs an
account-level variance decomposition and labels it as such. If you can get a
call-level assignment log from CKSingh keyed to `uid`, there is a commented merge
block ready for it.

**Conjoint caste reference (`00_master.do` §4e).** Default is `yadav`, as the
more locally meaningful comparison given Yadav prominence in the qualitative
data. `08` runs `rajput` automatically as a robustness column.

**`ma_slur` taxonomy placement (`00_master.do` §4c).** Default reassigns it to
the microassault index, since a caste slur is overt and explicitly derogatory
rather than a dismissal. The instrument placed it in the D2 microinvalidation
block. Set `slur_as_assault 0` to follow the instrument instead; either way,
footnote the discrepancy.

---

## Reproducibility

Every stochastic procedure sorts on a unique key before the random draw. The
lesson from the sampling do-file applies throughout: a non-deterministic sort
order before the RNG, not the seed, is what makes results move between runs.

- `07_conjoint_reshape.do` builds `taskid` with `egen group()` on a sorted key
  rather than `_n`, because `_n` depends on the current sort order.
- `11_power.do` sorts on `uid task profile` before `set seed $seed`.

---

## Statistical choices worth knowing about

**Wilson rather than normal-approximation CIs** for every proportion. Several
items will have prevalence near 0 or 1, where the normal approximation can
produce bounds outside [0,1].

**Alpha reported only for self-efficacy and wellbeing.** Those are reflective
scales. The backlash and microaggression indices are formative: the items are
distinct component events that jointly constitute the phenomenon, not
interchangeable indicators of a latent trait. For a formative index a low alpha
is not a validity problem and a high alpha is not validation. `03` reports
inter-item correlation matrices for transparency instead, with the reasoning
printed in the output header.

**Benjamini–Hochberg computed by hand** in `06`, so there is no package to
verify and the arithmetic is inspectable. The plan mentions Anderson's sharpened
two-stage procedure, which is more powerful; that is a different algorithm and I
have not implemented it, because I would be coding a procedure I cannot check
against the source. If you want it, verify the exact algorithm against the paper
first.

**Two-part model rather than Tobit** for the allocation outcome. Tobit assumes a
latent continuous variable censored at zero; here zero is a genuine preferred
allocation, not a suppressed negative one. Tobit is reported in `09` §5.4 for
completeness and labelled as not preferred.

**LPM primary, logit as a functional-form check** throughout the conjoint. LPM
coefficients read directly as percentage-point changes, which is what a conjoint
is for.

---

## Citations flagged for verification

I have not invented any source, but verify details before citing:

- Hainmueller, Hopkins & Yamamoto (2014), *Political Analysis* — conjoint AMCE
  estimation. Confident it exists and is correctly attributed; verify the
  specification details.
- Kling, Liebman & Katz (2007), *Econometrica* — standardised index construction.
- Anderson (2008), *JASA* — sharpened two-stage FDR q-values.
- Creswell & Plano Clark — mixed-methods typology and notation. Edition varies;
  the typology is stable across editions but page references are not.
- Leeper, Hobolt & Tilley, *Political Analysis* — marginal means for conjoint
  subgroup comparison. **I am not confident of the exact year and title. Confirm
  before citing.**
- Sue et al. (2007), *American Psychologist* — microaggression taxonomy. Already
  in your bibliography.

For `ci proportions ..., wilson`: the command was introduced in Stata 14 and the
option set has been stable, but confirm against your version's help file rather
than assuming.

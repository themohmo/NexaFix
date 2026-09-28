# NexaFix Costing Engine: Estimating Pain Points, Hidden Costs, Margins and UAE Rules

Research date: 2026-09-28. Scope: residential/light-commercial furnishing, joinery and fit-out in Dubai.
Source tags like [S3] map to the list at the end. **"estimate"** marks our own figures, which were not found in a source. Verify them against NexaFix's own supplier and job data.

---

## 1. Pain points: what is slow, what gets forgotten, what loses money

### 1.1 Quantity take-off and rounding errors
| Pain point | What goes wrong | Engine rule |
|---|---|---|
| **Rounding sheets up per item** | 5 small items each need 0.3 of an 18 mm MR-MDF sheet. Rounding each item up gives 5 sheets. Pooling gives ceil(1.5 x 1.12 waste) = **2 sheets**. Padding every item this way over-prices joinery and loses bids. Cut-list vendors report that "pad factor; extra sheets parked" wastes about 2 carcass sheets plus 1 door sheet per job [S9]. | Pool sheet demand at project level by **material + thickness + colour/finish**. Apply the yield/waste factor once, then round up once. Only round up per item for one-off finishes that cannot share a sheet. |
| **Waste factors missing or double-counted** | Sheet goods need 10-15%, hardwood/veneer 15-20% and consumables about 5% [S5][S7]. SPC straight lay needs 5-7% and herringbone 15-20% [S20]. Tiles need 5-7% in square rooms, 10% in rectangles and 15% in rooms with angles or diagonal lay [S20]. | Store waste per material and per layout pattern. Apply it once, before pack rounding. |
| **Pack/box rounding** | SPC comes in boxes of about 2.2 m² [S20]. Tiles come by the box, LED strip in 5 m reels, WPC fluted panels as 160 x 2900 mm pieces (0.46 m²) [S21], and PVC marble sheets as 1220 x 2800 mm [S21]. | Pool **same-SKU** flooring across rooms and round up once, plus 1 spare box per SKU as attic stock (estimate). For cladding, round up **per wall**: offcuts shorter than the wall height can't be reused, and marble sheets need pattern or book-matching. Each material needs a `pooling_rule`: project, room or wall. |
| **Edge banding under-counted** | This is the most under-estimated joinery material. Shelves get added, end panels become visible and fillers show, so estimates made per cabinet rather than per panel run short [S6]. | Calculate edge banding in metres from the visible edges of each panel, plus 10% trim waste (estimate). |
| **Small stuff forgotten** | Shops price the boards correctly but forget screws, glue, edge band, silicone, masking tape and sandpaper [S6][S5]. | Add a consumables allowance of 3-5% of material cost [S5]. Always generate a hardware line: hinges per door by height (typically 2 up to 900 mm, 3 up to 1600 mm, 4 up to 2200 mm; estimate from common hinge-maker guidance), runners per drawer, handles, and hanging rails. |
| **LED under-specified** | The strip gets priced but the driver, aluminium profile, diffuser, end caps, connectors, cable, dimmer/sensor and **driver access** do not. Drivers must be sized with 20% headroom: W/m x m x 1.2, then rounded up to a standard size (30/40/50/60/75/100/150/200/240/300 W) [S10]. | Size drivers automatically per circuit or zone. Split long runs to limit voltage drop (roughly 5 m for 12 V and 10 m for 24 V per feed; estimate). Add an access panel wherever a driver sits in the ceiling. |
| **Gypsum ceiling add-ons** | Access panels for FCUs and valves, relocating sprinkler heads and smoke detectors (usually by the building's approved fire-safety contractor), AC grille modifications, and MR board in wet areas. Painting is normally **not** in the gypsum rate. Cove lighting adds gypsum, LED and paint together [S19]. | Generate child lines automatically from a "gypsum ceiling" parent. |
| **Socket points priced as "a point"** | A point price hides the back box, cable run length, faceplate brand, chasing and making good, and whether a **new circuit or DB way** is needed (which may need DEWA involvement, see section 5). | Price each point as base + per-metre run. Set a flag for a new circuit. |

### 1.2 Labour
- **Installation takes longer than planned.** Builds commonly take **30% more hours** than estimated [S8]. The usual causes are walls out of plumb, scribing, fillers and difficult access [S5][S15].
- **Tower logistics eat productive time.** Crews wait for the service lift, carry material from the loading bay, lay protection and clean up daily. Plan on about 6 productive hours out of 8 in a tower (estimate). Ramadan days are 6 hours [S16], and non-air-conditioned sites in summer lose 20-25% productivity [S17].
- **Fabrication and installation are mixed together.** Estimate them separately: workshop hours at the shop rate, site hours at the site rate, plus travel.
- **True labour cost is understated.** A fully loaded worker costs 1.3-1.5x base wage [S5]. In the UAE, accommodation, transport, health insurance and gratuity add 15-20% on top of base wage [S17], and visa costs come on top of that. Overtime is +25%, or +50% between 10 pm and 4 am, with a maximum of 2 hours a day [S16]. After-hours or weekend work in premium towers raises labour cost by 10-25% [S18].

### 1.3 Commercial and process losses
- **Variation orders go unbilled.** Extra work requested verbally never gets invoiced [S8]. Change orders after design freeze add 5-30% [S18]. UAE lawyers advise against proceeding on verbal instructions and recommend fixing how variations are valued in the contract [S14].
- **Stale price lists.** Templates aren't updated when material prices rise [S8]. Update at least quarterly, preferably monthly [S5]. UAE material categories rose 12-18% [S22]. Diesel went from AED 2.72 to 4.69/litre (+72%) after the regional conflict, and suppliers are shortening how long their quotes stay valid [S23].
- **Rework and snagging** have no budget. Reserve 1-2% of project value for warranty work and callbacks [S5]. UAE contracts usually carry a 12-month defects liability period [S14].
- **Cash flow.** A typical Dubai carpentry schedule is 50% on order, 40% before delivery and 10% on completion, with quotes valid 30 days [S12]. Office fit-outs often run 20/40/30/10 [S11]. B2B jobs often hold 10% retention: 5% released at completion and 5% after the 12-month DLP [S14]. VAT is due when an advance is received, not when the work is done [S13].
- **Minimum charges.** One mirror or one socket still costs a truck trip (AED 300-500) plus a 2-person crew [S24]. Use a minimum line value or a "mobilisation per visit" line (estimate: AED 350-600 per visit).
- **Quoting from the client's floor plan instead of a site survey.** Flag the quote as "subject to site measurement" and hold a risk allowance until the survey is done.
- **Design work given away.** Drawings, 3D renders and shop drawings often aren't charged [S15].
- **Markup/margin confusion.** See section 3.
- **Speed.** Spreadsheet estimates break on one bad formula, suffer version chaos and need manual re-pricing on every revision [S25]. That limits how many quotes a small firm can turn around.

---

## 2. Hidden / commonly-missed project-level lines (preliminaries checklist)

| # | Line | Basis | Typical UAE figure | Source |
|---|---|---|---|---|
| 1 | Building/community NOC admin fee | Lump sum; usually passed to the client | AED 0-5,000. Emaar about 1,000-5,000, Nakheel 2,000-5,000, DAMAC 1,000-2,500, Meraas minor works free | [S1] |
| 2 | Refundable security deposit | Cash-flow item; damage can be deducted | AED 2,000-20,000; must be reclaimed within 2 years or it is forfeited | [S1][S2] |
| 3 | Authority fit-out permit | Per area or lump sum | DDA: AED 0.90/ft² (min 200, max 10,000) + AED 20. DM: AED 500-3,500. Trakhees: per project | [S1][S3] |
| 4 | NOC drawings / MEP layouts | Lump sum | AED 2,500-15,000 for larger scopes. Simple apartment: AED 500-2,500 (estimate) | [S1] |
| 5 | Insurance (public liability, usually min. AED 1M; CAR) | % of contract or overhead | Per-project CAR about 0.2-0.5% of contract (estimate) | [S4] |
| 6 | Site protection (floor, lift, corridor, dust sheeting) | Per m² + lump sum | PP sheet 0.9 x 2 m x 3 mm = AED 15 (about AED 8/m² material). Installed about AED 10-20/m² (estimate) + lift padding | [S26][S4] |
| 7 | Protection of finished work (SPC before joinery goes in, cladding) | Per m² | As above; this is often forgotten entirely | estimate |
| 8 | Transport / delivery trips | Per trip | 3-ton pickup AED 300-500/trip; loading crew AED 150-500/hr | [S24] |
| 9 | Debris disposal / skip | Per skip or per bag trip | Skip AED 520-3,300; small jobs from AED 300; 5 CBM typical for small renovations; landfill AED 100/tonne. Towers often require bagged debris taken down through the service lift | [S27] |
| 10 | Packaging removal (loose-furniture cartons) | Per trip | 1 extra pickup trip per furniture delivery (estimate) | estimate |
| 11 | Building on-floor cleaning / waste charges | Lump sum | Charged by the building; varies | [S28] |
| 12 | Final / post-construction cleaning | Per unit or per hour | Apartment deep clean AED 300-1,600. Post-construction AED 45/hr per cleaner, 4-hour minimum. Commercial AED 2.5-5/ft² | [S29] |
| 13 | Supervision / PM | % of direct cost | 5-8% of direct cost for small residential (estimate) | estimate |
| 14 | Consumables | % of material | 3-5% | [S5] |
| 15 | Design, 3D, shop drawings | Lump sum or % | 3-5% or AED 1,500-5,000 (estimate) | estimate |
| 16 | Fire-safety device relocation, access panels, AC grille changes | Per item | Sprinkler/detector relocation AED 150-400 each via the building's contractor. Access panel AED 150-350 (estimate) | estimate |
| 17 | Electrical approval (new circuits or DB changes) | Lump sum | Licensed contractor + possible DEWA review; 3-7 working days | [S30] |
| 18 | After-hours / weekend premium | % of labour | +10-25% | [S18] |
| 19 | Parking, Salik, access cards, gate passes | Per day or per card | AED 50-150/day per van in Downtown or Marina towers; access cards AED 50-200 (estimate) | estimate |
| 20 | Warranty / snagging reserve | % of sell | 1-2% | [S5] |
| 21 | Contingency | % of cost | 5-10% for a new/vacant unit. 10-15% is standard UAE practice [S31]. 15-20% for older or occupied buildings [S18] | [S31][S18] |
| 22 | Price escalation (quotes valid over 30 days, imported items) | % of material | 2-5% (estimate) or an escalation clause | [S23] |
| 23 | Financing cost of the payment schedule | % | 1-2% when the schedule is back-loaded (estimate) | estimate |

Benchmark: Turner & Townsend puts Dubai preliminaries at **12% (small projects, 2,500 m²)** and **14% (large projects)** [S31]. For a single-apartment furnishing job, prelims typically land at **5-10% of direct cost** (estimate).

---

## 3. Margins, markup vs margin, and pricing units

### 3.1 Norms
- **UAE contractors (Turner & Townsend 2025):** OH&P is 12% on small Dubai projects and 10% on large ones. Profit on mid-to-large projects is 8-12%. Tender price inflation was 3.3% in 2025 [S31]. These are construction-contractor figures; bespoke residential work carries more.
- **Joinery workshops:** most sustainable workshops aim for 15-25% gross margin on top of a break-even hourly rate [S15]. Cabinetry pricing guides target 10-30%, with 20% as a baseline, plus 5-10% contingency for high-risk jobs [S5].
- **Cabinet shop P&L (practitioners) [S32]:**
  - materials 30-42% of sales (one long-run average: 38.7%)
  - labour 18-34%
  - overhead 13.5-24.5%
  - net profit 10-30%
  - one rule of thumb is "1/3 materials, 1/3 labour, 1/6 overhead, 1/6 profit"
- **Old shop rule:** "Triple the material cost and add 10%" [S33]. It's crude, but useful as a sanity check.
- **Labour/material mix:** a basic kitchen is about 2/3 labour and 1/3 material. High-end inset work is about 3/4 labour [S34].
- **NexaFix-type B2C Dubai furnishing:**
  - in-house joinery: aim for a **30-40% gross margin**
  - subcontracted trades (gypsum, electrical, paint): **15-25% markup**
  - loose furniture and curtains resold: **20-35% markup**
  - all four figures are estimates to calibrate against actual jobs

### 3.2 Formulas and worked example
```
Markup  = (Sell - Cost) / Cost          Sell = Cost x (1 + Markup)
Margin  = (Sell - Cost) / Sell          Sell = Cost / (1 - Margin)
Margin  = Markup / (1 + Markup)         Markup = Margin / (1 - Margin)
```
| Target margin | Markup needed |
|---|---|
| 15% | 17.6% |
| 20% | 25.0% |
| 25% | 33.3% |
| 30% | 42.9% |
| 35% | 53.8% |
| 40% | 66.7% |

A 25% markup gives a 20% margin [S35].

**Worked example (AED):**

1. Direct cost (materials + labour + subcontract + prelims) = **40,000**
2. Add overhead recovery at 15% → **46,000**
3. Add contingency at 5% → **48,300** (break-even cost)
4. Apply a 25% margin correctly: 48,300 / 0.75 = **64,400** sell. Profit is 16,100.
5. The same target applied wrongly as a 25% markup: 48,300 x 1.25 = 60,375. The real margin is then 20%, and **AED 4,025 is lost** on one job.
6. Add VAT at 5% on 64,400 = 3,220 → **client total 67,620**.

Discounts compound the damage. A 10% discount on a 25% margin removes 40% of the profit.

### 3.3 Pricing units used in the trade
| Unit | Typical items |
|---|---|
| **per m²** | SPC, tiles, gypsum ceilings and partitions, painting, wall cladding, wallpaper. Wardrobes are often priced per m² of front elevation (estimate) |
| **per linear metre** | Cove/bulkhead (about AED 150/rm with a light provision [S19]), LED strip, skirting, curtain track, countertops, base units |
| **per point** | Sockets, light points, data |
| **per piece / lump sum** | TV units, mirrors, headboards, vanities, dressers, loose furniture |

Practitioners warn that per-linear-foot pricing works for repetitive production but fails for bespoke work [S15]. It also hides variation: a 2-door cabinet and a 6-drawer cabinet of the same width cost very differently [S36].

**Best practice:** build the cost bottom-up (parts, hardware, hours) and present it to the client in the units they understand. Separate lines for drawers, doors and accessories keep the unit rate honest [S36].

---

## 4. Best-practice estimate structure

**Cost build-up (internal):**
```
 1 Direct materials   = sum(qty x (1 + waste), then pack-rounded) x unit cost + freight-in
 2 Direct labour      = fabrication hrs x shop rate + install hrs x site rate + travel
                        (fully loaded; shop rate = overhead/hr + labour cost/hr [S15])
 3 Subcontract        = quotes + 5-10% attendance/coordination (estimate)
 4 Preliminaries      = section 2 checklist
 = PRIME COST
 5 Overhead recovery  = % of prime cost or per labour hour
                        (annual overhead / productive hours) [S5]
 6 Contingency        = set by risk (survey done? occupied? old building?)
 = BREAK-EVEN
 7 Profit             = by target MARGIN per category (joinery / subcontract / resale)
 = SELL (ex VAT)  -> round per line; apply minimum charge per line/visit
 8 VAT 5%             = on the sell total
 = CLIENT TOTAL
```

**The internal cost sheet should show:**
- Every line's raw quantity, waste %, rounded purchase quantity (with pack size) and unit cost
- The supplier and the **price date** for each cost
- Labour hours split by trade and by workshop vs site
- Subcontract quotes
- Each preliminaries item
- Overhead, contingency and margin at line, section and project level
- Blended margin, plus a warning when any line falls below the floor margin
- The cash-flow curve against the payment schedule
- Assumptions and risk flags, e.g. "from plan, not surveyed" and "new circuit"
- The quote version and a variation log

**The client quote should show:**
- Company details and TRN, with a "Quotation" (not tax invoice) heading
- Items grouped **by room**, with specs: material, thickness, finish or colour code, brand, hardware grade
- Quantity, unit, all-in unit rate and line total
- Subtotal, then any discount, then VAT at 5%, then the grand total
- **Validity** (14-30 days; 30 is common [S12])
- **Payment terms** (e.g. 50/40/10 [S12]) and lead time
- **Inclusions and exclusions.** Examples: NOC fees and deposits (client or NexaFix), DEWA or civil work, AC and sprinkler work, and prime-cost allowances for client-chosen items such as fabric and loose furniture
- "Measurements subject to site survey"
- Warranty and DLP, and the variation procedure (written approval, priced before starting)
- Cancellation terms. Custom items can't be cancelled once production starts; one Dubai firm charges a restocking fee of up to 50% [S12]

**Never show on the client quote:** cost, margin, contingency, waste %, or supplier names and prices.

Preliminaries can either be spread into the unit rates or shown as one "General & site preliminaries" line. UAE BOQs commonly show them separately. Keep a separate line when the client may remove items, so that fixed costs don't disappear with them.

---

## 5. Dubai / UAE-specific considerations

**Working time**
- **Building hours** are usually **8 am-6 pm on weekdays**, with limited Saturday work and no Sunday work in most towers. Heavy or noisy work often has tighter windows, such as 9 am-5 pm [S4].
- **DM noise rules** permit construction noise roughly 7 am-8 pm. Noisy work on Fridays and public holidays is restricted [S37].
- The **federal weekend** is Sat-Sun, with a Friday half-day for government since 2022. Fit-out crews usually work 6 days a week, and site time on Friday is cut by the prayer break (estimate).
- **Summer midday break:** from 15 June to 15 September, outdoor work is banned from 12:30 to 15:00. The fine is AED 5,000 per worker, up to AED 50,000 [S38]. It affects outdoor loading, deliveries and villa exteriors. Indoor sites without AC lose 20-25% productivity [S17].
- **Ramadan:** the private sector works 6-hour days, so capacity drops by 25% [S16]. Add Eid closures as well. The scheduler needs to know the calendar.

**Logistics**
- **Service lifts** must be pre-booked through building management within approved hours [S4].
- **Check lift cabin dimensions against the longest part.** Cladding pieces are 2.8-2.9 m and boards 2.44 m. Design wardrobes and TV units as knock-down modules, and flag any part longer than the lift cabin (estimate/practice).
- **Protection** is required from the unit entrance to the work area, including lift padding and dust sheeting [S4].

**Approvals and timelines**
- Building NOC: same day to about 2 weeks for non-structural work (3-10 working days typical) [S1][S4]
- DDA permit: 2 working days, valid 6 months [S3]
- DM permit: 3-10 working days. Trakhees permit: 7-14 days [S1]
- End-to-end approvals: about 3-5 weeks [S1]. Build this into programme and quote validity.
- Jurisdiction depends on location:
  - DM: mainland
  - DDA: TECOM-type zones
  - Trakhees: Nakheel/PCFC areas
  - DMCC: JLT
  - verify per plot
- Working without approval risks fines of up to AED 50,000 and a stop-work order [S1].

**Electrical and fire safety**
- Adding a socket on an existing circuit usually needs only the building NOC [S30].
- New circuits, DB modifications or load increases need a **DEWA-approved contractor** and may need DEWA approval (3-7 working days) [S30][S39].
- Relocating sprinklers or detectors goes through the building's fire-safety contractor, with Civil Defence rules applying [S3].

**Materials for humidity and heat**
- Vanities, kitchens and laundries: **HMR/MR-MDF**. Areas with direct wetting: marine ply (AED 90-185/sheet) [S40][S22].
- Wet areas: MR gypsum board.
- Vacant units with the AC off in summer can see SPC swell or lock failure and veneer movement. Specify acclimatisation and expansion gaps (estimate/practice).
- Sun-facing glazing: use UV-stable or lined curtains.

**Tax and money**
- **VAT** is 5%. Registration is mandatory above AED 375,000 turnover [S13].
- Tax invoices need the TRN and a VAT breakdown, and must be issued within 14 days of supply.
- VAT falls due at the earliest of payment, invoice or supply, so **advances trigger VAT** [S13].
- An e-invoicing mandate is phasing in; confirm the timeline for NexaFix [S13].
- The AED is pegged to the USD at 3.6725, but EUR/TRY/CNY-sourced finishes carry currency risk (estimate).

**Commercial**
- Retention is 10% (5% released at completion, 5% after the DLP). The DLP is typically 12 months [S14].
- Warranty inspection windows can be short: one firm allows 48 hours to report defects [S12].

---

## Sources
- [S1] bestimate.ae/blog/dubai-renovation-permit-noc-guide
- [S2] joinoliva.com glossary "fit-out NOC"; daralnaseeb.com NOC villa guide 2026
- [S3] dda.gov.ae/en/planning-development/construction/permits-nocs/fit-out-permit
- [S4] wefixall.ae/renovation-approval-process-dubai-apartments
- [S5] acrual.com/blog/pricing-cabinetry-for-profitability
- [S6] Search summary of cabinet estimating guides: hitechcaddservices.com, bertastore.com edge-banding calculator
- [S7] joinerycore.com/blog/how-to-price-joinery-work.html (waste factors)
- [S8] joinerycore.com/blog/cabinet-shop-job-costing-software.html
- [S9] cutlistor.com/blog/cut-list-optimization-cabinet-shop-profit
- [S10] superlightingled.com LED power calculator; kayva.sg driver sizing guide
- [S11] interiorsfitout.com/how-much-does-office-fit-out-cost-dubai
- [S12] karnakcarpentry.com/terms-and-conditions
- [S13] cleartax.com/ae/vat-in-uae; tallysolutions.com/mena/uae-vat/vat-construction-contracts-progress-billing
- [S14] chambers.com "Retentions in UAE construction contracts"; ayshamslaw.com DLP article
- [S15] joinerycore.com/blog/how-to-price-joinery-work.html
- [S16] wionews.com Ramadan 2026 hours; uaeahead.com UAE labour law working hours (Decree-Law 33/2021)
- [S17] capitalassociated.com/blog/construction-labour-costs-and-workforce-in-dubai
- [S18] radyinterior.ae/renovation-costs-dubai-hidden-fees-budget
- [S19] bestimate.ae/blog/false-ceiling-dubai-cost-guide; aaashi.com gypsum contractor
- [S20] aycontento.com SPC calculator; nextdayfloors.net; flooringforum.com waste threads
- [S21] dubaiwallcladding.com; wallyshardware.com WPC 160x23x2900; wpc-wallpanel.com PVC marble 1220x2800
- [S22] yasutrading.com 2026 UAE cost forecast; fepy.com/blog/plywood-prices-uae
- [S23] grovy.ae/uae-construction-costs-2026
- [S24] truckvillagetransport.ae 3-ton pickup; ehousemovers.com moving cost breakdown
- [S25] archdesk.com, nomitech.com (spreadsheet vs software)
- [S26] rightchoicedxb.com PP floor protection sheet
- [S27] dubaiwaste.com skip-bin calculator and landfill fee pages
- [S28] bestimate.ae/blog/apartment-renovation-dubai-cost-guide; haifarenov8.ae hidden expenses
- [S29] cleanfox.ae/cleaning-after-renovation; maidcorner.com; busybeesdubai.com
- [S30] revivehub.ae/dewa-approval-dubai
- [S31] marketintelligence.turnerandtownsend.com/uaemi-2025/construction-cost-performance; stonehaven.ae; fit.ae
- [S32] woodweb.com/knowledge_base/Materials_Labor_Overhead_And_Profit.html
- [S33] craftsmanengineering.com/blog/why-i-dont-consider-labor-when-estimating-cabinet-vision
- [S34] woodweb.com shop labor rate threads (search summary)
- [S35] buildertrend.com/library/margin-vs-markup-in-construction; jobtread.com markup vs margin
- [S36] woodweb.com/knowledge_base/Fine_Points_of_LinearFoot_Pricing.html
- [S37] bayut.com/mybayut construction noise complaint; propertyfinder.ae noise blog
- [S38] abspartners.ae/uae-midday-work-ban-2026; noblecoreventures.com midday break 2026
- [S39] interiofy.ae DEWA approval for electrical renovation
- [S40] madar-uae.com MR MDF; unilinpanels.com MR MDF

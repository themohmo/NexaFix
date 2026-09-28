# Costing pitfalls — and how the engine handles them

Condensed from the research in `docs/research/` (repo root). Use this when
reviewing an estimate or explaining why a number is what it is.

| Pitfall | What goes wrong | Engine behaviour |
|---|---|---|
| Rounding sheets per item | 5 items × 0.3 sheet become 5 sheets instead of 2 — joinery over-priced, bids lost | Boards pooled per material across the project, yield applied once, rounded once; rounding shown as its own cost |
| Pack rounding ignored | SPC/tiles by box, LED by 5 m roll, paint by 18 L pail | `pack_size` per material; purchase list buys whole packs; `spare_packs` for attic stock |
| Cladding offcuts assumed reusable | Fluted strips shorter than wall height and pattern-matched marble can't be pooled | Strips counted per column and rounded per wall; sheets `round_per_item` |
| Edge banding / hardware forgotten | The most under-estimated joinery lines | Edge band from every panel's visible edges; hinges by door height; runners, handles, stays, pins, rails, legs/hangers generated automatically |
| Consumables forgotten | Glue, screws, silicone, sandpaper, blades | `consumables_pct` (3%) of material cost |
| LED priced as strip only | Drivers, profile, connectors, cable, re-feeds missing; drivers overloaded | Drivers sized at 80% load, re-feed every 10 m, profile + connectors + cable + electrician hours |
| Gypsum add-ons | Access panels, MR board in wet areas, cove framing | Access panels / downlight cut-outs as fields; MR board automatic in wet rooms; cove & bulkhead framing |
| Socket = "a point" | Cable run, conduit, making good, new circuit | Per point: faceplate, box, cable, conduit, making good; isolators flag DEWA |
| Installation over-runs | Out-of-plumb walls, scribing, lifts, protection | Site trades +10% access allowance; install separate from workshop hours |
| True labour cost understated | Salary only, not visa/housing/transport/gratuity | Trade `cost_per_hour` is all-in ÷ ~179 productive h/month |
| Forgotten project costs | Transport, protection, cleaning, debris, supervision, NOC fees | Preliminaries auto-generated; `building_fees` / `extras` per project |
| Markup vs margin confusion | 25% markup is only 20% margin | Cost sheet shows both; warns under `min_margin_pct` |
| Stale prices | Materials up 12–18%; diesel +70% | Placeholder flags; `rates.py set` updates in seconds; validity 15 days on the quote |
| Tiny jobs at a loss | One mirror still costs a trip and two people | `min_charges` per item type; `min_job_value` warning |
| No snagging budget | Call-backs eat profit | Snagging reserve (1.5% of sell) in the internal cost |
| Unbilled variations | Verbal changes never invoiced | Re-run the spec with the change and issue `-R1` revision with the same ref |
| Floor plan ≠ site | Quoting brochure sizes | Typology estimates are labelled rough; assumptions listed; "subject to site measurement" in terms if needed |

## UAE specifics
- 5% VAT on top (advance payments trigger VAT on receipt). Toggle `pricing.vat_registered`.
- Building NOC admin fees AED 0–5,000 (developer-specific), refundable deposits AED 2,000–20,000 (cash flow, not cost).
- New circuits / DB changes may need DEWA involvement — the engine warns on isolators.
- Midday outdoor-work ban 15 Jun–15 Sep (12:30–15:00) — affects balconies/terraces, not interiors.
- Ramadan: working day −2 h; plan output × 0.75.
- Humidity: MR-MDF / marine ply for vanities and wet areas (vanity preset defaults to MR-MDF), MR gypsum in wet rooms.
- Towers: service-lift booking and loading-bay slots; check the lift cabin fits 2.8–2.9 m panels.

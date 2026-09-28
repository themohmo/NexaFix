---
name: nexa-costing
description: NexaFix costing and quotation engine for a Dubai furnishing, fit-out and bespoke joinery company. Turns property info (floor plans, room sizes, photos, a WhatsApp brief, or just "2BR in JVC, 110 m²") into a full cost build-up (material take-off, board and wood usage, hardware, LED drivers, labour hours, preliminaries, margin) and a client quotation PDF in the NexaFix template, priced from the owner's saved rate book. Use whenever the user asks to cost, price, estimate, quote or check margin on anything NexaFix supplies or installs (SPC/laminate/parquet flooring, tiles, wall cladding, TV/media units, wardrobes, kitchens, vanities, dressers, beds, headboards, mirrors, sockets, gypsum partitions and ceilings, cove lighting, LED strips, painting, curtains, blinds, countertops, furniture). Also use when the user gives new supplier prices or labour rates ("SPC now costs 38") so the rate book is updated, or asks which prices are still missing.
---

# NexaFix Costing

Everything is priced from **one rate book**, `rates.toml` (next to this file).
The owner enters prices once; every estimate reads them. Never invent a
price in chat — if something is missing from the rate book, add it there
first (see "Updating rates"), then run the engine.

The engine is deterministic Python. Your job is the part around it: read
the property, turn it into a project spec, run the engine, sanity-check
the result, and present it.

```
skill/
  rates.toml                 the rate book (single source of truth)
  scripts/estimate.py        spec -> estimate.json + Quotation PDF + Cost Sheet PDF + summary
  scripts/rates.py           show / set / add / confirm rates, list placeholders
  references/spec-format.md  every item type and field (read before writing a spec)
  references/intake.md       what to pull out of floor plans / briefs, defaults, what to ask
  references/takeoff.md      the formulas behind each quantity (for explaining numbers)
  references/pitfalls.md     what estimators get wrong and how the engine covers it
  references/estimate-json.md  structure of estimate.json (what the PDFs read)
  examples/*.yaml            complete worked specs
```

Requirements: Python 3.11+ (tomllib), `pyyaml` for YAML specs (JSON works
without it), `reportlab` for PDFs. Install with `pip install pyyaml reportlab` if an import fails.

## Workflow

### 1. Intake — get the property into rooms and items

Read whatever the user gives: floor-plan image or PDF, dimensions in text,
site photos, a scope list, a previous quote. Follow `references/intake.md`.

- **Rooms**: name, length × width (m), ceiling height if known, wet rooms,
  windows and doors that affect wall areas. From a floor plan, read the
  dimension strings. Where a room is only labelled with area, use `area`.
- **Scope**: what goes where: flooring type and which rooms, cladding
  walls (width × height), joinery (type, width, shelves, drawers,
  finish), mirrors, sockets, gypsum, lighting, paint.
- **No drawings yet?** Use a typology for a rough estimate:
  `project: {typology: 2br, total_area: 115}`. Say clearly that it is a
  rough budget until dimensions arrive.

Don't interrogate. If the brief is thin, make sensible assumptions from
`intake.md` and list them. Ask only for what would swing the price
materially (e.g. wardrobe width, whether cladding is full wall), and ask
it in one short message.

### 2. Write the project spec

Create a working folder per project (e.g. `quotes/<client-or-unit>/`) and
write `project.yaml` following `references/spec-format.md`. Group items the
way the client should see them: each `scope` entry becomes one numbered
item on the quotation (e.g. a "Master Bedroom Set" package holding
nightstands + headboard + bed box + cladding). Give packages client-friendly
`title` / `subtitle`. Leave `includes` out to let the engine write them.

### 3. Run the engine

```bash
python <skill>/scripts/estimate.py quotes/<job>/project.yaml --out quotes/<job>/out
```

It prints a markdown summary and writes `<ref>_Quotation.pdf` (client),
`<ref>_Cost_Sheet.pdf` (internal), `estimate.json`, `summary.md`.
A `SpecError` message says exactly which field is wrong — fix the spec and
re-run.

### 4. Check before presenting

Read the summary and look at:
- **Warnings**: margins below minimum, zero prices, missing images, DEWA notes.
- **Placeholder rates**: the rate book ships with researched UAE market
  defaults marked `placeholder`. Any quote using them is provisional —
  always tell the owner which ones were used (the summary lists them) and
  offer to replace them with their supplier prices.
- **Plausibility**: the engine warns when an item's price per m² / lm / point
  falls outside the usual Dubai band (`[sanity_bands]` in the rate book).
  Wardrobes per linear metre, TV units, mirrors: compare with `intake.md`
  section 4. If something looks off, open the cost sheet lines (`calc`
  column shows every formula) and fix the input, not the output.
- **Assumptions**: defaulted ceiling heights, rooms applied, typology sizes.

### 5. Present

Show the owner, in this order:
1. The headline (client total incl. VAT, gross margin, timeline).
2. The scope table (item, qty, client amount, cost, margin).
3. Assumptions and warnings, then placeholder rates used.
4. The two PDFs as files. **The cost sheet is internal — never
   send it to a client, and never put cost, margin or supplier information
   in anything client-facing.**

Then offer the obvious next moves: change an option ("3 shelves instead
of 2", "PVC marble instead of WPC"), apply a discount, show unit rates,
or replace placeholder prices.

- **Wording**: skim the client-facing text in the summary / PDF (titles,
  "scope includes", summary lines). Where the auto text doesn't fit the job,
  set `description` / `includes` / `summary_line` on the package.

### 6. Iterate

Edit `project.yaml` and re-run. Set `project.ref` for every quote and keep it
once the quote is sent, so revisions stay traceable (add `-R1`, `-R2`).
Preliminaries and contingency are spread over the items by value, so
changing one item nudges the others slightly; mention this if the owner
compares revisions line by line.

## Updating rates (the owner feeds data once)

When the owner gives a price, update the rate book immediately, show the
change, then use it:

```bash
python scripts/rates.py set materials.spc_plank.cost 38
python scripts/rates.py set materials.spc_plank.sell 115
python scripts/rates.py set trades.carpenter.cost_per_hour 24
python scripts/rates.py set pricing.contingency_pct 7
python scripts/rates.py add oak_spc_1220 --name "SPC oak 1220 x 180" --unit plank --cost 30 --sell 95 \
       --length-mm 1220 --width-mm 180 --category flooring --like spc_plank
python scripts/rates.py confirm materials.tile_60x60      # price is right, stop flagging it
python scripts/rates.py placeholders                      # what still needs real prices
python scripts/rates.py show cladding                     # browse
```

`set` on a cost/sell/hourly rate marks the entry `status = "owner"`, so it
stops being flagged. Only use `set` for keys you have understood; for a
new kind of item, read how an existing similar material is described and
use `add --like`.

**Onboarding.** If the owner wants to "load my prices", run `rates.py placeholders`
and go category by category (flooring, cladding, boards, hardware, LED,
electrical, gypsum, glass, paint, labour). Show the current default and
unit for each and let them answer in bulk ("MFC 265, MDF 18 60, hinges 12").
Labour: ask for monthly all-in cost per trade (salary + housing + visa +
transport) and divide by ~179 productive hours a month.

**Where the rate book lives.** In Claude Code, `rates.toml` is in the
NexaFix repo: commit changes so they persist. On Claude.ai (uploaded skill),
edits last only for the conversation: after updating, give the owner the
new `rates.toml` and remind them to re-upload the skill (or keep the master
copy in the repo). `NEXA_RATES=/path/rates.toml` or `--rates` points the
engine at another rate book.

## Calibrating against past jobs

When the owner shares an old quotation or a job's actual costs, write the
same scope as a spec, run it, and compare item by item. If the engine is
consistently off for one kind of work (e.g. joinery 15% high, painting
low), fix the cause in the rate book (the trade's `sell_per_hour`, a
category markup, an `install_hours_per_m2`, or a `sell_rate` the owner
always uses), not the individual quote. Tell the owner what you changed
and why, and re-run to confirm.

## Pricing logic (explain it when asked)

- Every line is priced twice: **cost** (what NexaFix pays) and **sell**.
  Materials sell at the owner's `sell` price if set (e.g. SPC plank 35 → 110),
  otherwise at cost + category markup. Labour sells at the trade's
  `sell_per_hour`. If a material's resale price already covers installation
  (`sell_includes_labour = true`, as for SPC), its labour is costed but not
  charged again.
- Materials are **pooled across the project** before rounding up to whole
  sheets, boxes, rolls and pails, so small items don't each pay for a full
  sheet. The rounding difference is a separate cost line ("stock rounding").
  Cladding strips and pattern-matched sheets are rounded per wall.
- Added at project level: consumables %, preliminaries (transport, protection,
  cleaning, debris, supervision, building fees), contingency %. These are
  spread across the quoted items in proportion to value, so the client sees
  clean lump sums. Each item is then rounded up to `round_items_to`.
- Internal only: snagging reserve and company overhead %, used to show net profit.
- Gross margin = (sell − direct cost) ÷ sell. Markup = (sell − cost) ÷ cost.
  A 25% markup is a 20% margin, so don't mix them up when the owner asks.
- Fixed selling rates are supported: `sell_rate` on an item (AED per m², lm,
  point) or `price` for a lump sum (a fixed-price item absorbs its share of
  preliminaries and contingency in its margin). The cost side is still built up, so the
  margin stays visible.

## Guardrails

- Rate book first: no ad-hoc prices in chat, no mental maths for totals.
  If the engine can't express something, use a `custom` item with explicit
  cost lines, or add a material.
- State every assumption the estimate depends on.
- Placeholder prices make a quote provisional. Say so plainly.
- Client documents never show costs, markups, suppliers or internal notes.
- Dubai context: 5% VAT (toggle `vat_registered`), building NOC and lift
  bookings (put fees in `project.building_fees`), DEWA approval for new
  circuits, moisture-resistant boards in wet areas (automatic for gypsum).

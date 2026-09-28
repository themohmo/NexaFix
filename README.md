# NexaFix — Project Costing Tool

Automated costing and quotations for **Nexa Fix** (furnishing, fit-out and
bespoke joinery, Dubai). Give it the property (a floor plan, room sizes, or
just "2BR in JVC, 1,250 sqft") and the scope. It produces:

- a **client quotation PDF** in the NexaFix template (cover letter, numbered
  scope items with "scope includes", investment summary, VAT, terms and acceptance)
- an **internal cost sheet PDF**: every material quantity with its take-off
  formula, wood/board usage in sheets, hardware, labour hours by trade, a
  shopping list rounded to whole boxes, sheets and rolls, preliminaries,
  margin, net profit after overheads and a timeline
- `estimate.json` and a chat summary.

Everything is priced from **one rate book** (`skills/nexa-costing/rates.toml`).
You enter your prices once; every quote uses them.

## How to use it

It is a **Claude skill**. You talk to Claude; Claude runs the engine.

> "New job, Mr. Ahmed, Marina Gate 2BR. SPC in all dry areas, fluted WPC
> wall behind the sofa 4.5 m with LED, TV unit 3 m with 2 shelves, cove in
> living and master, 2 wardrobes 2.4 and 1.8 m, 6 new sockets, paint
> throughout. Quote please."

> "SPC plank now costs me 38, I sell at 115."  → the rate book is updated.

> "Which prices are still placeholders?"  → Claude lists what to fill in.

**Claude Code (this repo).** The skill is linked at `.claude/skills/nexa-costing`,
so any Claude Code session in this repository picks it up. Rate changes are
saved in `rates.toml`; commit them so they persist.

**Claude.ai.** Build the zip with `python tools/build_skill_zip.py`, then upload
`dist/nexa-costing.zip` in Settings › Capabilities › Skills. Rebuild and
re-upload after changing prices (Claude.ai keeps its own copy of the skill).

**Command line (optional).**

```bash
pip install pyyaml reportlab            # Python 3.11+
cd skills/nexa-costing
python scripts/estimate.py examples/2br-marina-full-fitout.yaml --out ../../out
python scripts/rates.py placeholders    # prices still to confirm
python scripts/rates.py set materials.spc_plank.cost 38
```

## Feeding your data once

`rates.toml` ships with **researched UAE market prices (2025–26)** so the tool
works on day one. Every one of them is marked `status = "placeholder"`, and
quotes that use them are flagged. Replace them with your own supplier prices
(tell Claude, or use `rates.py set`); each one you set becomes `status = "owner"`.

What's in the rate book:

| Section | Holds |
|---|---|
| `[company]`, `[brand]`, `[quote]`, `[[terms]]` | quotation header, colours, letter, payment terms, validity, warranty |
| `[pricing]` | VAT, default and category markups, consumables %, contingency %, overhead %, target and minimum margin, rounding |
| `[trades.*]` | labour cost and sell per hour for carpenter, installer, flooring, tiler, gypsum, painter, electrician, upholsterer, helper, supervisor |
| `[materials.*]` | ~110 materials: SPC, tiles, cladding panels, gypsum, boards (MFC, MDF, ply, acrylic, veneer), hardware, LED, electrical, mirrors, paint, fabrics, stone |
| `[assemblies.*]` | how each item is built: waste %, consumption per m², hinge rule, workshop and site hours, cabinet presets (wardrobe, kitchen, vanity, dresser, nightstand…) |
| `[preliminaries]`, `[schedule]`, `[min_charges]` | transport, protection, cleaning, debris, supervision; crews and working hours; minimum charges |
| `[typologies.*]` | typical Dubai studio / 1BR / 2BR / 3BR / villa layouts for rough estimates |

## What it covers

Flooring (SPC, laminate, parquet, tiles, removal, levelling, skirting, thresholds)
· wall cladding (WPC fluted, PVC marble, stone-finish, acoustic slats, with trims
and LED) · gypsum partitions, ceilings, coves and bulkheads · cove lighting and
LED strips (drivers sized at 80% load) · sockets, switches, data and isolators
(new / relocate / faceplate) · mirrors (edges, frames, backlit) · all cabinet joinery
through a panel model (wardrobes, kitchens, vanities, dressers, nightstands,
shelving), media units (base box, feature panel, 1–3 floating shelves, LED),
headboards, bed boxes, countertops · painting, wallpaper, curtains, blinds · loose
furniture resale · custom lines.

## Repository layout

```
skills/nexa-costing/        the skill (upload this folder / the zip)
  SKILL.md                  instructions Claude follows
  rates.toml                YOUR RATE BOOK
  scripts/estimate.py       engine CLI      scripts/rates.py   rate-book CLI
  scripts/nexa_costing/     engine, calculators, joinery model, PDF renderers
  references/               spec format, intake guide, take-off formulas, pitfalls
  examples/                 worked project specs
  assets/fonts/             Cormorant Garamond + Jost (OFL)
docs/research/              the research behind the default prices and labour norms
docs/samples/               example quotation + internal cost sheet PDFs
tests/                      python -m pytest tests -q
tools/build_skill_zip.py    packages the skill for Claude.ai
```

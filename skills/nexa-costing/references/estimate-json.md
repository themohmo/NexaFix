# Estimate JSON contract

`estimate.py` writes `estimate.json` next to the PDFs. The PDF renderers
(`quote_pdf.py`, `costsheet_pdf.py`) read only this structure, so anything
shown on a PDF must exist here first. All money is AED (or `meta.currency`),
rounded to 2 decimals. Quantities are floats unless noted.

```jsonc
{
  "meta": {
    "ref": "NF-2026-0928",              // quotation reference
    "date": "28/09/2026",               // issue date, dd/mm/yyyy
    "title": "Bespoke Joinery & Wall Cladding Package",
    "summary": "A premium proposal for the supply, fabrication and installation of ...",
    "client": "Mr. Ahmed Khan",         // "" when unknown -> renderer prints "Client Name"
    "project": "Marina Gate 2BR",
    "location": "Dubai Marina, Dubai",
    "currency": "AED",
    "salutation": "Dear Sir / Madam,",
    "letter": ["paragraph", "paragraph", "paragraph"],
    "cover_tiles": ["LIVING ROOM", "TV UNIT", "BEDROOM", "DRESSER"],  // up to 4, numbered 01..04 on cover
    "cover_images": [null, null, null, null],                          // optional image paths per tile
    "show_unit_rates": false,           // true -> quote shows qty x rate per scope item
    "generated": "2026-09-28 15:55", "rates_file": ".../rates.toml"
  },
  "company": {
    "name": "NEXA FIX", "tagline": "Where craft meets quality", "division": "JOINERY & FIT-OUT",
    "phone": "", "email": "", "address": "", "website": "", "trn": "", "signatory": "",
    "validity_days": 15, "warranty_short": "2 Years",
    "brand": {"ink": "#1F1D1A", "accent": "#9C7B52", "paper": "#FBF8F3", "line": "#DDD3C4", "muted": "#7A7268"}
  },
  "scope": [
    {
      "no": "01",
      "title": "Living Room Wall Cladding",
      "subtitle": "Feature wall behind sofa",          // rendered letter-spaced caps
      "room": "Living Room",
      "description": "Full wall feature cladding ...",
      "includes": ["Colours and finishes as per approved sample", "..."],
      "summary_line": "Feature wall behind sofa, with integrated lighting",  // one line for the summary table
      "qty": 1, "unit": "Set", "qty_display": "1 Set",
      "unit_rate": 12500.0,                 // amount / qty (for show_unit_rates)
      "amount": 12500.0,                    // FINAL client amount for this scope item (ex VAT, before discount)
      "image": null,                        // optional reference image path (absolute when found)
      "tile": "LIVING ROOM",                // short label used on the cover grid
      "internal": {
        "cost_materials": 3100.0, "cost_labour": 1450.0, "cost_other": 0.0,
        "cost_project_share": 320.0,        // share of consumables, stock rounding, prelims, snagging reserve
        "cost_total": 4870.0,
        "fixed_price": false,               // true when the spec set a lump-sum `price`
        "sell_build_up": 11200.0,           // sum of line sells before prelims/contingency/rounding
        "amount": 12500.0,
        "profit": 7950.0, "margin_pct": 63.6,
        "labour_hours": {"installer": 14.0, "electrician": 3.0},
        "lines": [
          {"kind": "material",               // material | labour | other
           "ref": "wpc_fluted_panel",         // rate-book key (materials.* or trades.*)
           "description": "WPC fluted panel 160 x 2900 mm",
           "qty": 29.0, "unit": "pc",
           "unit_cost": 38.0, "cost": 1102.0,
           "unit_sell": 53.2, "sell": 1542.8,
           "calc": "4.2 m wide / 0.16 m = 27 columns x 1 piece + 8% waste",
           "placeholder": true}               // true when the rate is still a default, not the owner's price
        ],
        "notes": ["Wall width taken from floor plan"],
        "warnings": []
      }
    }
  ],
  "totals": {
    "subtotal": 48500.0, "discount": 0.0, "discount_label": "",
    "net": 48500.0, "vat_pct": 5.0, "vat": 2425.0, "grand_total": 50925.0,
    "vat_registered": true
  },
  "terms": [
    {"title": "Scope of Work", "text": "..."},
    {"title": "Pre-Commencement Coordination Meeting", "text": "..."},
    {"title": "Payment Terms", "text": "50% advance payment upon confirmation · 40% ..."},
    {"title": "Validity", "text": "This quotation is valid for 15 days from the date of issue."},
    {"title": "Warranty", "text": "Two (2) year warranty against manufacturing defects."}
  ],
  "internal": {
    "materials_cost": 0, "labour_cost": 0, "other_cost": 0,
    "consumables_cost": 0, "stock_rounding_cost": 0, "prelims_cost": 0, "snagging_reserve_cost": 0,
    "consumables_pct": 3, "snagging_reserve_pct": 1.5,
    "direct_cost": 0,                       // everything we pay out for this job
    "overhead_pct": 10, "overhead_cost": 0,  // share of company running costs
    "total_cost": 0,
    "sell_net": 0,                          // = totals.net
    "gross_profit": 0, "gross_margin_pct": 0,   // (sell - direct cost) / sell
    "net_profit": 0, "net_margin_pct": 0,       // after overhead
    "markup_on_cost_pct": 0,                    // (sell - direct) / direct
    "target_margin_pct": 35, "min_margin_pct": 25,
    "contingency_pct": 5, "contingency_amount": 0,
    "prelims": [{"name": "Transport & delivery", "cost": 0, "sell": 0, "calc": "3 trips x 250"}],
    "purchase_list": [
      {"ref": "spc_plank", "description": "SPC plank 1800 x 180 mm", "category": "flooring",
       "qty_required": 131.9, "qty_to_buy": 136, "unit": "plank",
       "pack_note": "17 boxes of 8", "unit_cost": 35.0, "cost": 4760.0,
       "supplier": "", "placeholder": false}
    ],
    "boards": [
      {"ref": "mdf_18", "description": "MDF 18 mm 1220 x 2440", "m2": 21.4,
       "sheets_exact": 8.8, "sheets_to_buy": 9}
    ],
    "labour": [
      {"trade": "carpenter", "label": "Carpenter (workshop)", "hours": 42.0, "days": 4.7,
       "cost_per_hour": 22.0, "cost": 924.0, "sell_per_hour": 60.0, "sell": 2520.0}
    ],
    "schedule": {"procurement_days": 5, "workshop_days": 8, "site_days": 6, "total_days": 17,
                 "weeks": 3.4, "notes": ["Workshop and site overlap is not assumed"]},
    "warnings": ["Margin on 'SPC Flooring' is 22% (below minimum 25%)"],
    "assumptions": ["Ceiling height 2.8 m (default)"],
    "placeholders_used": ["wpc_fluted_panel", "carpenter"],   // bare rate-book keys (materials or trades)
    "rooms": [{"name": "Living Room", "area": 27.9, "perimeter": 21.4, "height": 2.8,
               "wall_area": 51.9, "wet": false, "estimated": false}]
  }
}
```

## Rules the renderers rely on

* `sum(scope[].amount) == totals.subtotal` exactly (the engine distributes
  preliminaries, contingency and rounding into the scope amounts).
* `scope[].amount` is already rounded to the rate book's `round_items_to`.
* Client quote PDF never shows anything under `internal`.
* `placeholder: true` lines must be visibly flagged on the internal cost sheet.

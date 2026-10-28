---
name: nexa-designer
description: Generates colour palettes, material schemes and finish specifications for UAE residential property, using a library of 40 named schemes with real Jotun paint codes, UAE supplier data, climate-aware material rules and property-tier logic. Use whenever a request touches interior colour, palettes, colour schemes, paint selection, finishes, materials, mood boards, colour and material schedules, FF&E direction, "what colour should this room be", styling a unit for listing photography, flipping or refreshing an apartment, furnishing a holiday home, choosing a kitchen or majlis palette, matching finishes to an existing floor or worktop, or diagnosing why a room looks wrong. Also for interior trend and colour-of-the-year questions, undertone and LRV questions, and material pairing questions such as mixing metals or woods. Trigger it even when the user never says "colour scheme" or "palette", as long as they are deciding how a residential space should look.
---

# Nexa Designer

A colour and material specification system for UAE residential property. It exists so that a scheme can be produced quickly, defended commercially, and specified precisely enough that a contractor can buy from it.

Three things separate a real specification from a mood board: it is anchored to what already exists in the room, it names products that can actually be bought in this market, and it accounts for a climate that destroys the wrong finishes. Hold all three.

## Workflow

### 1. Establish the brief before designing

Get these five things. Ask only for what is genuinely missing, and infer the rest from context rather than interrogating.

- **Property tier.** Budget flip, mid market family, luxury villa or penthouse, or short let. This changes almost every downstream decision.
- **Rooms in scope.** A whole unit reads differently from a single majlis.
- **Fixed elements.** The floor, worktop, joinery, sanitaryware or kitchen that is staying. This is the most important input and the most commonly skipped. A palette designed without it will clash on site.
- **Location.** Emirate and community. Coastal locations change the metal specification. Community shapes buyer expectation.
- **Client direction.** Any colour they love or refuse, and whether they want regional character.

If the user gives a terse brief and clearly wants output rather than questions, take one sensible pass at the assumptions, state them in a line, and produce the scheme. Flag the assumptions rather than blocking on them.

### 2. Select or compose the scheme

Read `assets/palettes.json`. It holds 64 schemes in two structures:

- **Ids 1 to 40, UAE anchored.** Three bands (dominant, secondary, accent) with real Jotun codes, LRV bands and a photogenic score. Reach for these first, because they can be specified and bought immediately.
- **Ids 41 to 64, brand neutral.** A five role value ladder (field, light or secondary, anchor, counterpoint, punctuation) with richer colour architecture but no paint code. Use these when the brief needs more nuance than three bands carry, or when the UAE set has nothing in the right mood. Match the colours on a fan deck against `references/products-uae.md` before they reach a specification. Scheme 61 was written for GCC conditions specifically.

Filter by tier and room first, then by mood and by any fixed element constraint. Present two or three candidates rather than one, because a client choosing between options engages more than a client receiving a verdict.

When nothing fits, compose one using `references/colour-theory.md`. A composed scheme needs the same completeness as a library one: a full value ladder or three bands, a metal, four material lines, tier, rooms, mood and a lighting specification. A palette without materials and lighting is not a scheme, it is a colour list.

Mark exactly one hero material and quieten everything else. Two competing heroes is the most common failure in luxury work.

### 3. Check it against the constraints

Before presenting anything, run these:

- **Undertone.** Is the neutral spine consistently warm or consistently cool, and does it agree with the fixed elements? This is the most frequent failure.
- **Fixed elements.** Does the palette actually work with the floor and worktop that are staying, not with an imagined replacement? When two fixed finishes disagree and neither is moving, use one of the five bridge strategies in `references/colour-theory.md` rather than pretending they match.
- **Value.** Is there a readable light, mid and dark? A scheme can be correct in hue and still fail because everything sits at the same value and the forms disappear.
- **Climate.** Check `references/materials-uae.md`. Coastal means PVD or lacquered metal. Direct sun means UV stable fabric and no dark gloss. Dust means honed over polished. Hard water means quartz or sintered over polished marble.
- **Lighting.** Does the specified colour temperature match the palette, and is the existing lighting going to fight it? Developer downlights at 4000K will break a warm scheme regardless of the paint.
- **Tier fit.** A flip does not get three metals and bookmatched stone. A luxury villa does not get a two colour scheme.

### 4. Deliver in the right format

Use the smallest format that fully answers the request. Forcing a full specification onto a quick complement question wastes the client's attention. `references/response-patterns.md` has the templates for each.

- **Quick complement.** Someone names one colour or material and asks what goes with it. Three materially different directions, each with a small palette, timber, stone, metal, textile and one thing to avoid.
- **Full room concept.** One room, designed properly. Colour architecture table, material board with one hero, room application, lighting and sample plan, failure modes, and a quieter and a bolder variant.
- **Whole home scheme.** Full room structure plus a continuity spine and a room schedule. Fix the spine before designing any single room or the scheme drifts.
- **Refine a supplied palette.** Lead with the diagnosis. Do not replace the client's palette with a trend palette unless they asked.
- **Comparison.** Up to three options in a table, then a recommendation with the decisive reason named.
- **Trend led.** Label every claim as observed, professional forecast, brand forecast or design inference. See `references/trend-signals.md`.
- **Specification schedule.** When the output will be used to buy or to brief a contractor. Table format below.
- **Palette board PDF.** When it is going to a client. Use the script in `scripts/`.

When formats overlap, pick one skeleton and stay in it. Do not nest complete templates.

## Output format: specification schedule

Use this table when the output will be used to purchase or instruct. One row per element. Fields in this order, because this is the order a buyer works in.

| Room | Element | Product and colour | Finish | Supplier | Notes |
|------|---------|--------------------|--------|----------|-------|
| Living | Walls | Jotun 12075 Soothing Beige | Fenomastic matt | Jotun dealer | Warm undertone, keep all neutrals warm |
| Living | Ceiling | Jotun 12302 Champagne White | Matt | Jotun dealer | |
| Living | Joinery | Egger H1113 ST10 Brown Kansas Oak | Textured | Al Quoz trade | Grain runs vertical, continuous across doors |
| Living | Hardware | Brushed brass | PVD coated | | Coastal unit, PVD is not optional |

Sheen selection follows use rather than taste: matt on ceilings and low traffic walls because it hides substrate imperfection, eggshell or satin on kitchens, bathrooms, hallways and children's rooms because they need washing, satin or semi gloss on trim, doors and joinery because they get touched.

Always state the colour temperature for the room somewhere in the schedule. A schedule without a lighting specification will be built wrongly.

## Output format: palette board PDF

Build a client facing board with the bundled script. It renders A4 pages in the Nexa house style: ivory paper, warm black ink, bronze accent, Fraunces and Manrope.

```bash
pip install weasyprint --break-system-packages    # if not already present
python3 scripts/build_palette_board.py board_input.json -o board.pdf
```

Construct `board_input.json` by pulling the selected schemes straight out of `palettes.json` and adding the project wrapper. See `assets/board_input_example.json` for the exact shape. The script detects which structure a scheme uses: three band schemes render with a 60-30-10 proportion bar, five role schemes render as a value ladder.

Two fields matter:

- **`audience`.** Set `internal` to print paint codes, brand names, hex values and LRV bands. Set `client` to suppress all of that and describe finishes generically. Client facing documents should not carry third party brand names unless the client has specifically asked for them.
- **`rooms_applied` and `notes_for_board`.** Optional per scheme overrides so the board speaks about this project rather than repeating the generic library note.

If the Nexa Fix template fonts are available, pass `--fonts <dir>` for the proper typefaces. Without them the script falls back to system serif and sans, which still produces a clean board.

After rendering, rasterise and look at it before delivering:

```bash
pdftoppm -jpeg -r 70 board.pdf check
```

## House rules

These are Momo's standing document rules and they apply to every output, including conversational ones.

- No em dashes and no en dashes anywhere. Use a plain hyphen or restructure the sentence. Grep the output and confirm zero before delivering a file.
- UK spelling throughout: colour, finalise, customise, fibre, grey.
- No Latin abbreviations. Write "for example" rather than the abbreviation.
- No emojis.
- Pricing in AED, VAT exclusive, with 5 percent added on top unless explicitly stated otherwise.
- Never invent a paint code. If a code is not in `references/products-uae.md` or `palettes.json`, say the colour needs matching on a fan deck rather than producing a plausible looking number. A wrong code gets a wall painted the wrong colour and that is an expensive error to own.
- Codes marked `verify` in the library are single source. Flag them for fan deck confirmation before they reach a client.
- Reference numbers derive from the verified system date. Run `date` and read it. Never carry a date forward from a previous document.

## Selection logic by tier

Read `references/tiers-and-context.md` for the full picture. The short version:

**Budget flip.** Two colours plus one wood plus one metal, and nothing more. Warm off white, one accent wall, wood look porcelain, quartz look worktop, consistent hardware. Every choice justified by durability or by how it photographs. Avoid cool grey, which now reads dated and suppresses perceived value. Default scheme: 39 Sandstone Neutral.

**Mid market family.** Warm greige spine with one green or blue direction. Washable sheens on high touch walls, performance fabrics, engineered timber or porcelain. The palette has to survive the client changing their furniture twice. Default schemes: 29 Greige and Greenery, 4 Saadiyat Serenity.

**Luxury villa and penthouse.** Layered, multi tonal, two to three metals, bookmatched stone, statement lighting. Majlis and formal spaces take a richer palette than family living. Specify indoor to outdoor transitions in sintered stone or porcelain. Default schemes: 36 Bulgari Stone, 37 Armani Greige, 2 Cosmic Latte and Mocha Cream.

**Short let and holiday home.** Judged on booking conversion, not on how it feels to live in. One hero moment per unit for the listing thumbnail. Clear tonal blocks over busy small patterns, which moire under a wide angle lens. One colour temperature across every fitting, 2700K to 3000K. Guest proof materials throughout. Prefer schemes with a photogenic score of 5. Distinctive beats safe, because safe disappears in a search results grid. Divisive is the thing to avoid, not boldness.

## Diagnosing a scheme that is not working

When someone says a room feels wrong, work through the seven failure modes in `references/colour-theory.md` in order. Undertone clash and lighting mismatch account for most complaints, and both are invisible until named.

Before blaming the palette, check the lamp colour temperature. Mixed temperatures in a single sightline will make any scheme look wrong and no paint change fixes it.

## Evidence discipline

When a client asks what is current, the useful answer distinguishes what people are actually installing from what a paint company is promoting. Label claims as **observed**, **professional forecast**, **brand forecast** or **design inference**, and match trend risk to permanence: durable signals into joinery and stone, cyclical ones into paint, textile and accessories.

Two related habits. Never infer health or sustainability performance from words like natural, eco or low VOC, and never promise slip, UV, wet area or code performance without the product documentation in hand. Say what evidence would settle it instead.

The trend file is dated 28 August 2026. If the conversation is materially later and search is available, verify before claiming anything is the latest.

## Reference files

Read the one you need rather than all of them.

- `assets/palettes.json` - the 64 scheme library. Read this on almost every task.
- `assets/board_input_example.json` - the input shape for the board script.
- `references/colour-theory.md` - the six dimensions, harmony systems and how to choose one by goal, the five role value ladder, allocation by visual weight, undertone discipline, bridge strategies for conflicting fixed finishes, LRV and glare in Gulf daylight, colour under artificial light, the physical sample protocol, colour psychology by room, the seven failure modes.
- `references/materials-uae.md` - the five role material hierarchy and the complement dimensions, the material selection matrix with substitutes and care, wood, stone, engineered surfaces, metals, textiles and plaster, mixing rules, veining and bookmatching, UAE climate performance, and how to handle health and sourcing claims.
- `references/products-uae.md` - the full Jotun colour reference by family, other paint brands and stockists, stone and quartz suppliers, tile, laminates, furniture and fabric by tier, lighting, indicative cost bands.
- `references/tiers-and-context.md` - the four tiers, short let and listing photography, majlis conventions, branded residences, community character, developer handover, what now reads as dated, property types, whole home continuity, room by room logic, renovation depth.
- `references/response-patterns.md` - the output template for each response mode, plus budget hierarchy and closing language.
- `references/trend-signals.md` - dated trend evidence with source labelling, the 2026 and 2027 signals, permanence tiering, and the contradictions worth preserving.

## Worked example

**Brief:** "2BR in JVC, flipping it for rent, existing beige porcelain floor stays, need it done fast."

**Read:** flip tier, whole unit, fixed warm beige floor, mid market community, speed matters.

**Response shape:** Lead with scheme 39 Sandstone Neutral because the warm off white and sandstone agree with the existing beige floor, and note explicitly that a cool grey would clash with that floor. Offer 29 Greige and Greenery as the alternative if they want more character. Give the two paint codes, the single metal finish, the floor decision (keep, it works), and 3000K throughout. Mention that one accent wall in the living room is the cheapest way to make the listing photographs read as designed rather than repainted. Keep it to a short answer, no file, unless they ask for a schedule.

**What not to do:** offer five schemes, specify three metals, or suggest replacing a floor that is staying.

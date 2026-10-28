# 5. Layout, components, overlays, and page transitions

Entries 081 to 100. Grids, responsive components, overlays, and native view transitions. Prefer browser primitives where support allows, keep a clean single-column reading order in the DOM, and always retain native form and focus semantics under styled controls.

### 081. Bento Grid
**Also called:** modular dashboard, tile mosaic. **Does:** composes features in varied but aligned rectangular spans, often mixing metrics, media, and small interactions. **Replicate:** use CSS Grid with explicit named areas or span utilities, keep one dominant tile, align inner content with subgrid, and change the composition at container breakpoints. **Label:** Native.

### 082. Asymmetric Editorial Grid
**Also called:** broken grid, magazine layout. **Does:** creates tension with oversized type, offset media, intentional whitespace, and occasional controlled overlap. **Replicate:** establish a 12-column grid, anchor key edges, let selected elements span or translate across tracks, and preserve a simple single-column reading order in the DOM. **Label:** Native.

### 083. Masonry / Grid-Lanes Gallery
**Also called:** Pinterest layout, packed gallery. **Does:** packs variable-height items into visual lanes without row gaps. **Replicate:** use the emerging CSS Grid Lanes/masonry syntax only as progressive enhancement; today, use CSS columns for simple non-interactive galleries or Masonry.js for strict source-order/control. **Label:** Progressive / Library.

### 084. Subgrid-Aligned Cards
**Also called:** shared card rhythm, cross-card alignment. **Does:** aligns headings, copy, metadata, and CTAs across cards even when content lengths differ. **Replicate:** make the card collection a grid, let each card use `grid-template-rows: subgrid`, and span the shared row tracks. **Label:** Native.

### 085. Container-Query Morphing Component
**Also called:** component-responsive card, intrinsic layout. **Does:** changes a component from compact row to editorial panel based on its own space, not the viewport. **Replicate:** declare `container-type: inline-size` on the host and use `@container` to alter grid, type, media ratio, and controls; use `cqi` units for fluid local scaling. **Label:** Native.

### 086. Scroll-State-Aware Component
**Also called:** stuck-state styling, snapped-card emphasis. **Does:** styles a sticky header when stuck, highlights the snapped carousel item, or shows edge fades only while more content is scrollable. **Replicate:** set `container-type: scroll-state` and query `stuck`, `snapped`, `scrollable`, or direction states; fall back to IntersectionObserver and scroll measurements. **Label:** Progressive.

### 087. Anchor-Positioned Tooltip or Popover
**Also called:** tethered overlay, collision-aware callout. **Does:** keeps an overlay attached to a trigger and automatically flips it when space runs out. **Replicate:** combine the HTML Popover API with CSS `anchor-name`, `position-anchor`, `position-area`, and `position-try-fallbacks`; use Floating UI as the fallback for older browsers. **Label:** Progressive / Library.

### 088. Animated Top-Layer Dialog
**Also called:** native modal transition, popover entrance. **Does:** gives dialogs, sheets, menus, and popovers polished entry and exit motion while retaining native focus/top-layer behaviour. **Replicate:** use `<dialog>` or `popover`, `@starting-style`, `transition-behavior: allow-discrete`, and transitions for `display`/`overlay`, opacity, and transform. **Label:** Native / Progressive.

### 089. Customizable Native Select
**Also called:** styled select picker, base-select. **Does:** gives the native `<select>` a fully art-directed button and option panel without discarding keyboard and form behaviour. **Replicate:** opt into `appearance: base-select`, style the picker and selected-content pseudos, and retain conventional select styling as fallback. **Label:** Progressive.

### 090. CSS-Native Carousel
**Also called:** scroll-marker carousel, no-JS slider. **Does:** provides snapping, next/previous controls, and pagination with browser primitives. **Replicate:** combine horizontal overflow, scroll snap, `::scroll-button`, `::scroll-marker`, `scroll-marker-group`, and `:target-current`; use an Embla/Swiper fallback until support meets your audience. **Label:** Progressive.

### 091. 3D Coverflow / Card-Deck Carousel
**Also called:** perspective slider, stacked swiper. **Does:** emphasises the active card while neighbours rotate, recede, or fan behind it. **Replicate:** use Swiper's Coverflow/Cards/Creative effects, or map each slide's distance from center to translateZ, rotateY, scale, and opacity; preserve swiping, buttons, and keyboard navigation. **Label:** Library.

### 092. Before-and-After Comparison
**Also called:** image comparison slider, reveal scrubber. **Does:** lets users directly compare two aligned visuals. **Replicate:** stack matching images, clip the top one at a CSS-variable percentage, and update it with an accessible range input; position the handle from the same value. **Label:** Native.

### 093. Dock Magnification Navigation
**Also called:** macOS dock, fisheye nav. **Does:** enlarges the hovered icon and proportionally affects nearby icons. **Replicate:** calculate pointer distance from each item center and map it through a smooth falloff to scale/translation; Motion values and springs work well. Provide labels and a stable keyboard state. **Label:** Library.

### 094. Floating Island Navigation
**Also called:** dynamic island nav, pill dock. **Does:** uses a compact floating pill that expands or morphs to show active context, playback, cart, or page controls. **Replicate:** keep one fixed/sticky shell, animate its measured layout with Motion `layout`/`layoutId` or GSAP FLIP, and change content through explicit states. **Label:** Library.

### 095. Command Palette
**Also called:** spotlight search, action launcher. **Does:** opens a fast keyboard-first overlay for navigation, search, and actions. **Replicate:** use a dialog with a combobox/listbox pattern, fuzzy filtering, recent items, grouped results, and `Ctrl/Cmd+K`; animate only the panel and result changes, not focus. Libraries include cmdk and React Aria components. **Label:** Native / Library.

### 096. Radial Context Menu
**Also called:** pie menu, orbit actions. **Does:** places contextual actions around the pointer or selected object for quick directional choice. **Replicate:** position a popover at the invocation point, distribute buttons with polar coordinates, and animate them from the center; always provide a linear list for keyboard/touch and avoid more than about eight actions. **Label:** Native / Library.

### 097. Exclusive Accordion
**Also called:** animated FAQ, one-open disclosure. **Does:** expands one content section while closing its peers. **Replicate:** use `<details name="group">` for native exclusivity where supported, animate an inner grid from `0fr` to `1fr` or use discrete display transitions, and rotate the summary icon. **Label:** Native / Progressive.

### 098. Shared-Indicator Tabs
**Also called:** morphing tab underline, sliding pill tabs. **Does:** moves one highlight fluidly between tab labels and can animate the content's layout. **Replicate:** keep an accessible tablist, animate a shared element with Motion `layoutId`, GSAP FLIP, or measured CSS variables, and use directional transitions for the panels. **Label:** Library / Native.

### 099. Same-Document Shared-Element Transition
**Also called:** SPA view transition, thumbnail-to-detail morph. **Does:** visually carries an image/card from one app state into another, preserving context. **Replicate:** assign unique `view-transition-name` values and wrap the DOM update in `document.startViewTransition()`; style the old/new snapshot pseudo-elements and provide an instant update fallback. **Label:** Native / Progressive.

### 100. Cross-Document Page Transition
**Also called:** MPA view transition, animated page navigation. **Does:** animates between separate HTML pages, including shared hero imagery or directional chapter slides. **Replicate:** opt both pages in with `@view-transition { navigation: auto; }`, match unique transition names, and use transition types for forward/back behaviour; pair likely links with cautious speculation-rule prefetching for near-instant navigation. **Label:** Progressive.

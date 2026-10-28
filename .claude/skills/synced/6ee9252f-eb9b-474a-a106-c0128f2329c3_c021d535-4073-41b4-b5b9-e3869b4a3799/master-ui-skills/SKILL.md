---
name: master-ui-skills
description: A field guide of 120 named modern web UI/UX techniques spanning scroll and narrative motion, kinetic typography, pointer and touch micro-interactions, gradient/glass/blend surfaces, advanced layout and page transitions, and GPU/3D/generative media. Each entry gives what it does, its aliases, a fast build recipe, and an implementation label. Use whenever building, designing, or redesigning any website, landing page, hero, dashboard, or component; adding scroll effects, entrance animations, transitions, hover or cursor interactions, loading states, or premium polish; identifying or naming an effect the user has seen; choosing techniques for a site archetype such as SaaS, editorial, product launch, developer/cyber, or playful app; or working with GSAP, Motion, Lenis, Three.js, Rive, Lottie, scroll-driven CSS animations, view transitions, anchor positioning, container queries, or WebGPU. Reach for it even when no specific effect is named but the user wants modern, current, or 2026-era frontend design.
---

# Master UI Skills

A working catalogue of 120 modern web UI/UX techniques with build recipes. This skill supplies the vocabulary and the fastest credible way to build each effect. It pairs naturally with any aesthetic or redesign skill: those decide taste and direction, this decides which named technique to reach for and how to ship it.

This is a broad field guide rather than a claim that every item was invented recently. It favours techniques that are visually current, newly browser-native, or newly practical because of recent CSS and Web API improvements. Research date on the source catalogue: 20 July 2026.

## How to use this skill

Follow this loop whenever a task involves frontend motion, interaction, or visual polish.

1. Identify the need. Work out the site archetype and the specific job to be done, for example a hero entrance, a scroll narrative, a numeric stat, a card hover, a page transition, or a loading state.
2. Shortlist by archetype. Use the Fast selection guide below to get a starting set of technique numbers suited to the kind of product being built.
3. Open the right category file. Read only the reference file that covers the technique numbers you need. Each entry gives the aliases to search, what the effect does, a build recipe, and an implementation label.
4. Pick the implementation route. Use the label and the Suggested stack table to choose between a native, progressive, library, or GPU approach based on the browser matrix and performance budget.
5. Build to the production rules. Apply all five production rules below to every effect, and always include the reduced-motion and coarse-pointer fallbacks.

Do not paste effects in blindly. Choose a small number that support the content, keep the real semantic layer intact underneath, and make every animation degrade gracefully.

## Implementation labels

Every technique carries one or more of these labels so the correct build route is obvious.

- Native. Practical with HTML, CSS, and browser APIs, with broad modern-browser support.
- Progressive. A newer browser feature. Wrap it in `@supports`, retain a static fallback, and check it against the target browser matrix.
- Library. Easiest and most robust with the named library, although a hand-built version is possible.
- GPU / heavy. Canvas, SVG filters, WebGL, WebGPU, video, or another technique that needs a real performance budget.

## Five production rules

These apply to every technique in the catalogue. They are not optional polish, they are what separates a credible build from a janky one.

1. Prefer `transform` and `opacity` for frequent animation. Layout-triggering and paint-heavy properties can stutter.
2. Provide a calm version under `@media (prefers-reduced-motion: reduce)` and never let meaning depend on motion alone.
3. Keep real buttons, links, headings, focus order, and keyboard behaviour underneath the visual layer.
4. Treat custom cursors, hover effects, and smooth scrolling as desktop enhancements. Disable or simplify them for coarse pointers and touch.
5. Pause hidden canvases and videos, cap device pixel ratio, lazy-load heavy scenes, and test on a mid-range phone, not only on a designer laptop.

## Fast selection guide

Use these as starting shortlists, then refine to the content. Numbers refer to catalogue entries in the reference files.

- Premium SaaS site: 001, 002, 004, 010, 021, 023, 043, 063, 080, 081, 085, 087, 098, 099.
- Editorial or cultural site: 007, 012, 014, 026, 028, 031, 038, 039, 065, 066, 074, 082, 100.
- Product launch: 011, 013, 018, 040, 049, 061, 068, 076, 101, 107, 111, 112, 117.
- Developer or cyber aesthetic: 005, 021, 025, 035, 062, 065, 071, 075, 076, 101, 109, 114, 118.
- Playful consumer app: 033, 034, 043, 046, 053, 054, 055, 057, 058, 059, 091, 094, 115, 116.

## Suggested implementation stack by need

| Need | First choice | Why |
|---|---|---|
| Small interface transitions | CSS transitions / Web Animations API | Minimal runtime and easy progressive enhancement |
| React layout and gesture motion | Motion | Springs, drag, shared layout, presence, and scroll values |
| Choreographed marketing pages | GSAP + ScrollTrigger | Precise timelines, pinning, scrubbing, text/SVG plugins |
| Smooth scroll synchronisation | Lenis | Lightweight inertial scrolling with WebGL/GSAP sync |
| Accessible carousels | Native CSS progressively, Embla or Swiper today | Native direction is promising, libraries cover current compatibility |
| 2D designer-authored animation | Rive for interaction, Lottie for playback | Rive has state machines, Lottie has a huge content pipeline |
| 3D product and shader work | Three.js or React Three Fiber | Mature rendering, loaders, controls, and post-processing |
| Very large sprite/particle scenes | PixiJS, Three.js instancing, or WebGPU | Keeps work off the DOM and exploits the GPU |

## Catalogue index

Read only the file you need for the current task.

1. Scroll, navigation, and narrative motion. Entries 001 to 020. Progress bars, sticky and direction-aware headers, scroll-linked reveals and decode effects, parallax, marquees, sticky stacking and pinned horizontal scroll, scrollytelling, image-sequence scrub, path draw, mask wipes, and inertial smooth scroll. See `references/01-scroll-navigation-motion.md`.
2. Typography and numeric display. Entries 021 to 040. Scramble and kinetic variable type, split-line and per-character reveals, typewriter, gradient and stroke effects, media-filled and path text, count-up and odometer numbers, split-flap and slot rotators, rolling labels, balanced wrapping, and scroll-scale display type. See `references/02-typography-numeric.md`.
3. Pointer, touch, and micro-interaction. Entries 041 to 060. Spotlight and custom cursors, magnetic buttons, 3D tilt and parallax layers, holographic glare, cursor trails and particle fields, hover previews, clip-path reveals, liquid and elastic buttons, ripple feedback, morphing icons, hold-to-confirm, draggable and swipeable cards, spring toggles, and morphing navigation. See `references/03-pointer-touch-microinteraction.md`.
4. Surfaces, colour, masking, and compositing. Entries 061 to 080. Mesh and aurora gradients, pointer-reactive lighting, conic borders, film grain, halftone, frosted and refractive glass, iridescence, chromatic aberration, duotone and gradient maps, blend cutouts, neon bloom, border beams, shimmer skeletons, mask reveals, and perceptual OKLCH colour systems. See `references/04-surfaces-color-compositing.md`.
5. Layout, components, overlays, and page transitions. Entries 081 to 100. Bento and editorial grids, masonry and subgrid, container-query and scroll-state components, anchor-positioned overlays, animated dialogs, customisable native select, native carousels, coverflow, comparison sliders, dock and island navigation, command palettes, radial menus, accordions, shared-indicator tabs, and same-document and cross-document view transitions. See `references/05-layout-components-transitions.md`.
6. GPU, 3D, generative, and rich-media experiences. Entries 101 to 120. Shader backdrops and cursor distortion, metaballs, fluid simulation, particle fields and constellations, displacement and vertex-distortion transitions, noise dissolve, post-processing, 3D product viewers and camera journeys, exploded hotspots, SDF text, Rive and Lottie, scroll-scrubbed video, glitch transitions, WebGPU backgrounds, and WebXR/AR placement. See `references/06-gpu-3d-generative-media.md`.

## Official references

Point to these for browser support details and API specifics when building.

- MDN: CSS scroll-driven animations, View Transition API, CSS anchor positioning, Popover API, `@starting-style`, container size/style and scroll-state queries, CSS `shape()`, `corner-shape`, `oklch()` and relative colour syntax, `color-mix()`, WebGPU API, WebXR Device API, and reduced-motion accessibility.
- Chrome for Developers: What's New in Web UI (I/O 2025 recap) and the customisable `<select>` write-up.
- Library docs: Motion, GSAP, Lenis, Three.js, Rive web runtime, Embla Carousel, Swiper, and Anime.js.
- web.dev: animation performance guidance.

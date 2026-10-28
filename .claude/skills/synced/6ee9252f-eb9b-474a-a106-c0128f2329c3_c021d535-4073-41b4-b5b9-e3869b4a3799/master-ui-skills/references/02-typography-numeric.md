# 2. Typography and numeric display

Entries 021 to 040. Kinetic type, animated headlines, and moving numbers. Keep a stable, whole-word accessible copy for anything that animates per character, and never announce intermediate typing states to assistive technology.

### 021. Scramble Text
**Also called:** decrypt, cipher, Matrix resolve. **Does:** flashes random glyphs before resolving to the final label. **Replicate:** use GSAP ScrambleTextPlugin or Motion's scramble utility, or repeatedly replace only unrevealed characters with `requestAnimationFrame`; keep the accessible text stable and hide the animated duplicate from assistive technology. **Label:** Library.

### 022. Kinetic Variable Type
**Also called:** variable-weight hover, breathing typography. **Does:** continuously or interactively changes weight, width, slant, optical size, or a custom font axis. **Replicate:** choose a variable font and animate `font-variation-settings`; map pointer distance, audio level, or scroll progress to axes such as `"wght"`, `"wdth"`, and `"slnt"`. **Label:** Native.

### 023. Split-Line Mask Reveal
**Also called:** line curtain, masked headline entrance. **Does:** makes each line rise cleanly from behind its own clipping edge. **Replicate:** split by visual line with GSAP SplitText or SplitType, wrap each line in `overflow: clip`, and stagger `translateY(110%)` to zero; re-split after fonts load and when width changes. **Label:** Library.

### 024. Per-Character Cascade
**Also called:** character stagger, kinetic letter build. **Does:** assembles a word with wave, fan, bounce, blur, or rotational motion per glyph. **Replicate:** split into character spans, expose an index custom property, and calculate staggered delays in CSS or use GSAP/Anime.js; keep a whole-word accessible copy to avoid screen-reader spelling. **Label:** Native / Library.

### 025. Typewriter with Living Caret
**Also called:** terminal typing, prompt writer. **Does:** types copy progressively while a caret blinks, stretches, or changes state. **Replicate:** reveal characters with a timer or stepped CSS animation, build the caret as a pseudo-element, and pause at punctuation. Do not repeatedly announce intermediate text in an `aria-live` region. **Label:** Native.

### 026. Blur-to-Sharp Text Reveal
**Also called:** focus reveal, optical fade. **Does:** brings copy into apparent focus while fading and slightly rising it. **Replicate:** animate from `filter: blur(8px)`, low opacity, and a small translate to a sharp resting state; stagger by word or line, and use a simple opacity fallback on low-power devices. **Label:** Native.

### 027. Gradient Sweep Type
**Also called:** highlight scan, metallic text pass. **Does:** sends a bright band across letterforms to signal emphasis, loading, or a premium material. **Replicate:** apply a wide linear gradient to `background-clip: text`, make the text transparent, and animate `background-position`; run once on entry or hover rather than looping everywhere. **Label:** Native.

### 028. Stroke-to-Fill Heading
**Also called:** outline fill, ink-in typography. **Does:** begins as outlined display type and fills with color or imagery. **Replicate:** layer an outlined copy using `-webkit-text-stroke` beneath a filled copy clipped with `clip-path`, then animate the filled layer's reveal. SVG text gives more consistent stroke control. **Label:** Native.

### 029. Media-Filled Text
**Also called:** video text mask, image-clipped headline. **Does:** displays moving photography or video only inside large letterforms. **Replicate:** use an SVG `<mask>` containing text over an image/video, or `background-clip: text` for simpler image treatments; provide a solid-color text fallback and preserve contrast around the silhouette. **Label:** Native / GPU.

### 030. Liquid Distortion Type
**Also called:** wavy text, refracted wordmark, heat-haze lettering. **Does:** bends glyphs like water, glass, or heat. **Replicate:** distort an SVG text layer with `feTurbulence` plus `feDisplacementMap`, animate the noise seed/base frequency sparingly, or sample a text texture in a fragment shader for pointer-reactive refraction. **Label:** GPU / heavy.

### 031. Text on a Motion Path
**Also called:** path typography, route label. **Does:** bends copy along a curve and can move it around that curve. **Replicate:** use SVG `<textPath>` for real curved text and animate `startOffset`; for a moving badge, use CSS `offset-path: path()` or the newer `shape()` syntax. **Label:** Native / Progressive.

### 032. Circular and Orbital Type
**Also called:** seal text, spinning type ring. **Does:** wraps labels around a circle for badges, cursors, stamps, and orbiting CTAs. **Replicate:** use SVG text on a circular path, or position individual letters with rotated CSS transforms; rotate the parent slowly and stop under reduced motion. **Label:** Native.

### 033. Count-Up Stats
**Also called:** animated counters, metric roll-up. **Does:** interpolates from a starting value to a final KPI as it enters view. **Replicate:** observe once with IntersectionObserver and animate a numeric value with `requestAnimationFrame`, Motion, or CountUp.js; format every frame with `Intl.NumberFormat` and expose the final value as the semantic text. **Label:** Native / Library.

### 034. Odometer Number Roll
**Also called:** rolling digits, mechanical counter. **Does:** moves each digit vertically like a meter instead of crossfading the entire number. **Replicate:** give each digit a clipped column containing 0 to 9, translate each column to its target digit with a spring, and stagger place values; Odometer.js or a Motion component handles carry transitions. **Label:** Library.

### 035. Split-Flap Display
**Also called:** Solari board, departure board, flip clock. **Does:** flips individual character tiles through intermediate glyphs before landing on new text or a price. **Replicate:** create front/back half-panels with `perspective` and 3D rotations, queue glyph changes per cell, and add a restrained click sound only after opt-in; use a maintained split-flap component for timing. **Label:** Library.

### 036. Slot-Machine Word Rotator
**Also called:** vertical word reel, phrase cycler. **Does:** swaps one keyword in a headline by rolling a vertical list through a clipped window. **Replicate:** keep equal-height rows in an overflow-hidden track, translate to the active index, and crossfade/blur around the midpoint; measure row height with ResizeObserver. **Label:** Native / Library.

### 037. Rolling Link Labels
**Also called:** double-label hover, text roll-up. **Does:** replaces a link label with a duplicate that rolls in from below or the side. **Replicate:** stack two identical labels in a clipped span and translate both on hover and focus-visible; mark the duplicate `aria-hidden`. This gives navigation motion without changing layout. **Label:** Native.

### 038. Auto-Balanced Headlines
**Also called:** balanced wrap, editorial heading rag. **Does:** distributes words more evenly across short headline lines. **Replicate:** apply `text-wrap: balance` or `text-wrap-style: balance` to headings, limit the measure, and let normal wrapping be the fallback. **Label:** Native.

### 039. Pretty Body Wrapping
**Also called:** orphan-aware copy, refined paragraph rag. **Does:** improves paragraph line breaks and reduces awkwardly short last lines. **Replicate:** use `text-wrap: pretty` on editorial body copy and cap line length around 55 to 75ch; do not apply it indiscriminately to huge dynamic text regions because the algorithm costs more. **Label:** Native.

### 040. Scroll-Scale Display Type
**Also called:** cinematic type zoom, typographic camera move. **Does:** lets an oversized word grow, compress, or pass behind content as a section progresses. **Replicate:** pin a clipped heading layer and map scroll progress to scale, tracking, and translation; animate a wrapper transform for performance and keep readable body copy outside the effect. **Label:** Library / Progressive.

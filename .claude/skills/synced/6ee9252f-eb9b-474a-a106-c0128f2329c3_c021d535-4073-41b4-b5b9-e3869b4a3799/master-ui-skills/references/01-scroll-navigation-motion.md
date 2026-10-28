# 1. Scroll, navigation, and narrative motion

Entries 001 to 020. Techniques that turn scroll position and navigation into motion, reveals, and story. Apply the five production rules from SKILL.md to every item, especially the reduced-motion fallback and keyboard preservation.

### 001. Scroll Progress Bar
**Also called:** reading indicator, page progress line. **Does:** shows how far the visitor has moved through a page or article. **Replicate:** scale a fixed bar from 0 to 1 with CSS `animation-timeline: scroll(root)` and `transform-origin: left`; use Motion `useScroll()` or a passive scroll listener as fallback. **Label:** Native / Progressive.

### 002. Condensing Sticky Header
**Also called:** shrink-on-scroll nav, compacting masthead. **Does:** turns a spacious header into a smaller utility bar once content moves beneath it. **Replicate:** make the outer shell `position: sticky`; toggle a stuck/scrolled state with a scroll-state container query where supported, or IntersectionObserver on a one-pixel sentinel; animate height visually with inner transforms and opacity. **Label:** Native / Progressive.

### 003. Reveal-on-Up Header
**Also called:** smart header, direction-aware nav. **Does:** hides navigation while the user scrolls down and returns it immediately when they reverse direction. **Replicate:** compare the current scroll position with the previous one, ignore tiny deltas, and translate the header by -100%; Motion `useScroll()` plus a motion-value change event or GSAP Observer makes the state logic tidy. **Label:** Library / Native.

### 004. Scroll-Linked Word Reveal
**Also called:** read-along highlight, Apple-style paragraph reveal. **Does:** progressively changes words from muted to fully legible as the reader advances. **Replicate:** split text into accessible word spans, drive a staggered opacity/color timeline with CSS `view()` or GSAP ScrollTrigger, and keep the original sentence available to screen readers. **Label:** Progressive / Library.

### 005. Scroll-Driven Decode
**Also called:** scroll-linked scramble, cipher resolve. **Does:** converts randomised characters into readable copy in proportion to scroll progress. **Replicate:** use GSAP ScrollTrigger to scrub ScrambleTextPlugin, or map view progress to the number of final characters revealed while randomising only the unresolved suffix. **Label:** Library.

### 006. View-Progress Entrance
**Also called:** view-timeline reveal, native reveal-on-scroll. **Does:** makes an element fade, rise, rotate, or settle as it crosses the viewport instead of merely firing once. **Replicate:** define keyframes, add `animation-timeline: view()`, and tune `animation-range` such as `entry 0% entry 70%`; use `animation-fill-mode: both`. **Label:** Progressive.

### 007. Layered Scroll Parallax
**Also called:** depth scroll, multi-plane parallax. **Does:** moves foreground, subject, and background at different rates to imply camera depth. **Replicate:** keep layers in one clipped scene and map scroll progress to small `translate3d` ranges; use Motion `useTransform`, GSAP ScrollTrigger, or CSS scroll timelines. Keep text movement subtle. **Label:** Library / Progressive.

### 008. Infinite Marquee
**Also called:** ticker, logo loop, conveyor strip. **Does:** repeats content in a seamless horizontal or vertical loop. **Replicate:** duplicate the sequence once, place both copies in a flex track, animate exactly one copy-width, mark the duplicate `aria-hidden`, and pause on hover/focus if it contains useful content; React Fast Marquee or Embla Auto Scroll handles edge cases. **Label:** Native / Library.

### 009. Velocity Marquee
**Also called:** scroll-speed ticker, directional speed line. **Does:** changes the marquee speed, direction, or skew in response to scroll velocity. **Replicate:** derive velocity from Motion `useVelocity()` or Lenis/GSAP scroll data, smooth it with a spring, then map it to playback rate and a small skew. Clamp extremes to prevent nausea. **Label:** Library.

### 010. Sticky Stacking Cards
**Also called:** pinned pile, deck scroll, card stack. **Does:** lets successive cards land over earlier cards while the page continues downward. **Replicate:** give each card `position: sticky`, a shared top offset, increasing `z-index`, and enough parent height; optionally scale and dim previous cards with a view timeline. **Label:** Native / Progressive.

### 011. Horizontal Pinned Scroll
**Also called:** sideways story, pinned gallery. **Does:** converts a portion of vertical travel into a horizontal gallery or timeline while the stage stays fixed. **Replicate:** calculate `trackWidth - viewportWidth`, pin the stage, and map progress to `translateX`; GSAP ScrollTrigger `pin` is the most battle-tested, while sticky positioning plus Motion/CSS timelines is lighter. Preserve wheel and keyboard expectations. **Label:** Library.

### 012. Scrollytelling Pinned Stage
**Also called:** sticky narrative, stepper story. **Does:** keeps one visualisation in place while adjacent text steps update its state. **Replicate:** use a sticky media panel, observe each semantic story step with IntersectionObserver, and animate between explicit states using Motion, GSAP, D3, or a Rive state machine. Ensure every state also has readable text. **Label:** Native / Library.

### 013. Image-Sequence Scrub
**Also called:** frame-by-frame product scroll, canvas sequence. **Does:** lets scroll rotate, assemble, or explode a photoreal object through pre-rendered frames. **Replicate:** export an AVIF/WebP sequence, preload a small lead window, draw the nearest frame to Canvas, and map scroll progress to frame index; use GSAP ScrollTrigger or Motion for the mapping. **Label:** GPU / heavy.

### 014. Scroll-Linked SVG Path Draw
**Also called:** route tracing, line-draw timeline. **Does:** reveals a line, signature, map route, or diagram as the page advances. **Replicate:** obtain the path length with `getTotalLength()`, set matching `stroke-dasharray` and `stroke-dashoffset`, then animate the offset to zero with a scroll timeline, GSAP DrawSVG, or Motion. **Label:** Native / Library.

### 015. Scroll Mask Wipe
**Also called:** curtain reveal, directional crop, section unveil. **Does:** exposes media or the next section through an expanding geometric window. **Replicate:** animate `clip-path: inset()` or a CSS/SVG mask from closed to open on a view timeline; for maximum smoothness, animate a transform on an oversized mask layer. **Label:** Native / Progressive.

### 016. Scroll-Velocity Skew
**Also called:** momentum typography, speed distortion. **Does:** briefly leans images or type in the direction of fast scrolling and relaxes when scrolling stops. **Replicate:** read scroll velocity, map it to roughly -4deg to 4deg, spring the value back to zero, and apply `skewY()` or `skewX()` to a wrapper. **Label:** Library.

### 017. Scroll-Linked Blur and Depth of Field
**Also called:** focus pull, rack-focus scroll. **Does:** shifts attention by bringing the current layer into focus while neighbouring layers blur and fade. **Replicate:** map view progress to `filter: blur()` and opacity, or use WebGL post-processing for true depth of field; keep blur ranges small because CSS filters can be paint-heavy. **Label:** Native / GPU.

### 018. Zoom-Through Portal
**Also called:** tunnel transition, scale-through scene. **Does:** makes the camera appear to pass through a word, image, doorway, or device frame into the next section. **Replicate:** pin a scene, animate scale and translation over a long scroll range, reveal the destination behind a mask, and swap layers near the crossover; GSAP timelines or Three.js cameras give the cleanest choreography. **Label:** Library / GPU.

### 019. Scroll-Snap Chapters
**Also called:** snap storytelling, full-page panels. **Does:** gently settles scrolling onto discrete slides or chapters without a custom scroll engine. **Replicate:** apply `scroll-snap-type` to the container and `scroll-snap-align` to children; add native `::scroll-marker`/`::scroll-button` progressively or use an accessible dot navigation fallback. Avoid mandatory snapping on long text. **Label:** Native / Progressive.

### 020. Inertial Smooth Scroll
**Also called:** lerped scroll, cinematic scrolling. **Does:** softens wheel input so motion has weight and synchronises DOM and WebGL animation. **Replicate:** initialise Lenis and feed its frame loop into GSAP or your renderer; retain native scrolling on touch and reduced-motion modes, and never use smoothing to block keyboard, anchor, or find-in-page behaviour. **Label:** Library.

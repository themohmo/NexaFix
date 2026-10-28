# 3. Pointer, touch, and micro-interaction

Entries 041 to 060. Cursor effects, hover treatments, button physics, and gestures. Treat most of these as desktop enhancements: disable or simplify them under `(hover: none)` and always mirror hover behaviour on `:focus-visible` and provide keyboard/touch equivalents.

### 041. Spotlight Cursor
**Also called:** flashlight, torch glow, cursor halo. **Does:** reveals color, texture, or brighter contrast in a radial area around the pointer. **Replicate:** write pointer coordinates to `--x` and `--y`, then position a `radial-gradient()` mask/background with those variables; update through `requestAnimationFrame` and disable when `(hover: none)`. **Label:** Native.

### 042. Custom Cursor Follower
**Also called:** trailing cursor, context cursor. **Does:** replaces or supplements the pointer with a lagging ring that changes for links, media, and drag zones. **Replicate:** keep the system cursor unless the custom one is fully reliable, spring a fixed `pointer-events:none` element toward pointer coordinates, and change state through `data-cursor` attributes. **Label:** Library / Native.

### 043. Magnetic Buttons
**Also called:** gravity CTA, attraction hover. **Does:** pulls a button and its label slightly toward the nearby pointer, making the target feel physical. **Replicate:** measure pointer offset from button center, map it to a small translate, and lerp/spring back on leave; GSAP quickTo or Motion springs prevent jitter. Keep the hit area stationary. **Label:** Library / Native.

### 044. 3D Tilt Cards
**Also called:** pointer parallax, perspective card. **Does:** rotates a card toward the pointer while inner layers appear at different depths. **Replicate:** calculate normalised pointer position, apply `perspective()` plus small `rotateX/rotateY`, translate selected children on Z, and spring to zero; Atropos or vanilla-tilt handles touch and glare. **Label:** Library.

### 045. Mouse-Parallax Layers
**Also called:** depth float, pointer parallax. **Does:** shifts several visual layers by different fractions of pointer movement without rotating the whole card. **Replicate:** normalise coordinates around the container center, multiply by per-layer depth factors, then interpolate `translate3d`; Atropos or a short RAF loop works well. **Label:** Native / Library.

### 046. Holographic Glare
**Also called:** trading-card shine, foil glare. **Does:** moves a bright specular reflection and rainbow tint across a card as it tilts. **Replicate:** combine a pointer-positioned radial highlight, a conic/repeating gradient, `mix-blend-mode`, and a mask; pair with 3D tilt and reduce opacity to keep text readable. **Label:** Native.

### 047. Cursor Trail
**Also called:** ghost trail, ribbon cursor, pointer echoes. **Does:** leaves fading dots, shapes, or small images behind movement. **Replicate:** reuse a fixed pool of elements or canvas particles, emit only after a distance threshold, and decay scale/opacity over time; avoid creating DOM nodes on every pointer event. **Label:** Native / Canvas.

### 048. Particle Cursor Field
**Also called:** interactive dust, pointer repulsion. **Does:** attracts, repels, or swirls a field of particles around the pointer. **Replicate:** run particles in Canvas 2D, PixiJS, or a GPU shader, use a spatial grid for many points, and pause when offscreen or hidden. **Label:** GPU / heavy.

### 049. Hover Preview Follower
**Also called:** cursor image preview, link thumbnail follow. **Does:** shows an image or video preview near the pointer while a project or article link is hovered. **Replicate:** keep one fixed preview layer, swap its media on link enter, spring it toward pointer coordinates, and clip/reveal the new media; anchor it statically for keyboard focus. **Label:** Library / Native.

### 050. Proximity-Reveal Labels
**Also called:** near-pointer navigation, latent labels. **Does:** reveals annotations or controls only when the pointer approaches a hotspot. **Replicate:** compute distance from pointer to each hotspot's center, map distance to opacity/scale, and include visible-on-focus behaviour. Use sparingly because hidden affordances reduce discoverability. **Label:** Native.

### 051. Clip-Path Hover Reveal
**Also called:** mask wipe, iris reveal. **Does:** reveals alternate media, color, or copy through an expanding shape on hover. **Replicate:** stack two layers and animate the top one from `clip-path: circle(0 at var(--x) var(--y))` to a large circle; set the origin from pointer coordinates and mirror it on focus-visible. **Label:** Native.

### 052. Liquid-Fill Button
**Also called:** fluid CTA, wave fill. **Does:** fills a button with a moving liquid edge while the label color inverts. **Replicate:** animate an oversized pseudo-element upward behind the label, shape its edge with rounded blobs or an SVG wave, and clip to the button; a simple transform keeps it smooth. **Label:** Native.

### 053. Elastic Pill Button
**Also called:** squishy CTA, spring button. **Does:** subtly stretches toward the press or pointer and rebounds with physical overshoot. **Replicate:** change scale independently on X/Y around the interaction point, drive release with a spring, and keep deformation under roughly 8% so the label remains crisp. Motion or GSAP elastic easing is convenient. **Label:** Library / Native.

### 054. Ripple and Tap Feedback
**Also called:** ink ripple, touch pulse. **Does:** confirms the exact press location with an expanding circle. **Replicate:** set CSS variables from the pointer point, scale a pseudo-element from zero, then fade it; recycle the same element or use Web Animations API. Respect overflow and rounded corners. **Label:** Native.

### 055. Morphing Icon
**Also called:** animated icon transition, path morph. **Does:** transforms one symbol into another, play/pause, search/close, plus/check, without a hard swap. **Replicate:** use compatible SVG paths and GSAP MorphSVG or Flubber, or design a single stroked icon whose dash offsets and rotations create both states. Preserve the button's accessible name. **Label:** Library / SVG.

### 056. Hold-to-Confirm Control
**Also called:** press-and-hold button, radial confirmation. **Does:** makes a destructive or high-consequence action require a deliberate hold while progress fills around it. **Replicate:** start a timer on pointer/keyboard press, animate an SVG circle's stroke, cancel on release or leave, and fire only at completion; provide a non-hold accessible alternative. **Label:** Native.

### 057. Inertial Draggable Cards
**Also called:** tossable cards, momentum drag. **Does:** lets users grab, throw, and settle cards with velocity-based motion. **Replicate:** use Pointer Events with pointer capture, estimate release velocity, constrain or snap the result, and animate inertia with Motion drag or GSAP Draggable plus InertiaPlugin. **Label:** Library.

### 058. Swipe-to-Dismiss
**Also called:** gesture dismissal, swipe action row. **Does:** dismisses a card or reveals contextual actions based on drag direction and threshold. **Replicate:** lock to the horizontal axis, map drag distance to translation/rotation/opacity, commit using distance or velocity, and expose equivalent buttons for keyboard and assistive tech. **Label:** Library.

### 059. Spring Toggle and Sliding Segment
**Also called:** morphing switch, pill selector. **Does:** moves one physical-looking thumb or highlight between states instead of redrawing controls. **Replicate:** use one absolutely positioned indicator, animate it with a spring or Motion `layoutId`, and keep native radio/checkbox inputs underneath for semantics. **Label:** Native / Library.

### 060. Morphing Hamburger Navigation
**Also called:** menu-to-close icon, expanding nav. **Does:** morphs the menu trigger into a close icon while a panel, curtain, or radial menu opens. **Replicate:** rotate and translate three CSS bars or morph SVG paths, open a real dialog/popover, trap or manage focus correctly, and animate the panel with top-layer entry/exit transitions. **Label:** Native / Progressive.

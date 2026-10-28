# 4. Surfaces, colour, masking, and compositing

Entries 061 to 080. Gradients, glass, blend modes, texture, and colour systems. Watch contrast over every possible background, add grain to prevent gradient banding, and keep continuously animated SVG filters off mobile.

### 061. Animated Mesh Gradient
**Also called:** multi-point gradient, liquid color field. **Does:** creates a soft, art-directed field of colors that drift into one another. **Replicate:** layer several large blurred radial gradients and animate their transforms, use Granim.js for a simple canvas, or render a mesh/fragment shader for true interpolation. **Label:** Native / GPU.

### 062. Aurora Ribbon Gradient
**Also called:** northern-lights background, spectral ribbon. **Does:** produces luminous folded bands across a dark field. **Replicate:** stack skewed blurred gradients with screen blending, animate their scale/translation at different speeds, or use a noise-warped shader for richer motion. Add grain to prevent banding. **Label:** Native / GPU.

### 063. Pointer-Reactive Radial Lighting
**Also called:** moving ambient light, card spotlight. **Does:** makes a surface brighten around the pointer as if lit by a moving lamp. **Replicate:** update `--x`/`--y`, use them inside a radial-gradient pseudo-element, and combine with a subtle border highlight; constrain updates to the hovered region. **Label:** Native.

### 064. Animated Conic-Gradient Border
**Also called:** rotating spectrum frame, energy ring. **Does:** moves color around a border without rotating the card content. **Replicate:** place a conic-gradient on a pseudo-element behind the card, mask out its center, and animate a registered angle custom property via `@property`; provide a static gradient fallback. **Label:** Native / Progressive.

### 065. Film Grain Overlay
**Also called:** noise texture, analog tint. **Does:** breaks digital smoothness and unifies photographs, gradients, and flat color. **Replicate:** use a tiny tiled noise image or an SVG `feTurbulence` filter on a fixed `pointer-events:none` overlay; keep opacity around 2 to 6% and avoid animating large SVG filters continuously on mobile. **Label:** Native.

### 066. Halftone and Dither Treatment
**Also called:** newspaper dots, ordered dithering, pixel grain. **Does:** converts tones into dots or pixels for a print, retro-computing, or editorial texture. **Replicate:** use SVG filter primitives, a CSS radial repeating pattern plus blend modes, or preprocess images; for live color/image effects, use Canvas/WebGL dithering. **Label:** Native / GPU.

### 067. Frosted Glass Panel
**Also called:** glassmorphism, translucent blur card. **Does:** lets the background show through a softly blurred, tinted surface. **Replicate:** use a translucent background, `backdrop-filter: blur()` and saturation, a one-pixel luminous border, and a solid fallback. Keep blur moderate and verify contrast over every possible background. **Label:** Native.

### 068. Refractive Glass Card
**Also called:** distorted glass, lens panel. **Does:** bends the background near edges so the surface feels like thick physical glass rather than a flat blur. **Replicate:** sample the underlying scene in WebGL and distort UV coordinates using a normal map; for a DOM approximation, combine backdrop blur, inner highlights, edge masks, and a displaced duplicate background. **Label:** GPU / heavy.

### 069. Liquid Glass Lens
**Also called:** blob lens, magnifying fluid cursor. **Does:** moves a rounded lens that magnifies and warps content beneath it. **Replicate:** use an SVG displacement filter for a limited region or render the content to a WebGL texture and apply refraction inside a signed-distance-field blob; spring the lens to the pointer. **Label:** GPU / heavy.

### 070. Iridescent Holographic Surface
**Also called:** pearlescent foil, spectral sheen. **Does:** shifts hues and highlights with pointer angle to imitate diffraction. **Replicate:** combine conic and repeating-linear gradients, soft radial glare, screen/color-dodge blending, and a noise mask; derive gradient position and rotation from tilt values. **Label:** Native.

### 071. Chromatic Aberration
**Also called:** RGB split, prism fringe. **Does:** separates red, green, and blue edges during hover, velocity, or transitions. **Replicate:** layer three copies with channel-colored blending and tiny opposing translations, use an SVG filter, or add a post-processing shader pass. Trigger briefly; persistent separation hurts readability. **Label:** Native / GPU.

### 072. Duotone Image Tint
**Also called:** two-color photography, posterized tint. **Does:** remaps shadows and highlights to a controlled brand pair. **Replicate:** use an SVG color matrix/component transfer filter, blend a grayscale image with colored layers, or preprocess assets. Tie the two colors to CSS custom properties for theme changes. **Label:** Native.

### 073. Animated Gradient Map
**Also called:** palette remap, color-ramp image. **Does:** replaces image luminance with multiple art-directed colors that can shift over time. **Replicate:** sample the image's luminance in a fragment shader and look it up in a gradient texture; an SVG component-transfer approximation works for static ramps. **Label:** GPU.

### 074. Mix-Blend Cutout
**Also called:** blend-mode type, inversion layer. **Does:** makes text or shapes interact with imagery by inverting, multiplying, or screening what is behind them. **Replicate:** place the element in a controlled isolation context and use `mix-blend-mode: difference`, `screen`, or `multiply`; add a normal-blend fallback for unpredictable backgrounds. **Label:** Native.

### 075. Neon Bloom
**Also called:** emissive glow, cyber light. **Does:** gives lines, type, and 3D objects a luminous halo. **Replicate:** layer restrained `text-shadow`/`box-shadow` values for DOM elements, or use selective bloom through Three.js EffectComposer for a scene; keep a crisp core so edges do not become mushy. **Label:** Native / GPU.

### 076. Traveling Border Beam
**Also called:** border tracer, comet border. **Does:** sends a short bright segment around a card or CTA perimeter. **Replicate:** animate a conic-gradient behind a masked center, move a gradient along an SVG rounded-rectangle path, or use CSS `offset-path`; fade the tail with a mask. **Label:** Native / SVG.

### 077. Shimmer and Skeleton Sweep
**Also called:** loading shimmer, light pass. **Does:** indicates pending content with a soft moving highlight rather than a frozen blank. **Replicate:** animate the background position of a narrow linear gradient across stable placeholder geometry; stop when content loads and disable the sweep under reduced motion. **Label:** Native.

### 078. CSS Mask Reveal
**Also called:** texture wipe, ink reveal, gradient mask. **Does:** reveals content using soft, irregular, or image-shaped transparency rather than a hard clip. **Replicate:** animate `mask-position`, `mask-size`, or a gradient stop; use an SVG/PNG alpha texture for brushed or smoky edges and provide an opacity fallback. **Label:** Native.

### 079. Shape-Morphed and Squircle Corners
**Also called:** superellipse card, notched/beveled panel. **Does:** moves beyond generic rounded rectangles with squircle, scoop, bevel, or notch silhouettes. **Replicate:** use the new `corner-shape` with `border-radius` progressively, the CSS `shape()` function for responsive clips/paths, or an SVG mask fallback. **Label:** Progressive.

### 080. Perceptual and Adaptive Color System
**Also called:** OKLCH theming, relative-color tokens. **Does:** generates consistent hover, border, tint, and dark-mode colors without muddy interpolation. **Replicate:** define seeds in `oklch()`, derive states with relative color syntax and `color-mix(in oklab, ...)`, and use `contrast-color()` progressively for black/white foreground choices. **Label:** Native / Progressive.

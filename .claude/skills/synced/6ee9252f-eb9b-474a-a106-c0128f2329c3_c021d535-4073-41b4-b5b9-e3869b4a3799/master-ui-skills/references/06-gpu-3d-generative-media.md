# 6. GPU, 3D, generative, and rich-media experiences

Entries 101 to 120. Shaders, 3D scenes, simulations, and heavy media. Every item here needs a real performance budget: lower resolution and sample counts on mobile, cap device pixel ratio, pause when offscreen, lazy-load behind a poster, and provide a static or reduced-motion cut.

### 101. WebGL Shader Backdrop
**Also called:** fragment-shader background, generative hero. **Does:** renders fluid light, caustics, noise, gradients, or abstract materials in real time. **Replicate:** draw a full-screen triangle, write a fragment shader using time/resolution uniforms, and add pointer coordinates for interaction; Three.js ShaderMaterial, React Three Fiber, OGL, or ShaderGradient reduces setup. **Label:** GPU / heavy.

### 102. Mouse-Reactive Shader Distortion
**Also called:** cursor warp, interactive heat field. **Does:** bends an image or gradient around the pointer with a soft trailing response. **Replicate:** pass normalised pointer position and velocity into a fragment shader, accumulate a small displacement field or use noise around the cursor, and spring the uniforms rather than snapping them. **Label:** GPU / heavy.

### 103. Metaball Field
**Also called:** liquid blobs, merging orbs. **Does:** makes separate circles fuse into one fluid surface when they approach. **Replicate:** for a small monochrome effect, blur circles and apply a high-contrast filter; for clean multicolor results, sum signed-distance fields in a fragment shader and threshold the field. **Label:** Native / GPU.

### 104. Fluid Simulation
**Also called:** ink flow, smoke field, cursor fluid. **Does:** creates dye, velocity, and vortices that react to touch or pointer movement. **Replicate:** use ping-pong framebuffers with advection, pressure, divergence, and dye shader passes, or start from a maintained WebGL fluid implementation; reduce simulation resolution aggressively on mobile. **Label:** GPU / heavy.

### 105. Generative Particle Field
**Also called:** dust cloud, star field, point swarm. **Does:** builds atmosphere or forms images/type from thousands of moving points. **Replicate:** use Canvas for hundreds of particles, PixiJS for sprites, or instanced points in Three.js/WebGPU for thousands; move attributes in shaders and pause when not visible. **Label:** GPU / heavy.

### 106. Interactive Constellation
**Also called:** connected particles, network field. **Does:** draws lines between nearby nodes and lets the pointer attract or repel the network. **Replicate:** store particles in Canvas/WebGL, use a spatial grid to avoid checking every pair, draw connections under a distance threshold, and cap line count. **Label:** GPU / heavy.

### 107. Displacement Image Transition
**Also called:** liquid image wipe, texture displacement. **Does:** warps one image into another using a noise or direction map instead of a simple fade. **Replicate:** load both images and a displacement texture into a fragment shader, offset their UVs in opposite directions as progress changes, and crossfade near the midpoint. **Label:** GPU / heavy.

### 108. Vertex-Distortion Hover
**Also called:** cloth image hover, mesh warp. **Does:** bends a flat image plane like fabric, rubber, or a wave when hovered. **Replicate:** subdivide a plane, displace vertices with noise and pointer distance in a vertex shader, then spring the deformation amplitude back to zero; React Three Fiber simplifies scene wiring. **Label:** GPU / heavy.

### 109. Noise Dissolve Transition
**Also called:** particle dissolve, burn-in reveal. **Does:** makes an object appear or disappear through an irregular granular edge. **Replicate:** compare a noise texture against animated progress in the fragment shader, discard pixels below the threshold, and color a narrow threshold band as a glowing edge. **Label:** GPU / heavy.

### 110. Post-Processing Stack
**Also called:** cinematic pass chain, realtime grading. **Does:** adds bloom, depth of field, vignette, film grain, glitch, and color grading after a 3D scene renders. **Replicate:** render through Three.js EffectComposer, add only the required passes, and lower resolution/sample count on mobile. Effects should support the art direction rather than hide weak composition. **Label:** GPU / heavy.

### 111. Interactive 3D Product Viewer
**Also called:** orbit viewer, product configurator. **Does:** lets users rotate, zoom, recolor, and inspect a real-time product. **Replicate:** export an optimised glTF/GLB, load it with Three.js or React Three Fiber/Drei, use orbit controls with limits, bake lighting where possible, and lazy-load behind a poster image. **Label:** GPU / heavy.

### 112. Scroll-Driven 3D Camera Journey
**Also called:** camera fly-through, spatial scrollytelling. **Does:** moves the viewer through a 3D scene as narrative sections progress. **Replicate:** author camera position/target keyframes, place them on a GSAP/Motion scroll timeline, interpolate with curves, and sync DOM labels to scene states; keep a reduced-motion cut or dissolve version. **Label:** GPU / heavy.

### 113. 3D Hotspots and Exploded View
**Also called:** product annotations, part callouts. **Does:** separates components and anchors labels to meaningful points on a 3D model. **Replicate:** animate named model groups along authored vectors, project each hotspot's 3D position to screen coordinates every frame, and occlude or hide labels when their anchor is behind the model. **Label:** GPU / heavy.

### 114. Signed-Distance-Field Text
**Also called:** shader text, infinite-scale glyphs. **Does:** renders crisp 3D/canvas text that can glow, outline, distort, or transition without raster blur. **Replicate:** generate an MSDF/SDF font atlas, render glyph quads, and use distance thresholds in the fragment shader for fill and stroke; Troika Three Text is a practical Three.js route. **Label:** GPU.

### 115. Rive State-Machine Illustration
**Also called:** interactive vector character, stateful motion graphic. **Does:** lets a designer-authored illustration react to hover, drag, form state, data, and multistep logic. **Replicate:** build states and transitions in Rive, load the `.riv` file with `@rive-app/webgl2` or Canvas, and drive inputs/data bindings from UI events; stop rendering when settled/offscreen. **Label:** Library / GPU.

### 116. Interactive Lottie Animation
**Also called:** scroll-controlled vector animation, JSON motion graphic. **Does:** plays designer-exported motion illustrations and icons without shipping video. **Replicate:** load a Lottie or dotLottie file with the web player, map scroll or interaction progress to frames, and choose SVG/Canvas based on complexity; optimise layer count and avoid huge embedded raster assets. **Label:** Library.

### 117. Scroll-Scrubbed Video
**Also called:** video scrollytelling, cinematic frame scrub. **Does:** maps page progress to a video's time for high-fidelity product or scene transitions. **Replicate:** encode an intra-frame-friendly, short, muted video, preload metadata, and set `currentTime` from a throttled scroll timeline; for exact mobile scrubbing, use an image sequence or WebCodecs-based pipeline. **Label:** Media / heavy.

### 118. Pixel-Sort and Glitch Transition
**Also called:** datamosh UI, scanline glitch, digital tear. **Does:** corrupts rows, channels, or blocks briefly during a route, hover, or media change. **Replicate:** manipulate image data in Canvas, use a fragment shader with block noise and RGB offsets, or add a Three.js GlitchPass; keep it short and never apply it to essential readable text. **Label:** GPU / heavy.

### 119. WebGPU Generative Background
**Also called:** compute-driven visual, GPU particle simulation. **Does:** handles particle counts and simulations beyond comfortable DOM/Canvas ranges using modern GPU render and compute pipelines. **Replicate:** request `navigator.gpu`, configure a `webgpu` canvas, write WGSL render/compute shaders, and fall back to WebGL or a static poster when unavailable. **Label:** Progressive / GPU / heavy.

### 120. WebXR / AR Product Placement
**Also called:** try-in-room, immersive product preview. **Does:** places a 3D product into the user's environment or opens an immersive spatial scene. **Replicate:** provide an optimised glTF asset, start an `immersive-ar` WebXR session where supported, anchor the model after hit testing, and offer platform-native model viewers or a standard 3D viewer as fallback. **Label:** Progressive / GPU / heavy.

# OceanPet character sprite prompts

Generated with the built-in image generation tool, then converted from a flat
chroma-key background to an alpha PNG with the imagegen skill helper.

## SpongeBob

```text
Use case: stylized-concept
Asset type: macOS floating desktop pet pixel-art animation sprite sheet
Primary request: Create an exact 4-column by 2-row sprite sheet of SpongeBob SquarePants for a personal, non-commercial desktop pet. Eight cells total, ordered left-to-right then top-to-bottom: 1 idle smiling front view, 2 blink, 3 talking mouth open, 4 laughing and bouncing, 5 walking left, 6 walking right, 7 confused, 8 sleepy. Keep the exact same character design, scale, proportions, palette, pixel density, and light direction in every cell.
Scene/backdrop: perfectly flat solid #ff00ff chroma-key background for background removal. Thin #ff00ff gutters clearly separate all eight equally sized cells.
Style/medium: crisp hand-authored 16-bit pixel art, chunky pixels, limited palette, readable at 128 px, no antialiasing, no blur.
Composition/framing: each pose centered in its own equal cell, feet aligned to the same baseline, full body visible with generous padding, nothing crosses cell boundaries.
Constraints: recognizable yellow rectangular sponge character with large blue eyes, buck teeth, white shirt, red tie, brown square shorts, striped socks, black shoes; exactly one character per cell; no props; no extra objects; no text; no labels; no watermark. Background must be one uniform #ff00ff with no shadows, gradients, texture, reflections, floor plane, or lighting variation. Do not use #ff00ff anywhere in the character. No cast shadow, no contact shadow, no reflection.
```

## SpongeBob classic 2D cartoon replacement

Generated with the built-in image generation tool using the previous sprite sheet
as the pose/layout reference, then converted from magenta chroma key to alpha.

```text
Use case: style-transfer
Asset type: desktop-pet sprite sheet
Input image: Image 1 is the edit target and defines the character, clothing, eight poses, proportions, and exact 4-by-2 layout.
Primary request: Redraw only the character rendering from pixel art into a polished, smooth, high-resolution 2D cartoon. Keep the same character design and the same eight poses in exactly the same order.
Style/medium: clean hand-drawn cel animation, smooth antialiased dark outlines, flat saturated colors, restrained cel shading, no pixel blocks.
Composition: exactly four equal columns and two equal rows. Top row: idle smile, blink, talking, joyful. Bottom row: walk left, walk right, confused, sleepy. Exactly one complete full-body character centered inside each cell, consistent scale and baseline, generous padding, no part crossing a cell boundary.
Invariants: yellow rectangular porous sponge body; large round blue eyes; eyelashes; long nose; two buck teeth; white shirt; red tie; brown shorts; striped socks; black shoes. Keep all limbs connected and fully visible. Keep the front-facing eye locations consistent.
Background: perfectly flat uniform solid #FF00FF chroma-key background, with no gradient, texture, shadow, reflection, floor, border, or grid. Do not use #FF00FF in the character.
Constraints: no text, no watermark, no extra characters or props, no pixel art, no jagged edges, no 3D, no cropped feet, no detached or duplicated limbs, no distorted eyes, no magenta halo.
```

### SpongeBob opposite walk phase

```text
Use case: precise-object-edit
Asset type: two-frame desktop-pet walking animation refinement
Input image: Image 1 is the edit target. It contains exactly two equal side-by-side cells: left-facing walk in the left cell and right-facing walk in the right cell.
Primary request: create the opposite gait phase in both cells. Change only the walking limb positions: swap which leg is reaching forward and which leg is trailing, and swing the arms naturally in the opposite phase. The character in the left cell must still face and travel left; the character in the right cell must still face and travel right.
Invariants: preserve the exact same smooth 2D cartoon character identity, face, body, eye direction, yellow sponge shape, pores, outfit, proportions, palette, line weight, scale, cell placement, and #FF00FF background. Keep each body as one connected full-body drawing. Keep both complete shoes, legs, arms, and hands visible.
Composition: exactly two equal cells in one row, one complete centered character per cell, identical baseline and padding to Image 1, nothing crossing the midpoint or outer edge.
Constraints: background remains perfectly flat uniform solid #FF00FF; no gradients, shadows, floor, grid line, text, watermark, extra character, extra limb, detached body part, crop, pixel art, 3D, or magenta halo.
```

## Patrick Star

```text
Use case: stylized-concept
Asset type: macOS floating desktop pet pixel-art animation sprite sheet
Primary request: Create an exact 4-column by 2-row sprite sheet of Patrick Star for a personal, non-commercial desktop pet. Eight cells total, ordered left-to-right then top-to-bottom: 1 idle smiling front view, 2 blink, 3 talking mouth open, 4 laughing and bouncing, 5 walking left, 6 walking right, 7 confused, 8 sleepy. Keep the exact same character design, scale, proportions, palette, pixel density, and light direction in every cell.
Scene/backdrop: perfectly flat solid #00ffff chroma-key background for background removal. Thin #00ffff gutters clearly separate all eight equally sized cells.
Style/medium: crisp hand-authored 16-bit pixel art, chunky square pixels, limited palette, readable at 128 px, no antialiasing, no blur.
Composition/framing: landscape 3:2 canvas; each pose centered in its own equal cell; feet aligned to the same baseline; full body visible with generous padding; nothing crosses cell boundaries.
Constraints: recognizable pink starfish character with a pointed head, round friendly eyes, simple eyebrows, large smiling mouth, lime-green shorts with purple flower shapes; exactly one character per cell; no props; no extra objects; no text; no labels; no watermark. Background must be one uniform #00ffff with no shadows, gradients, texture, reflections, floor plane, or lighting variation. Do not use #00ffff anywhere in the character. No cast shadow, no contact shadow, no reflection.
```

### Patrick refinement pass

Image 1 was the first Patrick chroma-key sheet. Image 2 was the SpongeBob sheet,
used only as a pixel-density and finish-quality reference.

```text
Use case: style-transfer
Asset type: production macOS floating-companion 4-column by 2-row pixel sprite sheet.
Input images: Image 1 is the edit target, the current Patrick Star eight-pose sprite sheet. Image 2 is a style-quality reference only for pixel density, outline precision, palette discipline, scale, and amount of detail; do not insert or depict SpongeBob.
Primary request: refine Image 1 so Patrick has the same professional hand-authored 16-bit pixel-art finish and compact floating-companion readability as Image 2.
Keep the exact 4x2 layout and exact pose order from Image 1: idle, blink, talking, happy, walking left, walking right, confused, sleepy.
Required improvements: use a crisp dark 2-to-3-pixel outline; replace smooth gradients and soft edges with deliberate square pixel clusters; use a restrained flat palette with small hard-edged highlight and shadow clusters; add tasteful Patrick skin dots and subtle belly/arm definition; clean up eye, eyebrow, mouth, shorts, purple flower, hand, and foot silhouettes; make every frame use identical body proportions, palette, pixel scale, and lighting. Scale Patrick down slightly so his full-body footprint and generous padding match Image 2's character footprint. Align standing feet to one baseline.
Scene/backdrop: perfectly flat uniform solid #00ffff chroma-key background. Use only #00ffff for the entire background and gutters. No white separators.
Constraints: preserve Patrick's recognizable pink pointed starfish body, friendly round eyes, simple eyebrows, lime-green shorts, and purple flower shapes. Exactly one full-body Patrick in each cell. Preserve the intended expressions and left/right directions. No motion lines, no letter Z, no symbols, no text, no labels, no props, no extra objects, no shadows, no scenery, no watermark. Do not use #00ffff anywhere in Patrick. Nothing may cross a cell boundary.
```

## Patrick classic 2D cartoon replacement

Generated with the built-in image generation tool using the previous sprite sheet
only as the pose/layout reference, then converted from cyan chroma key to alpha.

```text
Use case: style-transfer
Asset type: production macOS floating-companion animation sprite sheet, 4 columns by 2 rows.
Input image: edit target and pose/layout reference only; replace the pixel-art rendering while preserving the eight-cell order and action meanings.
Primary request: redraw Patrick Star as a polished, classic hand-drawn 2D cel-animation character matching his familiar TV-cartoon appearance, not pixel art. Exact eight cells ordered left-to-right then top-to-bottom: 1 idle smiling front view, 2 blink, 3 talking with mouth open, 4 laughing and bouncing with arms raised, 5 walking left, 6 walking right, 7 confused scratching his head, 8 sleepy. Keep exactly the same recognizable character design, body proportions, colors, line weight, and scale across all cells.
Scene/backdrop: perfectly flat uniform solid #00FFFF chroma-key background filling the full canvas and gutters, for background removal. No shadows, gradients, texture, floor plane, reflections, or lighting variation. Do not use #00FFFF anywhere in the character.
Style/medium: clean professional traditional 2D television cel animation; smooth confident dark outlines; flat pink skin color with a few characteristic darker pink spots; expressive simple face; lime-green shorts with purple flower motifs; subtle controlled cel shading only. Smooth antialiased curves, absolutely no square pixels, no pixel-art aesthetic, no 3D, no photorealism.
Composition/framing: landscape 3:2 canvas; exact equal 4x2 grid; one full-body Patrick centered in each cell; identical character height and footprint in comparable standing poses; feet aligned to a consistent baseline; generous padding; nothing crosses cell boundaries.
Constraints: preserve recognizable pink pointed starfish body, round belly, friendly round eyes, simple eyebrows, large expressive mouth, lime-green shorts with purple flowers. Exactly one Patrick per cell. Every hand and foot complete. Walking frames clearly face opposite directions. No SpongeBob, no other characters, no props, no extra objects, no text, no labels, no symbols, no motion lines, no watermark, no cast/contact shadows. Background must be only solid #00FFFF.
```

## Squidward classic 2D cartoon sprite sheet

Generated from the approved friendly Squidward character candidate, with the
black clarinet retained in every state. The talking pose received a final
localized eye correction so each eye has one aligned pupil.

```text
Use case: style-transfer
Asset type: production macOS floating-companion animation sprite sheet, exact 4 columns by 2 rows
Input image: Image 1 is the approved friendly Squidward character design and is the visual identity reference for every frame.
Primary request: Create one exact 4-by-2 sprite sheet with eight full-body Squidward poses, ordered left-to-right then top-to-bottom: 1 relaxed idle holding his clarinet, 2 gentle blink, 3 talking with one open-hand conversational gesture, 4 happily playing the clarinet, 5 walking left, 6 walking right, 7 mildly confused while scratching his head, 8 sleepy while leaning on his clarinet. Keep the same pale blue-green skin, large rounded head, long drooping nose, relaxed friendly eyes, small restrained smile, brown short-sleeved polo shirt, and black clarinet with silver keys in all eight cells.
Scene/backdrop: perfectly flat solid #FF00FF chroma-key background across the complete canvas and gutters. No shadows, gradients, texture, scenery, floor plane, reflections, or lighting variation. Do not use #FF00FF in the character.
Style/medium: polished classic hand-drawn 2D television cel animation; smooth confident dark outlines; clean flat colors; subtle controlled cel shading; antialiased curves; gentle and approachable expression rather than angry or intimidating; no pixel art, no 3D, no photorealism.
Composition/framing: exact equal 4x2 grid; one complete character in each cell; consistent head, body, clothing, instrument, palette, line weight, and scale; full body and clarinet visible with generous transparent-ready padding; standing feet aligned; nothing crosses a cell boundary.
Constraints: clarinet must remain recognizable as black with silver keys; exactly one Squidward per cell; no SpongeBob, Patrick, or other characters; no text, labels, symbols, extra props, watermark, motion lines, cast shadows, or contact shadows.
```

### Squidward talking-eye correction

```text
Use case: precise localized character-art correction. Preserve the full-body talking pose, magenta background, body, head, mouth, shirt, hand, clarinet, legs, feet, outlines, colors, scale, and placement. Correct only the eye-and-eyelid area. Use two clean adjacent yellow eye openings under matching relaxed half-lowered eyelids. Give the eyes exactly one identical red-brown pupil each, aligned on one horizontal line and looking in the same direction. The long nose may overlap the inner eye edges naturally but must not create a duplicate pupil, sliced eye, crossed gaze, or pupil merged into the nose. Keep the expression mild, weary, friendly, and conversational.
```

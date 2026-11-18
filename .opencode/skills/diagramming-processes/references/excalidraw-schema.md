# Excalidraw schema reference

Adapted for this repository from
[github/awesome-copilot](https://github.com/github/awesome-copilot)'s
`excalidraw-diagram-generator` skill (MIT, Copyright GitHub, Inc.). The
text-binding guidance is local and corrects the upstream examples: a label is a
separate `text` element bound to its container, never a `text` property on the
container.

## File skeleton

```json
{
  "type": "excalidraw",
  "version": 2,
  "source": "https://excalidraw.com",
  "elements": [],
  "appState": {
    "viewBackgroundColor": "#ffffff",
    "gridSize": 20
  },
  "files": {}
}
```

## Element fields

Every element needs:

| Field | Type | Notes |
| --- | --- | --- |
| `id` | string | Unique in the file. Use a readable slug. |
| `type` | string | `rectangle`, `ellipse`, `diamond`, `arrow`, `line`, or `text`. |
| `x`, `y` | number | Top-left position in scene coordinates. |
| `width`, `height` | number | Element size. |
| `angle` | number | Radians; use `0`. |
| `strokeColor` | string | Hex color, normally `#1e1e1e`. |
| `backgroundColor` | string | Hex color, or `"transparent"`. |
| `fillStyle` | string | `solid`, `hachure`, or `cross-hatch`. |
| `strokeWidth` | number | Use `2`. |
| `strokeStyle` | string | `solid`, `dashed`, or `dotted`. |
| `roughness` | number | Use `1`. |
| `opacity` | number | `0` to `100`; use `100`. |
| `groupIds` | array | Use `[]` unless grouping. |
| `frameId` | string or null | Use `null`. |
| `roundness` | object or null | `{ "type": 3 }` for rounded rectangles. |
| `boundElements` | array or null | Container elements list bound text and arrows. |
| `updated` | number | Millisecond timestamp. A fixed value is fine. |
| `link` | string or null | Use `null`. |
| `locked` | boolean | Use `false`. |

The renderer does not require `index`, `seed`, `version`, `versionNonce`,
`isDeleted`, or `baseline`, but including them makes the file closer to what
Excalidraw writes. The templates include the fields that matter.

## Bound text

A container label is two elements:

1. The container has
   `boundElements: [{ "type": "text", "id": "<label-id>" }]`.
2. The text element has `containerId: "<container-id>"`, `text`,
   `originalText`, `fontSize`, `fontFamily: 5`, `textAlign`, and
   `verticalAlign`.

The text element must come after the container in the `elements` array.

```json
[
  {
    "id": "step-receive",
    "type": "rectangle",
    "x": 100, "y": 100, "width": 240, "height": 90,
    "angle": 0, "strokeColor": "#1e1e1e", "backgroundColor": "#a5d8ff",
    "fillStyle": "solid", "strokeWidth": 2, "strokeStyle": "solid",
    "roughness": 1, "opacity": 100, "groupIds": [], "frameId": null,
    "roundness": { "type": 3 },
    "boundElements": [{ "type": "text", "id": "step-receive-label" }],
    "updated": 1706659200000, "link": null, "locked": false
  },
  {
    "id": "step-receive-label",
    "type": "text",
    "x": 110, "y": 125, "width": 220, "height": 40,
    "angle": 0, "strokeColor": "#1e1e1e", "backgroundColor": "transparent",
    "fillStyle": "solid", "strokeWidth": 2, "strokeStyle": "solid",
    "roughness": 1, "opacity": 100, "groupIds": [], "frameId": null,
    "roundness": null, "boundElements": null, "updated": 1706659200000,
    "link": null, "locked": false, "text": "Receive request",
    "fontSize": 20, "fontFamily": 5, "textAlign": "center",
    "verticalAlign": "middle", "containerId": "step-receive",
    "originalText": "Receive request", "lineHeight": 1.25, "baseline": 18
  }
]
```

Sizing rule: the text element's `width` is the container width minus about 20
pixels of padding. The text `height` is roughly `fontSize * 1.25 * lines`. For a
single line centered in a 90-pixel box, `x = container.x + 10`,
`y = container.y + 25`, `width = container.width - 20`, `height = 40`.

A standalone label, such as a sequence message or a title, is a `text` element
with `containerId: null` and `boundElements: null`.

## Arrows

An arrow has:

```json
{
  "id": "edge-receive-to-validate",
  "type": "arrow",
  "x": 220, "y": 190,
  "width": 0, "height": 80,
  "angle": 0,
  "strokeColor": "#1e1e1e",
  "backgroundColor": "transparent",
  "fillStyle": "solid",
  "strokeWidth": 2,
  "strokeStyle": "solid",
  "roughness": 1,
  "opacity": 100,
  "groupIds": [],
  "frameId": null,
  "roundness": { "type": 2 },
  "boundElements": null,
  "updated": 1706659200000,
  "link": null,
  "locked": false,
  "points": [[0, 0], [0, 80]],
  "lastCommittedPoint": null,
  "startBinding": { "elementId": "step-receive", "focus": 0, "gap": 4 },
  "endBinding": { "elementId": "step-validate", "focus": 0, "gap": 4 },
  "startArrowhead": null,
  "endArrowhead": "arrow"
}
```

`points` are relative to the arrow's `x` and `y`. Keep the first point at
`[0, 0]`. An arrow that touches a shape needs `startBinding` and `endBinding`;
use `mode: "orbit"` with a `fixedPoint` at the edge, or `focus` and `gap`. An
unbound arrow looks connected but will not move with the shape. A sequence
message that marks a time position on a lifeline may use a precise unbound
arrow. Use `strokeStyle: "dashed"` for returns, responses, and asynchronous
messages.

An arrow label is a `text` element bound to the arrow:

1. The arrow's `boundElements` lists
   `{ "type": "text", "id": "edge-label" }`.
2. The text element has `containerId: "edge-receive-to-validate"`,
   `labelPosition: 0.5`, `textAlign: "center"`, and `fontFamily: 5`.
3. The text follows the arrow in the `elements` array.

Bind the label to the arrow; the renderer reserves a gap in the line for it.
All three templates show the pattern: the flowchart's `yes` and `no`, the
sequence's message labels, and the swimlane's handoff labels.

## Fonts

| `fontFamily` | Font | Use |
| --- | --- | --- |
| `5` | Excalifont | House style for all text. |
| `1` | Virgil | Legacy hand-drawn text. |
| `2` | Helvetica | Clean sans-serif, when a document requires it. |
| `3` | Cascadia | Monospace, for code-like labels. |

Use `fontFamily: 5` unless the surrounding document has a stated reason for a
different face. Use `fontSize` 16 to 24.

## Colors

| Role | Background |
| --- | --- |
| Primary | `#a5d8ff` |
| Secondary | `#b2f2bb` |
| Emphasis | `#ffd43b` |
| Warning or exception | `#ffc9c9` |
| Neutral | `#e9ecef` |

Stroke is `#1e1e1e`. Background is white. Use color to carry meaning, not
decoration: one color per participant class or outcome, consistent across the
diagram.

## Validation

- [ ] Valid JSON.
- [ ] `type: "excalidraw"`, `version: 2`, `elements`, `appState`, `files`.
- [ ] Unique IDs.
- [ ] Every shape label is a separate `text` element. Bind it with `containerId`
  when the shape may move; standalone text is acceptable only inside a fixed
  shape.
- [ ] No shape uses a `text` property.
- [ ] All text uses `fontFamily: 5`.
- [ ] Arrows have `points`; arrows that touch a shape have matching
  `startBinding` and `endBinding`.
- [ ] Every arrow label has `containerId` set to the arrow, and the arrow's
  `boundElements` lists the text.
- [ ] Colors follow the palette.
- [ ] The render shows every label.

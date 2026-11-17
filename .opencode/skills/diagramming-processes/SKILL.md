---
name: diagramming-processes
description: Use when a business process, workflow, lifecycle, or system interaction needs an Excalidraw diagram - a flow that prose serializes badly, a state machine, a message sequence, or a cross-team process. Excalidraw is the only diagram tool. Encodes the .excalidraw source and PNG render convention, bound text labels, layout and color rules, the renderer, and the same-change maintenance rule. Use whenever a document needs a graph rather than more paragraphs.
---

# Diagramming processes in Excalidraw

**REQUIRED BACKGROUND:** the `technical-writing` skill (hard rules, truth
rules, style).

## Overview

A diagram is a set of claims drawn instead of written; every box and arrow is
bound by the same truth rules as a sentence. Core principle: **diagram the
behavior (processes, lifecycles, interactions), keep the `.excalidraw` source
in version control, and treat the PNG as derived.** Excalidraw is the only
diagram tool in this repository. The prose owns the reasoning; the diagram
carries what prose serializes badly: branching, concurrency, and state.

## When to invoke, and not

Invoke when a flow, lifecycle, or interaction needs showing: a business process
spanning components or organizations, a state machine, a message exchange, the
`processes.md` of a legacy campaign (`documenting-legacy-codebases`). Do NOT
invoke to decorate: a linear flow of three or four steps is a numbered list,
and a diagram restating one is furniture. Out of scope: charts generated from
data (metrics, trends), and implementation structure, which the behavior rule
below forbids.

## Source and render

- The `.excalidraw` file is the source. It is JSON text, committed, and edited
  directly or in the Excalidraw app.
- The `.png` is rendered from the source and committed beside it for Markdown.
  It is derived; never edit it by hand.
- One diagram per source file, named for the process it shows. Put diagrams in
  a `diagrams/` directory beside the documents that embed them. In this
  repository, use `docs/diagrams/` when no local convention exists.
- Run `scripts/render-excalidraw.sh <source.excalidraw> [...]` after every
  source edit. The script writes `<source>.png` at 2x scale. It uses
  `@moona3k/excalidraw-export` 0.2.1, a pure-computation renderer with no
  browser. The first run downloads the pinned package; later runs use the npm
  cache.
- When a source changes, its PNG is regenerated in the same change. If the
  render cannot run, delete the stale PNG and record the pending render in the
  diagram index; never leave a stale image to mislead.
- A screenshot, an exported picture, or a whiteboard photo with no
  `.excalidraw` source is a finding against the document that contains it.

## The reader's question picks the layout

Pick the layout from the question the reader brings, one question per diagram:

| The reader asks | Excalidraw layout |
|---|---|
| How does this process run across teams or systems | Swimlane: actor headers, vertical lanes, handoff arrows |
| What happens, in what order, with which decisions | Flowchart: rectangles, diamonds, labeled arrows |
| Which states can this thing be in, and what moves it | State machine: rounded rectangles, labeled transitions |
| Who talks to whom, in what order, with what messages | Sequence: actor boxes, lifelines, arrows |
| What exists in this domain and how it relates | Concept map: boxes and labeled relationships |

A diagram answering two questions answers neither; split it. A diagram that
needs a legend of its own invented symbols is answering too many at once.

## Behavior, never implementation

The refactor test from `documenting-legacy-codebases` governs diagrams too, and
a diagram hides its drift better than a paragraph does:

- **Participants are systems, roles, modules, and business objects.** Classes,
  methods, and functions stay in the code.
- **Edges carry the event or condition, in the domain's language**: "payment
  confirmed", never a callback name. A guard may name a config key, because
  config keys are contract surface; it never names a method.
- **Titles name the process**, never a spec, phase, or plan: the
  no-delivery-narrative hard rule applies inside the `.excalidraw` source too,
  including text and comments.
- **Error and exception paths are drawn where behavior differs**, and drawn
  distinguishably; a happy-path-only diagram of a process with real failure
  branches is an overstated claim.
- **Quirks are drawn, and are content.** The state nothing can leave, the flow
  that skips a step for one input: the surprising branch is why the diagram
  earns its place (`documenting-legacy-codebases`, quirks).

## Excalidraw construction

### File skeleton

```json
{
  "type": "excalidraw",
  "version": 2,
  "source": "https://excalidraw.com",
  "elements": [],
  "appState": { "viewBackgroundColor": "#ffffff", "gridSize": 20 },
  "files": {}
}
```

### Element types

- `rectangle`: process steps, actors, systems, states. Use
  `roundness: { "type": 3 }` for a softer box.
- `ellipse`: start and end terminals, and some states.
- `diamond`: decisions.
- `arrow`: flow, handoffs, messages, transitions. Set `points` and binding.
- `line`: lifelines and dividers in sequence diagrams.
- `text`: every label, title, and annotation.

### Text is bound, not a shape property

Excalidraw and the renderer do not render a `text` property on a rectangle,
ellipse, or diamond. A label is a separate `text` element bound to its
container:

1. On the container, set `boundElements: [{ "type": "text", "id": "<label-id>" }]`.
2. Create a `text` element with `containerId: "<container-id>"`,
   `originalText`, `text`, `fontSize`, `fontFamily: 5`, `textAlign`, and
   `verticalAlign`.
3. Put the text element after the container in the `elements` array.

Minimal pair:

```json
[
  {
    "id": "step-receive",
    "type": "rectangle",
    "x": 100, "y": 100, "width": 240, "height": 90,
    "strokeColor": "#1e1e1e", "backgroundColor": "#a5d8ff",
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
    "strokeColor": "#1e1e1e", "backgroundColor": "transparent",
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

Use `fontFamily: 5` (Excalifont) for all text. Use `fontSize` 16 to 24. Keep
labels short; if the label does not fit, widen the box or split the step. A
shape with a `text` property and no bound text element renders as an unlabeled
box, which is a failure.

### Arrows and bindings

- Give each arrow a unique `id`, `points` starting at `[0, 0]`, and
  `startBinding` and `endBinding` when the arrow touches a box.
- Keep arrows out of boxes; bind them to the box edges.
- Put the label on the arrow as a separate `text` element near the arrow for
  predictable rendering. If you use an arrow `label` object, verify the render.
- Use straight arrows for simple flows and a small number of bends for crossing
  lanes. Do not route arrows through unrelated boxes.

### Style

- Palette: primary `#a5d8ff` (blue), secondary `#b2f2bb` (green), emphasis
  `#ffd43b` (yellow), warning or exception `#ffc9c9` (red), neutral `#e9ecef`
  (gray).
- Stroke `#1e1e1e`; background white; `roughness: 1`; `strokeWidth: 2`.
- Spacing: 200 to 300 pixels horizontally, 100 to 150 pixels vertically. Align
  boxes to a grid.
- One diagram stays under about 20 elements. If it needs more, split it by
  question or subsystem.
- IDs are readable slugs, not random: `step-receive`,
  `edge-receive-to-validate`, `lane-support`. Keep them stable when editing;
  arrows and labels reference them.

### Validation checklist

- [ ] The file is valid JSON with `type: "excalidraw"`, `version: 2`,
  `elements`, `appState`, and `files`.
- [ ] Every element has a unique `id`.
- [ ] Every label is a separate `text` element with `containerId` and a
  matching `boundElements` entry. No shape has a `text` property.
- [ ] All text uses `fontFamily: 5` and a readable `fontSize`.
- [ ] Boxes do not overlap; arrows do not cross labels.
- [ ] Colors follow the palette; exception paths are distinguishable.
- [ ] The element count is under about 20.
- [ ] The PNG renders and every label is visible.

## Rendering

```bash
scripts/render-excalidraw.sh docs/diagrams/refund-process.excalidraw
```

The script writes `docs/diagrams/refund-process.png` at 2x scale. It uses
`@moona3k/excalidraw-export` 0.2.1, a pure-computation renderer with no browser.
The first run downloads the package; later runs use the npm cache. Run
`bash -n scripts/render-excalidraw.sh` after editing the script.

## Embedding

Embed the PNG, not the source:

```markdown
![Refund process](diagrams/refund-process.png)
```

Link the source beside the image or in the diagram index so the next editor can
change it. Do not embed the `.excalidraw` file directly; browsers do not render
it. Keep the source and the PNG in the same commit.

## The diagram index

More than five diagrams get one index document beside them, a derived artifact
rebuilt from the files (core truth rules):

- A coverage table: what each diagram shows, its `.excalidraw` source, its
  `.png` render, and its status.
- Per diagram, the module it describes, as the drift anchor: the one place a
  diagram points at code.
- The render command, so the index is also the build instruction.
- Pending renders, named per source, so a missing render is a tracked state
  rather than a silent gap.

## Maintenance

A change that alters a flow updates the matching `.excalidraw` source in the
same change: a diagram is documentation, and documentation is part of done
(core truth rules). Rendering is the diagram's compile step: source edits break
syntax invisibly, and the break surfaces only when the render runs. The author
renders before shipping the edit. When a feature is removed, one change covers
the prose, the source, the PNG, the index row, and any links. A diagram nobody
can bring themselves to update is answering too big a question; split it along
the seams that change independently.

## Verification

Everything legible in a diagram is a claim (core truth rules), so a diagram is
grounded and reviewed like prose:

- Verify every box, arrow, and guard against the code before drawing it. A flow
  inferred rather than confirmed is labeled as inference beside the diagram in
  the embedding document, never silently drawn as fact.
- The reviewer reads the diagram against the behavior, and reviews the
  `.excalidraw` source text rather than the picture: the source is what the next
  editor changes.
- Open the rendered PNG and check that every label is visible and every arrow
  lands on the intended box. A blank or label-free render is a failure, not a
  style choice.
- Diagram sources drift like prose and join every legacy campaign: the campaign
  (`documenting-legacy-codebases`) grounds the diagram sources with the
  documents that embed them.
- A diagram and its surrounding prose share one home per fact: the prose says
  why the process exists and what to look out for, the diagram shows the flow,
  and neither restates the other step by step.

## References and templates

- `references/excalidraw-schema.md`: file and element schema, with the bound
  text correction.
- `references/element-types.md`: element, layout, and color guidance, with the
  bound text correction.
- `templates/flowchart.excalidraw`: flowchart starter with bound labels.
- `templates/sequence.excalidraw`: sequence starter with lifelines and labels.
- `templates/swimlane.excalidraw`: swimlane starter with lane headers and bound
  labels.

## Attribution

The process and lifecycle guidance is adapted from the `technical-writer` skill
(MIT, riekelt). The Excalidraw schema, element, and layout guidance is adapted
from [github/awesome-copilot](https://github.com/github/awesome-copilot)'s
`excalidraw-diagram-generator` skill (MIT, Copyright GitHub, Inc.). See
`UPSTREAM.md` for the pins and the local changes.

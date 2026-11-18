# Excalidraw element types and layouts

Adapted for this repository from
[github/awesome-copilot](https://github.com/github/awesome-copilot)'s
`excalidraw-diagram-generator` skill (MIT, Copyright GitHub, Inc.). The
text-binding guidance is local: labels are separate `text` elements bound with
`containerId`, never a `text` property on a shape.

## Element types

| Type | Visual | Use | Label |
| --- | --- | --- | --- |
| `rectangle` | Box | Process steps, actors, systems, states | Bound `text` element |
| `ellipse` | Circle | Start and end terminals, some states | Bound `text` element |
| `diamond` | Diamond | Decisions and guards | Bound `text` element |
| `arrow` | Arrow | Flow, handoff, message, transition | Separate `text` near the arrow |
| `line` | Line | Lifeline, divider, connector without a head | Separate `text` |
| `text` | Text | Titles, labels, annotations | Its own text |

A shape with a `text` property and no bound text element renders as an
unlabeled box. Do not use that pattern.

## Rectangle

- Process step: `#b2f2bb`, centered label.
- Actor, system, or service: `#a5d8ff`, centered label.
- Store or record: `#e9ecef`, centered label.
- Decision outcome: `#ffd43b` for the chosen path, `#ffc9c9` for the exception
  path.

Sizes:

| Content | Width | Height |
| --- | --- | --- |
| One word | 120 to 150 | 60 to 80 |
| Short phrase | 180 to 220 | 80 to 100 |
| Sentence | 250 to 300 | 100 to 120 |

Use `roundness: { "type": 3 }` for process steps and states. Use square corners
for systems and lanes.

## Ellipse

Use for start and end terminals, and for states that must read as a single
atomic condition. Keep `width === height` for a circle. Use 100 to 120 pixels
for a short label and 150 to 180 for a longer one.

## Diamond

Use one decision per diamond, with one incoming edge and two outgoing edges.
Label the outgoing edges with the conditions, not with "yes" and "no" when the
conditions are concrete. Keep the diamond at least 160 by 120 pixels so the
label fits.

## Arrow

- Straight arrows for simple flows.
- One or two bends for a handoff that crosses lanes.
- Dashed arrows for returns, responses, and asynchronous messages.
- Solid arrows for commands and forward flow.
- Label the arrow with the event or condition, in the domain's language.
- Keep arrow labels outside boxes and off other arrows.
- Bind the arrow to the shapes it touches. An arrow near a shape without a
  binding is not connected.
- Bind the label to the arrow; the renderer reserves a gap in the line for it.

Arrow binding:

```json
"startBinding": { "elementId": "step-receive", "mode": "orbit",
                  "fixedPoint": [1, 0.5] },
"endBinding": { "elementId": "step-validate", "mode": "orbit",
                "fixedPoint": [0, 0.5] }
```

The `focus` and `gap` form is also accepted.

## Text

- `fontFamily: 5` (Excalifont).
- `fontSize` 16 to 24.
- Titles may use 24 to 28; keep body labels at 18 to 20.
- `textAlign`: `center` in boxes, `left` for annotations.
- `verticalAlign`: `middle` in boxes, `top` for annotations.
- Keep a label to one or two lines. Widen the box before shrinking the font.

## Sequence layout

- Actor boxes across the top, each with a bound label.
- A dashed `line` lifeline from each actor box downward.
- Arrows between lifelines, ordered top to bottom.
- Message labels as `text` elements bound to their arrows with `containerId`
  and `labelPosition: 0.5`.
- Activation bars as narrow rectangles on a lifeline when the protocol matters.
- Time flows from top to bottom; do not route a message backward in time unless
  the protocol does.

## Swimlane layout

- One lane per actor, role, or system, as a tall rectangle with a light neutral
  fill.
- A header box at the top of each lane with the actor name.
- Process boxes inside the lane that owns the step.
- Handoff arrows cross from one lane to the next; bind each handoff arrow to its
  source and target boxes, and bind its label to the arrow.
- Keep lane widths equal and lane headers aligned to the same baseline.
- Put the start terminal in the lane that initiates the process.

## State machine layout

- Rounded rectangles for states.
- A filled circle for the initial state and a ringed circle for the final state.
- Arrows for transitions, labeled with the event and guard.
- Lay states left to right in the order a normal run visits them; put exception
  states below the main row.
- Draw self-transitions as a small loop above the state.

## Concept map layout

- Boxes for domain objects, roles, and systems.
- Labeled lines or arrows for relationships. The label is a verb phrase:
  "creates", "owns", "notifies".
- Put the most connected concept near the center.
- Keep the map at one level of abstraction; push detail into a separate
  diagram.

## Spacing and alignment

- Horizontal gap: 200 to 300 pixels.
- Vertical gap: 100 to 150 pixels.
- Align boxes to a 20-pixel grid.
- Keep a margin of at least 40 pixels around the content.
- Leave room for arrow labels; a label that overlaps an arrow is unreadable.

## Complexity

| Diagram | Recommended elements | Maximum |
| --- | --- | --- |
| Flowchart | 3 to 10 steps | 15 |
| Swimlane | 3 to 6 lanes, 2 to 4 steps per lane | 20 total |
| Sequence | 3 to 5 actors, 4 to 8 messages | 20 total |
| State machine | 3 to 8 states | 12 |
| Concept map | 3 to 8 concepts | 12 |

When the request exceeds the maximum, split it into a high-level diagram and
one detail diagram per subsystem. Say which diagram answers which question.

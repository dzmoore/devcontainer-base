# Local diagramming-processes skill

This skill is repository-owned. It is not refreshed from upstream.

## Sources

- Process and lifecycle guidance: adapted from
  [riekelt/technical-writer](https://github.com/riekelt/technical-writer),
  `plugins/technical-writer/skills/diagramming-processes`, commit
  `85e53729dd959a2795d593d6769068e342cf3486` (v1.8.4, MIT).
- Excalidraw schema, element, and layout guidance: adapted from
  [github/awesome-copilot](https://github.com/github/awesome-copilot),
  `skills/excalidraw-diagram-generator`, commit
  `a06ba06d11f41b996f8c246e2a452e1bf3a17950` (MIT, Copyright GitHub, Inc.).
- Renderer: [`@moona3k/excalidraw-export`](https://www.npmjs.com/package/@moona3k/excalidraw-export)
  0.2.1 (MIT), invoked by `scripts/render-excalidraw.sh`. It is not vendored.

Vendored: 2026-11-16.

## Local changes

- Excalidraw is the only diagram tool. The upstream PlantUML and ArchiMate
  output guidance is removed.
- The `.excalidraw` source and `.png` render convention, the renderer script,
  and the templates are local.
- Labels are bound `text` elements with `containerId`, not a `text` property on
  a shape. Excalidraw and the renderer do not render a shape `text` property.
  The references and templates correct the upstream guidance on this point.
- The diagram index, maintenance, and verification sections are adapted to the
  source and PNG pair.

# GenePen

A lightweight plasmid/DNA sequence viewer and editor for HarmonyOS devices.

## What It Does

| Feature | Status |
| --- | --- |
| Open .gb / .fa / .dna files | ✅ |
| Circular and linear plasmid maps | ✅ |
| Drag, zoom, pan navigation | ✅ |
| Restriction enzyme display (47 enzymes) | ✅ |
| Cut site visualization | ✅ |
| ORF translation (1-letter / 3-letter) | ✅ |
| Primer display and editing | ✅ |
| Sequence editing (insert, delete, undo/redo) | ✅ |
| Feature annotations | ✅ |
| Export to .gb / .fa / .dna | ✅ |
| Auto-save and session recovery | ✅ |

## Coming Soon

- Right-click context menu
- Virtual gel electrophoresis
- Restriction cloning simulation
- BLAST integration
- Multi-file tabs
- Primer Tm optimization

## How to Use

**Browser** — just open `v2.html` in any modern browser.

**HarmonyOS** — open the project in DevEco Studio, then Build & Run.

## Tech

Built as a single self-contained HTML file. No dependencies, no build tools. Runs inside a WebView on HarmonyOS with a minimal native bridge for file I/O.

## License

MIT

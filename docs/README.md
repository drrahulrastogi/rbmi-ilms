# RBMI documentation

Open `help/index.html` for the full operator and administrator manual. Open `help/printable.html` for the complete printable edition, then use your browser's Print > Save as PDF.

The CHM source consists of `help/RBMI.hhp`, `help/RBMI.hhc`, `help/RBMI.hhk`, topic HTML and `help/assets/manual.css`. Compile on Windows with `../scripts/build-chm.ps1`. No compiled CHM is included unless that command successfully finds Microsoft's HTML Help Workshop compiler.

`requirements.md` maps the authoritative requirements to implemented modules and checks. `architecture.md` describes the trust boundary, database and API contracts. `hosting-research.md` records current hosting research and links.

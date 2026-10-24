# Illustrated manual

The 24-section guide includes 38 original screenshots and 42 screen references. All screenshots use sample records and contain no real passwords. Its PDF has portrait instruction pages and landscape screen pages for legibility. HTML provides the same instructions and screenshots; Windows CHM uses those HTML sources.

Sources:

- `docs/manual-content.json`: operator instructions and limits.
- `docs/manual-screenshots.json`: screenshot captions and chapter mapping.
- `docs/help/assets/screenshots/`: original application captures.
- `scripts/build-illustrated-manual.py`: PDF, HTML and CHM project builder.

From the repository root, with Python, ReportLab and Pillow installed:

```powershell
python scripts/build-illustrated-manual.py
npm run build
```

The builder copies PDF and HTML deliverables into `manual-output` by default. Set `--output-dir` to choose another destination. In the original workspace use `--output-dir ../../outputs`. PDF and HTML also remain in `docs/help` in all cases.

To compile Windows CHM, install Microsoft HTML Help Workshop and run `scripts/build-chm.ps1`. The compiler is not bundled. The CHM project explicitly includes its screenshot assets. A compiled CHM was not produced in the development environment.

The password CSV column uses `INSTITUTE@PATRON_CODE` when blank. New student/faculty logins require a real unique email and a mandatory initial password change. Membership import and Auth account creation are separate steps; review each account result. Completed password CSVs remain private and must never be copied into documentation, Git, screenshots or public downloads. Welcome emails are not sent by this release; existing password recovery email remains available.

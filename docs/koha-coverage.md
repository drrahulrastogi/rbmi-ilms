# Supplied Koha manual coverage

|Manual/module|Implemented|Limits|
|---|---|---|
|Acquisition|vendors, orders, budgets, funds, baskets, full receipt|No EDI, partial receipts, subfund hierarchy or accounting ledger|
|Advanced search|field terms AND/OR/NOT|Simple selected-field filtering|
|Authorities|preferred headings, variants, title links|No full authority MARC editor or global replacement|
|Book migration|CSV, UTF-8 ISO2709, MARCXML|No MARC-8 conversion or lossless export|
|Circulation|issue, return, renew, FIFO holds, rules, fines|No offline/RFID/SIP2; same-library return required|
|Item search|copy identifiers, condition, checkout count/date|Current application history only|
|Lists|owner-editable private/public lists|Authenticated library visibility; no external sharing|
|OPAC|anonymous catalogue, holdings, temporary cart; linked patron loans/holds after sign-in|No purchase suggestions, tags/reviews or saved anonymous cart|
|Patrons|categories, profiles, expiry, deactivation, imports|Auth accounts provisioned separately|
|Reports|dataset/date definitions, CSV, usage|No arbitrary SQL, email scheduler|
|Serials|subscriptions, weekly/monthly/quarterly/yearly predictions, issue receiving states|No irregular calendars, automated claims or routing|

Source material: the eleven PDFs supplied by the owner in KOHA MANUAL DOCUMENTATION. This matrix describes the RBMI implementation, not full Koha feature parity.

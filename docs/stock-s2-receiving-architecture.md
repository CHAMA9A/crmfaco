# FACOLUB Receiving S2 architecture

## Scope

S2 records inbound physical goods only. It does not implement purchasing prices, production,
prepared-bottle transformation, customer orders, dispatch, or reservation changes.

## State and stock contract

- `draft`: editable through trusted RPCs; creates no stock movement.
- `confirmed`: immutable; each receipt line owns one append-only `receipt / in` stock movement.
- `cancelled`: only a draft can enter this state; it creates no stock movement.
- Confirmed receipts cannot be deleted or directly cancelled. Errors use the existing Admin stock
  correction workflow, preserving the original movement.
- A receipt changes physical stock only. Active reservations are untouched, so available stock is
  recalculated as `physical - reserved` by the S1 balance engine.

Confirmation locks the receipt row, allocates its official number, changes status, and records all
movements in one PostgreSQL transaction. A retry sees the confirmed status and returns the existing
result. A unique receipt-line movement index is a second idempotency guard.

## Numbering

Official numbers are allocated only on confirmation through an atomic daily counter. The format is
`REC-DDMMYY-NN`, matching the approved example `REC-071026-01` for 7 October 2026. Drafts consume no
number, and `MAX(...) + 1` is not used.

## Private photos

- Bucket: `facolub-receipts`, private.
- Object path: `<receipt-uuid>/<random-token>-<sanitized-file-name>`.
- Accepted types: JPEG, PNG, WebP, HEIC, and HEIF.
- Maximum stored object size: 8 MiB.
- JPEG/PNG/WebP images above 1.5 MB are resized to at most 2,000 pixels on the longest side and
  encoded as JPEG at 82% quality when that produces a smaller file.
- PostgreSQL stores metadata and the private object path, never image bytes.
- Detail screens use short-lived signed URLs. No permanent public URL is stored.
- A linked object cannot be renamed or removed through normal Storage access. A draft-only detach
  RPC removes its metadata first; confirmed evidence remains read-only.

## Authorization

- Factory, Management, and Admin can use the receiving workflow.
- Factory can read and edit only its own receipts; Management and Admin can review all receipts.
- Factory cannot insert into `stock_movements` or call arbitrary movement operations. The S1 engine
  accepts Factory only for an exact confirmed receipt line, and the confirmation RPC is the normal
  entry point.
- Admin alone manages the minimal supplier directory.
- All public tables have RLS. Mutations use validated `SECURITY DEFINER` RPCs.

## Client resilience

Text fields and receipt lines are mirrored to browser local storage while the form is open. A
temporary request failure leaves both that persisted draft and in-memory selected `File` objects in
place, and confirmation displays an explicit retryable error. Browsers do not permit durable local
storage of camera files without broader device permissions, so photos must be selected again after a
full page reload. Local data is never treated as a confirmed stock transaction.

## Manual SQL order

After Stock S1 (`020`-`024`), execute `030` through `033` in order. `034` is a rollback-only suite
covering draft isolation, confirmation, quantities, reservations, idempotency, movement permissions,
immutability, attachment linkage, and RLS. The real mobile camera/upload path is validated in the UI
because the SQL suite intentionally does not manufacture Storage binaries.

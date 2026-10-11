# Manual SQL execution order

Run these files in the Supabase SQL Editor, one at a time, and review each result before continuing:

1. `001_invoice_foundation.sql`
2. `002_invoice_authoritative_total.sql`
3. `003_invoice_numbering.sql`
4. `004_invoice_rls_and_grants.sql`
5. `005_invoice_test_data.sql` (optional, clearly labelled TEST data)
6. `006_invoice_numbering_ambiguity_fix.sql`
7. `007_issue_test_invoice_template.sql` (replace the Admin UUID placeholder first)
8. `008_invoice_role_access_verification.sql` (read-only; selects eligible test users automatically)
9. `009_invoice_creation_rpc.sql` (atomic draft creation used by the invoice form)
10. `010_orders_architecture.sql` (orders/items plus nullable legacy-safe invoice link)
11. `011_order_document_numbering.sql` (atomic daily common-reference allocator)
12. `012_delivery_transport_documents.sql` (one BL and one BT per order)
13. `013_order_documents_rls.sql` (commercial RLS and RPC-only order writes)
14. `014_order_bundle_functions.sql` (transactional/idempotent bundle workflow)
15. `015_order_documents_verification.sql` (rollback-only behavior and access tests)
16. `020_stock_foundation.sql` (stock enums, items, locations, adjustment foundation)
17. `021_stock_movement_engine.sql` (immutable physical movement ledger)
18. `022_stock_reservations.sql` (reservation ledger and derived stock balances)
19. `023_stock_rls.sql` (read policies, write revocation, safe Factory visibility)
20. `024_stock_functions.sql` (atomic movement, correction, reservation, history, and item RPCs)
21. `025_stock_verification.sql` (rollback-only stock behavior, access, and calculation tests)
22. `030_receiving_foundation.sql` (suppliers, receipt drafts, lines, and attachment metadata)
23. `031_receiving_numbering.sql` (atomic daily `REC-DDMMYY-NN` allocator)
24. `032_receiving_storage_rls.sql` (private photo bucket plus receipt/table/storage RLS)
25. `033_receiving_functions.sql` (draft editing, photo linking, atomic confirmation, and history RPCs)
26. `034_receiving_verification.sql` (rollback-only receiving, idempotency, stock, and access tests)
27. `035_receiving_demo_data.sql` (optional persistent DEMO catalog, balances, suppliers, and receipts)
28. `040_prepared_bottles_foundation.sql` (versioned recipes, preparation drafts, frozen component snapshots)
29. `041_prepared_bottle_recipes.sql` (atomic numbering and Admin recipe configuration RPCs)
30. `042_prepared_bottle_functions.sql` (requirements preview, draft workflow, atomic confirmation, history RPCs)
31. `043_prepared_bottle_rls.sql` (FACOLUB read policies and RPC-only writes)
32. `044_prepared_bottle_verification.sql` (rollback-only stock, reservation, access, and idempotency tests)
33. `050_planning_foundation.sql` (product/format catalog, multi-line production plans, lifecycle foundation)
34. `051_production_recipes.sql` (configurable carton capacities and versioned finished-product recipes)
35. `052_planning_requirements.sql` (authoritative conversions, availability preview, stable requirement snapshots)
36. `053_planning_functions.sql` (Admin configuration and Admin/Management planning RPCs)
37. `054_planning_rls.sql` (FACOLUB visibility, Factory mission scope, RPC-only writes)
38. `056_planning_quantity_mode_fix.sql` (idempotent carton-mode fall-through correction for databases that received the original 052)
39. `055_planning_verification.sql` (rollback-only conversion, shortage, history, access, and no-stock-impact tests)
40. `057_planning_final_audit.sql` (read-only final audit of the installed S4 schema, APIs, RLS, grants, and no-stock-mutation contract)
41. `060_production_reservations.sql` (plan reservation lifecycle and one-active-reservation-per-requirement foundation)
42. `061_reservation_functions.sql` (atomic reserve/release, cancellation integration, balances, and history RPCs)
43. `062_reservation_rls.sql` (RPC-only reservation mutations and FACOLUB access grants)
44. `063_reservation_verification.sql` (rollback-only snapshot, balance, role, idempotency, and atomicity tests)
45. `070_production_execution_foundation.sql` (execution, item, issue, and immutable reservation-resolution foundation)
46. `071_production_execution_functions.sql` (prepare, start, block, resolve, normalize, and completion-preview RPCs)
47. `072_production_reservation_consumption.sql` (atomic material consumption, unused release, and finished output)
48. `073_production_execution_rls.sql` (Factory mission scope, Management history, RLS, and RPC grants)
49. `074_production_execution_verification.sql` (rollback-only actual-production, stock, blocking, and idempotency tests)
50. `080_stock_counts_foundation.sql` (physical count sessions, frozen line snapshots, evidence, and safe numbering)
51. `081_stock_adjustments.sql` (loss, damage, correction, count links, movement links, and immutable evidence)
52. `082_stock_count_functions.sql` (count lifecycle, stale detection, atomic approval, and adjustment RPCs)
53. `083_stock_count_rls.sql` (role-scoped reads, RPC-only writes, and private evidence Storage)
54. `084_stock_count_verification.sql` (rollback-only count, adjustment, reservation, stale, and correction tests)

Files 001-004 and 006 contain production schema/security only. Test data is never mixed into them.

Files 010-014 are the production order-bundle migration and must be run in order, one at a time.
File 015 is a rollback-only verification suite; it requires active FACOLUB users for all three
roles and at least one active customer, and commits no test rows or numbering increments.

Files 020-024 are the production Stock S1 schema and must be run in order, one at a time.
They are additive and contain no speculative stock items; 020 seeds only `FACOLUB-MAIN`.
File 025 is rollback-only and requires one active FACOLUB user for Admin, Management, and Factory.
The S1 quantity, unit, concurrency, and future-module contract is documented in
`docs/stock-s1-architecture.md`.

Files 030-033 are the production Receiving S2 schema and must be run in order, one at a time,
after Stock S1. File 032 creates or hardens the private `facolub-receipts` Storage bucket with
an 8 MiB image limit; uploaded object names must start with the receipt UUID. File 034 is
rollback-only and requires one active FACOLUB user for Admin, Management, and Factory. Its
photo fixture validates PostgreSQL traceability metadata; a real camera/upload check remains
part of the later UI validation because binary Storage uploads are not emulated in SQL.
The S2 transaction, security, photo, and offline-resilience contracts are documented in
`docs/stock-s2-receiving-architecture.md`.

File 035 is optional and commits visible data whose codes/references start with `DEMO-`.
It is idempotent and intended for UI testing after 034 passes. Confirmed demo receipts use
metadata-only photo placeholders; use the generated Factory draft to upload a real photo
through the application before confirming it. Confirmed demo history and stock movements
are immutable by design and should not be installed in a production dataset.

Files 040-043 are the production Prepared Bottles S3 schema and must be run in order, one at a
time, after Stock S1 and Receiving S2. They are additive: drafts do not affect stock, recipes
consume only active `empty_bottle` and `label` items, and confirmations produce one active
`prepared_bottle` item through the immutable stock ledger. File 044 is rollback-only and
requires one active FACOLUB user for Admin, Management, and Factory. It creates no persistent
test rows, stock movements, reservations, or numbering increments.

Files 050-054 are the production Planning S4 schema and must be run in order, one at a time,
after Stock S1 and Prepared Bottles S3. They are additive and deliberately stop at planning:
drafting, planning, and validation calculate or snapshot future needs but never create stock
movements or reservations. Carton capacities are configurable, recipes are versioned, and
validated plans retain their historical quantities and requirement snapshots. File 056 is an
idempotent correction for databases that received the original 052 and must be applied before
rerunning 055; fresh installations already contain the same correction in 052. File 055 is
rollback-only and requires one active FACOLUB user for Admin, Management, and Factory. It
creates no persistent catalog rows, plans, recipes, stock movements, reservations, or numbering
increments. File 057 is a read-only final installation audit and changes no data.

Files 060-062 are the production Reservations S5 schema and must be run in order after S4.
They reuse `stock_reservations`: a validated plan is reserved in full from its immutable S4
requirement snapshot or not at all. Ordered stock balance locks prevent concurrent overbooking.
Reservation and release never create physical movements; cancelling a reserved plan releases
its active reservations atomically. File 063 is rollback-only, requires one active FACOLUB user
for Admin, Management, and Factory, and leaves no fixtures, movements, plans, or reservations.

Files 070-073 are the Production Execution S6 schema and must be run in order after S5.
They create one execution per reserved plan, preserve the validated requirement snapshot, and
record partial reservation resolution as immutable consumed/released quantities. Start and
Blocked states never move stock. Completion posts all material OUT movements, finished-product
IN movements, reservation resolutions, and the Done lifecycle atomically. File 074 is
rollback-only, requires one active FACOLUB user for every role, and leaves no test data.

Files 080-083 are the Physical Stock Count and Corrections S7 schema and must be run in order
after Stock S1; the installed S2-S6 history is never rewritten. Counts snapshot physical stock
and an append-only movement-count watermark under the shared stock lock. Approval is blocked if
the ledger changed after any snapshot. Factory-originated differences, losses, damage, and
corrections require Management/Admin approval. Posting creates immutable ledger movements,
preserves active reservations, and explicitly reports any over-reserved shortage. File 083
creates the private `facolub-stock-evidence` bucket with a 10 MiB limit. File 084 is rollback-only,
requires one active FACOLUB user for every role, and leaves no counts, adjustments, movements,
reservations, evidence metadata, or numbering increments.

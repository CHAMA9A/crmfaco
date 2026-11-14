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
55. `090_facolub_product_catalog_foundation.sql` (normalized range, SKU, and legacy-safe catalog links)
56. `091_facolub_product_catalog_seed.sql` (idempotent official 41-SKU catalog seed with conflict checks)
57. `092_facolub_product_stock_link.sql` (finished-product stock references; no quantities or movements)
58. `093_facolub_product_catalog_verification.sql` (read-only exact mapping, uniqueness, linkage, and balance audit)
59. `094_stock_packaging_seal_rules.sql` (range/product-aware carton and seal configuration; zero opening stock)
60. `095_auto_receipt_companion_rules.sql` (atomic Empty Bottle 25L to Seal 25L receipt companion)
61. `096_recipe_rule_updates.sql` (prospective versioned recipe packaging updates and missing-mapping audit)
62. `097_invoice_ttc_foundation.sql` (explicit HT/TVA/TTC snapshot fields and nullable default tax configuration)
63. `098_invoice_ttc_functions.sql` (database-authoritative invoice totals and Admin tax-rate configuration)
64. `099_demo_cleanup_verification.sql` (safe demo deactivation plus catalog, packaging, receiving, and TTC audit)
65. `100_invoice_tva_20.sql` (confirmed 20% default TVA; recalculates drafts and preserves issued invoices)
66. `101_invoice_tva_recalculation_fix.sql` (calculates draft TVA with the new 20% rate and repairs zero-tax drafts)
67. `110_customer_master_upgrade.sql` (additive authoritative CRM fields, safe customer codes, notes, and HT custom-price foundation)
68. `111_customer_functions.sql` (validated customer CRUD, duplicate detection, search, snapshot helper, and derived history)
69. `112_customer_rls.sql` (Admin/Management CRM visibility, RPC-only writes, and Factory denial)
70. `113_customer_document_integration.sql` (legal snapshots and customer delivery defaults for orders/documents)
71. `114_customer_verification.sql` (rollback-only CRM, duplicate, search, deactivation, reference, and role tests)
72. `115_stock_catalog_completion_foundation.sql` (tonne unit and product/format-safe stock mapping foundation)
73. `116_stock_catalog_completion_seed.sql` (labels, prepared bottles, shared empty bottles, and exact 19-oil bulk master)
74. `117_stock_catalog_completion_verification.sql` (read-only acceptance tests, ambiguity report, and liter/tonne audit)

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

Files 090-092 are the official FACOLUB 2026 catalog installation and must be run in order after
the existing planning catalog and stock engine. They reuse compatible product/format/stock rows,
stop on identity conflicts, preserve document snapshots and all ledger history, and never create
opening balances or stock movements. File 093 is read-only and expects exactly 41 official SKUs,
9 ranges, 41 finished-product stock links, and no duplicate SKU.

Files 094-099 are the additive post-catalog business-rule patch. File 094 adds configurable
carton/seal resolution without stock quantities. File 095 keeps 25L bottle/seal receipt movements
in one idempotent confirmation transaction. File 096 versions only recipes whose bulk and prepared
bottle mappings already exist, and reports missing mappings instead of guessing. Files 097-098
introduce explicit authoritative HT/TVA/TTC semantics; the default TVA rate is deliberately null
until confirmed and configured by an Admin. File 099 deactivates only explicit DEMO/TEST fixtures,
preserves confirmed history, and audits the installed rules and official 41-SKU catalog.
File 100 records the subsequently confirmed SOMA TVA rate of 20%. It applies the rate to new
invoices and existing drafts only; issued/cancelled invoice snapshots remain unchanged.
File 101 fixes recalculation when a draft moves from a null or previous rate to 20%. It recalculates
all drafts as `TVA = round(TOTAL HT * 20 / 100, 2)` and audits final invoices without rewriting them.

Files 110-113 are the additive Customer CRM module and must be run in order after the invoice TVA
patches and official product catalog. They extend the existing `customers` table, preserve all
foreign keys and issued snapshots, generate concurrency-safe `CLI-000001` codes with a sequence,
and keep Factory users out of legal/commercial CRM data. Customer-specific prices are HT only and
do not implement pricing formulas. File 114 is rollback-only, requires active FACOLUB users for
all three roles, and leaves no test customers, notes, prices, documents, or numbering increments.

Files 115-116 complete the official stock master without creating physical quantities. File 115
adds the canonical tonne unit and mapping tables. File 116 creates or reuses product/format label
and prepared-bottle references, maps all 41 SKUs to four shared physical empty bottles, installs
exactly the supplied 19-oil FACOLUB bulk master in tonnes, and maps every official finished SKU.
Label quantities are copied only from an existing active prepared-bottle recipe; unknown counts
remain null for explicit confirmation. Tonne/liter conversion is also null by design and must be
configured per lubricant. File 117 is read-only and reports both unresolved label quantities and
active liter-based production recipes; it creates no test rows or stock movements.

Files 118-121 implement S8 physical loading/dispatch and must be run in order after File 117.
They add partial order fulfillment, private photo evidence, vehicle traceability, atomic and
idempotent finished-product stock OUT, and one BL/BT pair per confirmed dispatch while preserving
historical documents. Invoice quantity semantics remain order-based. File 122 is read-only.

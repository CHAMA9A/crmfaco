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

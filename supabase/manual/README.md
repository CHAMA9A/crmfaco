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

Files 001-004 and 006 contain production schema/security only. Test data is never mixed into them.

Files 010-014 are the production order-bundle migration and must be run in order, one at a time.
File 015 is a rollback-only verification suite; it requires active FACOLUB users for all three
roles and at least one active customer, and commits no test rows or numbering increments.

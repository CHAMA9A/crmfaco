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

Files 001-004 and 006 contain production schema/security only. Test data is never mixed into them.

# FACOLUB Stock S1 architecture

## Authoritative quantity model

- **Physical** is the signed sum of immutable `stock_movements`: `in` adds and `out` subtracts.
- **Reserved** is the sum of `stock_reservations.quantity` where status is `active`.
- **Available** is always calculated as `physical - reserved` by `stock_balances` or `get_stock_balance`.
- No stock quantity is stored on `stock_items`, and available stock is never independently editable.

## Units and catalog relationship

S1 stores canonical physical quantities in `piece`, `liter`, or `kilogram`. Empty bottles, labels,
seals, cartons, prepared bottles, and finished products are counted as pieces. Bulk lubricant can be
stored in liters or kilograms according to the item's configured canonical unit. S1 performs no
carton-to-piece or mass-to-volume conversion.

The inspected schema has no authoritative product/format catalog. `stock_items.product_format_id`
therefore remains a nullable, intentionally unbound UUID. A future catalog migration can add the
foreign key after existing values have been validated; S1 does not duplicate speculative products.

## Mutation and concurrency rules

Application users cannot insert, update, or delete stock ledger rows directly. Trusted functions
validate the authenticated active FACOLUB member and their role before writing. Confirmed movements
have an additional database trigger that rejects every UPDATE and DELETE; an error is represented by
an opposite `correction` movement linked through `corrected_movement_id`.

All movement and reservation mutations take the same PostgreSQL transaction-level advisory lock for
the `(stock_item_id, location_id)` pair before reading the balance. This serializes simultaneous OUT
movements and reservations. The second transaction reads the balance after the first commits, so two
requests cannot both spend the same available quantity.

Normal OUT movements fail if they would make physical stock negative. Only Admin can explicitly
allow a negative result during a linked correction or an `adjustment_out` reconciliation. This is an
S1 assumption that SOMA must confirm before later operational workflows are enabled.

## Role boundary

- **Factory:** safe quantity and movement-history reads; no stock mutations or threshold changes.
- **Management:** safe reads plus trusted movement and reservation RPCs.
- **Admin:** Management capabilities plus item configuration and linked corrections.

The stock model contains no purchase price, cost, margin, or other financial field.

## Future module calls

- **S2 Receiving:** after a physical receipt is confirmed, call `record_stock_movement` with
  `movement_type = receipt` and `direction = in`.
- **S3 Prepared Bottles:** atomically call the movement engine for material OUT entries and prepared
  bottle IN entries when the real preparation event is confirmed.
- **S4 Planning:** read `stock_balances`; planning itself creates no physical movement.
- **S5 Reservations:** call `create_stock_reservation`, `release_stock_reservation`, and
  `consume_stock_reservation`. Reservation consumption alone does not change physical stock.
- **S6 Production:** atomically record confirmed consumption OUT and output IN movements. S1 does not
  define BOMs or recipes.
- **S7 Inventory / Corrections:** use the `stock_adjustments` approval foundation and post an
  `adjustment_in` or `adjustment_out`; use `record_stock_correction` for input errors.
- **S8 Dispatch:** actual confirmed loading—not an Order, BL, or BT—will consume/release its
  reservation and record a `dispatch` OUT movement in one future transaction.

No S2-S8 workflow is connected in S1.

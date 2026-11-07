import { describe, expect, test } from "bun:test";
import { PDFDocument } from "pdf-lib";

import { createInvoicePdfBlob, invoicePdfFilename, invoicePdfTotalRows } from "./pdf";
import type { InvoiceDocument } from "./types";

const testInvoice: InvoiceDocument = {
  id: "42e8c3ae-a10d-472a-994b-166b18b75e26",
  order_id: null,
  invoice_number: "FAC-2026-000001",
  invoice_date: "2026-09-23",
  purchase_order: "TEST-INVOICE-VALIDATION-2026-09-23",
  customer_name_snapshot: "[TEST] SOMA INVOICE VALIDATION",
  customer_city_snapshot: "CASABLANCA",
  customer_address_snapshot: "TEST ADDRESS - NOT A REAL CUSTOMER",
  customer_ice_snapshot: "TEST-ICE-NOT-FISCAL",
  status: "issued",
  currency: "MAD",
  subtotal_ht: "10500.00",
  tax_rate: "20.0000",
  tax_total: "2100.00",
  total_ttc: "12600.00",
  authoritative_total: "12600.00",
  prices_confirmed_at: null,
  items: [
    {
      id: "1",
      order_item_id: null,
      description: "[TEST] SOMA 10W40 - VALIDATION LINE",
      quantity: "10",
      unit_price: "650.00",
      line_total: "6500.00",
      position: 1,
    },
    {
      id: "2",
      order_item_id: null,
      description: "[TEST] SOMA 20W50 - VALIDATION LINE",
      quantity: "5",
      unit_price: "800.00",
      line_total: "4000.00",
      position: 2,
    },
  ],
};

describe("invoice PDF", () => {
  test("uses the official invoice number as the filename", () => {
    expect(invoicePdfFilename(testInvoice)).toBe("FAC-2026-000001.pdf");
  });

  test("renders database-authoritative HT, TVA and TTC values", () => {
    expect(invoicePdfTotalRows(testInvoice)).toEqual([
      ["TOTAL HT", "10 500,00 MAD"],
      ["TVA 20 %", "2 100,00 MAD"],
      ["TOTAL TTC", "12 600,00 MAD"],
    ]);
  });

  test("does not invent TVA semantics for a preserved legacy invoice", () => {
    expect(invoicePdfTotalRows({ ...testInvoice, tax_rate: null })).toEqual([
      ["TOTAL HISTORIQUE", "12 600,00 MAD"],
    ]);
  });

  test("generates a valid one-page A4 PDF", async () => {
    const blob = await createInvoicePdfBlob(testInvoice);
    const bytes = await blob.arrayBuffer();
    const document = await PDFDocument.load(bytes);
    const [page] = document.getPages();

    expect(blob.type).toBe("application/pdf");
    expect(document.getPageCount()).toBe(1);
    expect(page?.getWidth()).toBeCloseTo(595.28, 1);
    expect(page?.getHeight()).toBeCloseTo(841.89, 1);
  });

  test("paginates long invoices", async () => {
    const longInvoice: InvoiceDocument = {
      ...testInvoice,
      items: Array.from({ length: 45 }, (_, index) => ({
        ...testInvoice.items[0]!,
        id: String(index),
        position: index + 1,
      })),
    };
    const document = await PDFDocument.load(
      await (await createInvoicePdfBlob(longInvoice)).arrayBuffer(),
    );
    expect(document.getPageCount()).toBeGreaterThan(1);
  });

  test("adapts to long customer information and long references", async () => {
    const adaptiveInvoice: InvoiceDocument = {
      ...testInvoice,
      customer_name_snapshot:
        "[TEST] CLIENT INDUSTRIEL AVEC UNE RAISON SOCIALE EXCEPTIONNELLEMENT LONGUE POUR VALIDATION",
      purchase_order:
        "PO-2026-VALIDATION-REFERENCE-TRES-LONGUE-AVEC-DES-INFORMATIONS-COMPLEMENTAIRES",
      customer_address_snapshot:
        "ZONE INDUSTRIELLE DE TEST, BATIMENT 27, ETAGE 4, BUREAU 418, CASABLANCA - ADRESSE VOLONTAIREMENT LONGUE POUR VERIFIER LE RETOUR A LA LIGNE ET LA HAUTEUR ADAPTATIVE",
      items: Array.from({ length: 14 }, (_, index) => ({
        ...testInvoice.items[index % testInvoice.items.length]!,
        id: String(index),
        description: `${testInvoice.items[index % testInvoice.items.length]!.description} - DESCRIPTION COMPLEMENTAIRE POUR VERIFIER LA HAUTEUR DYNAMIQUE DE LA LIGNE PRODUIT`,
        position: index + 1,
      })),
    };

    const document = await PDFDocument.load(
      await (await createInvoicePdfBlob(adaptiveInvoice)).arrayBuffer(),
    );
    expect(document.getPageCount()).toBeGreaterThan(1);
    document.getPages().forEach((page) => {
      expect(page.getWidth()).toBeCloseTo(595.28, 1);
      expect(page.getHeight()).toBeCloseTo(841.89, 1);
    });
  });
});

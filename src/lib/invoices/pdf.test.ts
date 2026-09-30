import { describe, expect, test } from "bun:test";
import { PDFDocument } from "pdf-lib";

import { createInvoicePdfBlob, invoicePdfFilename } from "./pdf";
import type { InvoiceDocument } from "./types";

const testInvoice: InvoiceDocument = {
  id: "42e8c3ae-a10d-472a-994b-166b18b75e26",
  invoice_number: "FAC-2026-000001",
  invoice_date: "2026-09-23",
  purchase_order: "TEST-INVOICE-VALIDATION-2026-09-23",
  customer_name_snapshot: "[TEST] SOMA INVOICE VALIDATION",
  customer_city_snapshot: "CASABLANCA",
  customer_address_snapshot: "TEST ADDRESS - NOT A REAL CUSTOMER",
  customer_ice_snapshot: "TEST-ICE-NOT-FISCAL",
  status: "issued",
  currency: "MAD",
  authoritative_total: "10500.00",
  items: [
    {
      id: "1",
      description: "[TEST] SOMA 10W40 - VALIDATION LINE",
      quantity: "10",
      unit_price: "650.00",
      line_total: "6500.00",
      position: 1,
    },
    {
      id: "2",
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

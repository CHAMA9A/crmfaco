import { describe, expect, test } from "bun:test";
import { PDFDocument } from "pdf-lib";
import { createDeliveryNotePdfBlob, createTransportNotePdfBlob, documentFilename } from "./pdf";
import type { DeliveryNoteDocument, OrderLine, TransportNoteDocument } from "./types";

const items: OrderLine[] = Array.from({ length: 42 }, (_, index) => ({
  id: String(index + 1),
  description: `PRODUIT SOMA ${index + 1} - DESCRIPTION LONGUE POUR VERIFIER LES RETOURS A LA LIGNE`,
  quantity: String(index + 1),
  position: index + 1,
}));
const delivery: DeliveryNoteDocument = {
  id: "11111111-1111-4111-8111-111111111111",
  order_id: "22222222-2222-4222-8222-222222222222",
  delivery_note_number: "BL-250926-01",
  delivery_date: "2026-09-25",
  prepared_for: "Rachid Nhari",
  object: "acheminement de marchandises",
  handover_date: "2026-09-25",
  transport_reception_name: "Rachid Nhari",
  status: "issued",
  order_number: "CMD-250926-01",
  items,
};
const transport: TransportNoteDocument = {
  id: "33333333-3333-4333-8333-333333333333",
  order_id: delivery.order_id,
  transport_note_number: "BT-250926-01",
  transport_date: "2026-09-25",
  transport_person: "Rachid Nhari",
  sender: "SOMA LUBRIFIANTS",
  pickup_date: "2026-09-25",
  loading_location: "CASABLANCA",
  destination: "RABAT",
  vehicle_registration: "12345-A-1",
  status: "issued",
  order_number: delivery.order_number,
  items,
};

describe("order shipping PDFs", () => {
  test("uses official document filenames", () => {
    expect(documentFilename(delivery, "delivery")).toBe("BL-250926-01.pdf");
    expect(documentFilename(transport, "transport")).toBe("BT-250926-01.pdf");
  });
  test("BL and BT paginate long product lists without oversized pages", async () => {
    for (const blob of [
      await createDeliveryNotePdfBlob(delivery),
      await createTransportNotePdfBlob(transport),
    ]) {
      const pdf = await PDFDocument.load(await blob.arrayBuffer());
      expect(pdf.getPageCount()).toBeGreaterThan(1);
      for (const page of pdf.getPages()) {
        expect(page.getWidth()).toBeCloseTo(595.28, 1);
        expect(page.getHeight()).toBeCloseTo(841.89, 1);
      }
    }
  });
});

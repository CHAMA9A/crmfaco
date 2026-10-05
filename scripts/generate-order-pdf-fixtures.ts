import { mkdir } from "node:fs/promises";
import { createDeliveryNotePdfBlob, createTransportNotePdfBlob } from "../src/lib/orders/pdf";
import type {
  DeliveryNoteDocument,
  OrderLine,
  TransportNoteDocument,
} from "../src/lib/orders/types";

const nativeFetch = globalThis.fetch;
globalThis.fetch = ((input: string | URL | Request, init?: RequestInit) => {
  if (String(input) === "/soma-invoice-logo.png") {
    return Promise.resolve(new Response(Bun.file("public/soma-invoice-logo.png"), { status: 200 }));
  }
  return nativeFetch(input, init);
}) as typeof fetch;

const referenceItems = [
  ["FACOLUB SAE 50 5L", "148"],
  ["FACOLUB SAE 50 2L", "222"],
  ["FACOLUB SAE 50 1L", "888"],
  ["FACOLUB 20W50 5L", "76"],
  ["FACOLUB 20W50 2L", "222"],
  ["FACOLUB 20W50 1L", "888"],
  ["FACOLUB 4T 20W50 1L", "336"],
  ["FACOLUB 4T 15W50 1L", "216"],
  ["FACOLUB 4T 10W40 1L", "276"],
  ["FACOLUB SAE 140 5L", "44"],
  ["FACOLUB SAE 140 2L", "90"],
  ["FACOLUB SAE 140 1L", "444"],
  ["FACOLUB SAE 90 5L", "44"],
  ["FACOLUB SAE 90 2L", "90"],
  ["FACOLUB SAE 90 1L", "444"],
  ["FACOLUB 2T 5L", "88"],
  ["FACOLUB 2T 2L", "222"],
  ["FACOLUB 2T 1L", "888"],
  ["FACOLUB 2T 25L", "30"],
  ["FACOLUB 68 5L", "76"],
  ["FACOLUB 68 25L", "200"],
  ["FACOLUB ATF 1L", "444"],
  ["FACOLUB 10W40 5L", "60"],
  ["FACOLUB 10W40 1L", "216"],
  ["FACOLUB 15W40 5L", "120"],
  ["FACOLUB 15W40 1L", "216"],
] as const;

const items: OrderLine[] = referenceItems.map(([description, quantity], index) => ({
  id: crypto.randomUUID(),
  description,
  quantity,
  position: index + 1,
}));
const base = {
  order_id: crypto.randomUUID(),
  order_number: "CMD-250926-01",
  items,
  status: "issued" as const,
};
const delivery: DeliveryNoteDocument = {
  ...base,
  id: crypto.randomUUID(),
  delivery_note_number: "BL-250926-01",
  delivery_date: "2026-09-25",
  prepared_for: "Rachid Nhari",
  object: "acheminement de marchandises",
  handover_date: "2026-09-25",
  transport_reception_name: "Rachid Nhari",
};
const transport: TransportNoteDocument = {
  ...base,
  id: crypto.randomUUID(),
  transport_note_number: "BT-250926-01",
  transport_date: "2026-09-25",
  transport_person: "Rachid Nhari",
  sender: "SOMA LUBRIFIANTS",
  pickup_date: "2026-09-25",
  loading_location: "CASABLANCA",
  destination: null,
  vehicle_registration: null,
};

await mkdir("output/pdf", { recursive: true });
await Bun.write(
  "output/pdf/BL-250926-01-validation.pdf",
  await createDeliveryNotePdfBlob(delivery),
);
await Bun.write(
  "output/pdf/BT-250926-01-validation.pdf",
  await createTransportNotePdfBlob(transport),
);
console.log("Generated BL and BT validation PDFs");

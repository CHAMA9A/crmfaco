import type { DocumentStatus, InvoiceStatus, OrderStatus } from "@/types/database";

export type OrderLine = {
  id: string;
  description: string;
  quantity: string;
  position: number;
};

export type OrderDocumentSummary = {
  id: string;
  number: string | null;
  status: DocumentStatus | InvoiceStatus;
};

export type OrderListRow = {
  id: string;
  order_number: string | null;
  order_date: string;
  purchase_order: string | null;
  customer_name: string;
  status: OrderStatus;
  invoice: OrderDocumentSummary | null;
  delivery_note: OrderDocumentSummary | null;
  transport_note: OrderDocumentSummary | null;
};

export type OrderWorkspaceData = {
  orders: OrderListRow[];
};

export type OrderEditorData = {
  today: string;
  customers: Array<{
    id: string;
    company_name: string;
    city: string | null;
    address: string | null;
    purchase_order_default: string | null;
  }>;
};

export type DraftOrderEditorData = OrderEditorData & {
  order: {
    id: string;
    customer_id: string;
    order_date: string;
    purchase_order: string | null;
    destination_city: string | null;
    destination_address: string | null;
  };
  items: OrderLine[];
};

export type OrderDetailData = {
  order: {
    id: string;
    order_number: string | null;
    order_reference: string | null;
    order_date: string;
    purchase_order: string | null;
    destination_city: string | null;
    destination_address: string | null;
    customer_name: string;
    status: OrderStatus;
  };
  items: OrderLine[];
  invoice: (OrderDocumentSummary & { prices_confirmed_at: string | null }) | null;
  delivery_note: OrderDocumentSummary | null;
  transport_note: OrderDocumentSummary | null;
};

export type DeliveryNoteDocument = {
  id: string;
  order_id: string;
  delivery_note_number: string | null;
  delivery_date: string | null;
  prepared_for: string | null;
  object: string;
  handover_date: string | null;
  transport_reception_name: string | null;
  status: DocumentStatus;
  order_number: string;
  items: OrderLine[];
};

export type TransportNoteDocument = {
  id: string;
  order_id: string;
  transport_note_number: string | null;
  transport_date: string | null;
  transport_person: string | null;
  sender: string;
  pickup_date: string | null;
  loading_location: string;
  destination: string | null;
  vehicle_registration: string | null;
  status: DocumentStatus;
  order_number: string;
  items: OrderLine[];
};

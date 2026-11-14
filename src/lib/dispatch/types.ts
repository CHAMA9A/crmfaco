export type DispatchStatus = "draft" | "confirmed" | "cancelled";
export type DispatchAttachmentCategory = "goods" | "vehicle" | "registration" | "other";

export type DispatchMission = {
  order_id: string;
  order_number: string;
  order_date: string;
  destination_name: string;
  destination_city: string | null;
  remaining_total: number;
  remaining_lines: number;
  draft_dispatch_id: string | null;
};

export type DispatchRemainingLine = {
  order_item_id: string;
  product_format_id: string;
  sku: string;
  description: string;
  ordered: number;
  dispatched: number;
  remaining: number;
};

export type DispatchHeader = {
  id: string;
  dispatch_number: string | null;
  order_id: string | null;
  customer_id: string | null;
  location_id: string;
  dispatch_date: string;
  destination_type: "customer" | "internal";
  destination_name: string;
  delivery_address_snapshot: string | null;
  delivery_city_snapshot: string | null;
  delivery_contact_snapshot: string | null;
  status: DispatchStatus;
  vehicle_description: string | null;
  vehicle_registration: string | null;
  driver_name: string | null;
  driver_phone: string | null;
  transport_company: string | null;
  notes: string | null;
  confirmed_at: string | null;
  confirmed_by: string | null;
  created_by: string;
  created_at: string;
  updated_at: string;
};

export type DispatchItem = {
  id: string;
  dispatch_id: string;
  order_item_id: string | null;
  product_format_id: string;
  stock_item_id: string;
  sku_snapshot: string;
  description_snapshot: string;
  ordered_quantity_snapshot: number | null;
  quantity_loaded: number;
  created_at: string;
};

export type DispatchAttachment = {
  id: string;
  dispatch_id: string;
  category: DispatchAttachmentCategory;
  storage_path: string;
  file_name: string | null;
  mime_type: string;
  file_size: number;
  uploaded_by: string;
  uploaded_at: string;
  signed_url?: string | null;
};

export type DispatchDetail = {
  dispatch: DispatchHeader;
  items: DispatchItem[];
  attachments: DispatchAttachment[];
  movements: Array<{ id: string; quantity: number; created_at: string }>;
  remaining: DispatchRemainingLine[];
};

export type DispatchHistoryRow = Pick<
  DispatchHeader,
  | "id"
  | "dispatch_number"
  | "dispatch_date"
  | "order_id"
  | "destination_name"
  | "vehicle_registration"
  | "confirmed_at"
  | "created_by"
  | "status"
> & { total_loaded: number; employee_name: string };

export function validateLoadedQuantity(value: unknown, remaining: number) {
  const parsed = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) return "Loaded quantity must be greater than zero.";
  if (parsed > remaining) return "Loaded quantity cannot exceed the remaining order quantity.";
  return null;
}

export function fulfillmentState(lines: Array<{ ordered: number; dispatched: number }>) {
  if (!lines.length || lines.every((line) => line.dispatched === 0)) return "not_dispatched";
  if (lines.every((line) => line.dispatched >= line.ordered)) return "fully_dispatched";
  return "partially_dispatched";
}

export function sanitizeDispatchFileName(fileName: string) {
  return (
    fileName
      .normalize("NFKD")
      .replace(/[\u0300-\u036f]/g, "")
      .replace(/[^a-zA-Z0-9._-]+/g, "-")
      .replace(/-+/g, "-")
      .replace(/^[.-]+|[.-]+$/g, "")
      .slice(0, 120) || "dispatch-photo.jpg"
  );
}

export function buildDispatchStoragePath(dispatchId: string, fileName: string) {
  return `${dispatchId}/${crypto.randomUUID()}-${sanitizeDispatchFileName(fileName)}`;
}

import type {
  Receipt,
  ReceiptAttachment,
  ReceiptListRow,
  ReceiptStatus,
  StockItem,
  StockLocation,
  StockUnit,
  Supplier,
} from "@/types/database";

export const receiptStatuses = ["draft", "confirmed", "cancelled"] as const;

export const receiptStatusLabels: Record<ReceiptStatus, string> = {
  draft: "Draft",
  confirmed: "Confirmed",
  cancelled: "Cancelled",
};

export type ReceivingStockItem = StockItem & {
  location_id: string;
  physical_quantity: number;
  reserved_quantity: number;
  available_quantity: number;
};

export type ReceiptDetailItem = {
  id: string;
  stock_item_id: string;
  stock_item_name: string;
  category: StockItem["category"];
  quantity: number;
  unit: StockUnit;
  position: number;
};

export type ReceiptDetailAttachment = ReceiptAttachment & { signed_url: string | null };

export type ReceiptDetailMovement = {
  id: string;
  stock_item_id: string;
  quantity: number;
  direction: "in" | "out";
  created_by: string;
  created_at: string;
  receipt_item_id: string | null;
};

export type ReceiptDetail = {
  receipt: Receipt;
  location_name: string;
  created_by_name: string;
  confirmed_by_name: string | null;
  items: ReceiptDetailItem[];
  attachments: ReceiptDetailAttachment[];
  movements: ReceiptDetailMovement[];
};

export type ReceivingHomeData = {
  rows: ReceiptListRow[];
};

export type ReceivingHistoryData = {
  rows: ReceiptListRow[];
  suppliers: Supplier[];
  stockItems: Pick<StockItem, "id" | "name">[];
  users: { id: string; display_name: string }[];
};

export type SupplierAdminData = { suppliers: Supplier[] };

export type ReceiptEditorData = {
  today: string;
  receipt: ReceiptDetail | null;
  stockItems: ReceivingStockItem[];
  locations: StockLocation[];
  suppliers: Supplier[];
};

export type ReceiptConfirmationBalance = {
  receipt_item_id: string;
  stock_item_id: string;
  quantity_received: number;
  unit: StockUnit;
  movement_id: string;
  physical_before: number;
  reserved_before: number;
  physical_after: number;
  reserved_after: number;
  available_after: number;
  current_physical: number;
  current_reserved: number;
  current_available: number;
};

export type ReceiptConfirmation = {
  receipt_id: string;
  receipt_number: string;
  status: "confirmed";
  confirmed_at: string;
  balances: ReceiptConfirmationBalance[];
};

export type ReceiptDraftLine = {
  key: string;
  id: string | null;
  stockItemId: string;
  quantity: string;
};

export type LocalReceiptDraft = {
  receiptId: string | null;
  receiptDate: string;
  locationId: string;
  supplierId: string;
  supplierName: string;
  reference: string;
  comment: string;
  lines: ReceiptDraftLine[];
};

export const receivingDraftStorageKey = "facolub-receiving-draft:v1";
export const receiptPhotoMaxBytes = 8 * 1024 * 1024;
export const receiptPhotoCompressThresholdBytes = 1_500_000;
export const receiptPhotoMaxDimension = 2_000;
export const supportedReceiptPhotoTypes = [
  "image/jpeg",
  "image/png",
  "image/webp",
  "image/heic",
  "image/heif",
] as const;

export function validateReceiptLines(lines: readonly ReceiptDraftLine[]) {
  if (lines.length === 0) return "At least one item is required.";
  const selected = new Set<string>();
  for (const line of lines) {
    if (!line.stockItemId) return "Select an item for every line.";
    const quantity = Number(line.quantity);
    if (!Number.isFinite(quantity) || quantity <= 0) {
      return "Every quantity must be greater than zero.";
    }
    if (selected.has(line.stockItemId)) return "Each item can appear only once.";
    selected.add(line.stockItemId);
  }
  return null;
}

export function sanitizeReceiptFileName(fileName: string) {
  const safe = fileName
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-zA-Z0-9._-]+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^[.-]+|[.-]+$/g, "")
    .slice(0, 120);
  return safe || "receipt-photo.jpg";
}

export function validateReceiptPhoto(file: Pick<File, "type" | "size">) {
  if (
    !supportedReceiptPhotoTypes.includes(file.type as (typeof supportedReceiptPhotoTypes)[number])
  ) {
    return "Only JPEG, PNG, WebP, HEIC, or HEIF images are accepted.";
  }
  if (file.size <= 0) return "The selected photo is empty.";
  if (file.size > receiptPhotoMaxBytes) return "Each photo must be 8 MiB or smaller.";
  return null;
}

export function buildReceiptStoragePath(receiptId: string, fileName: string, token: string) {
  return `${receiptId}/${token}-${sanitizeReceiptFileName(fileName)}`;
}

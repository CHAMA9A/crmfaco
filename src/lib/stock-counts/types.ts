import type {
  StockAdjustment,
  StockAdjustmentStatus,
  StockAdjustmentType,
  StockCount,
  StockCountAttachment,
  StockCountItem,
  StockCountStatus,
  StockItem,
  StockItemCategory,
  StockLocation,
  StockMovement,
  StockUnit,
} from "@/types/database";

export const stockCountStatuses = [
  "draft",
  "submitted",
  "approved",
  "rejected",
  "cancelled",
] as const;
export const stockAdjustmentStatuses = [
  "draft",
  "pending",
  "approved",
  "rejected",
  "posted",
] as const;
export const stockAdjustmentTypes = [
  "count_difference",
  "loss",
  "damage",
  "correction",
  "other",
] as const;

export const stockCountStatusLabels: Record<StockCountStatus, string> = {
  draft: "Draft",
  submitted: "Pending Approval",
  approved: "Approved",
  rejected: "Rejected",
  cancelled: "Cancelled",
};

export const stockAdjustmentStatusLabels: Record<StockAdjustmentStatus, string> = {
  draft: "Draft",
  pending: "Pending Approval",
  approved: "Approved",
  rejected: "Rejected",
  posted: "Posted",
};

export const stockAdjustmentTypeLabels: Record<StockAdjustmentType, string> = {
  count_difference: "Count difference",
  loss: "Loss",
  damage: "Damage",
  correction: "Correction",
  other: "Other adjustment",
};

export type StockCountListRow = {
  id: string;
  count_number: string | null;
  count_date: string;
  location_id: string;
  location_name: string;
  status: StockCountStatus;
  created_by: string;
  created_by_name: string;
  approved_by_name: string | null;
  item_count: number;
  difference_count: number;
  net_difference: number;
  created_at: string;
};

export type StockAdjustmentListRow = {
  id: string;
  stock_item_id: string;
  stock_item_name: string;
  location_name: string;
  adjustment_type: StockAdjustmentType;
  difference_quantity: number;
  reason: string;
  status: StockAdjustmentStatus;
  requested_by: string;
  requested_by_name: string;
  approved_by_name: string | null;
  stock_count_id: string | null;
  stock_movement_id: string | null;
  original_movement_id: string | null;
  created_at: string;
};

export type CountBalance = {
  physical_quantity: number;
  reserved_quantity: number;
  available_quantity: number;
  reservation_shortage: boolean;
};

export type StockCountDetailItem = {
  item: StockCountItem;
  stock_item_name: string;
  unit: StockUnit;
  adjustment: StockAdjustment | null;
  movement: StockMovement | null;
  current_balance: CountBalance;
};

export type StockCountDetail = {
  count: StockCount;
  location_name: string;
  created_by_name: string;
  submitted_by_name: string | null;
  approved_by_name: string | null;
  rejected_by_name: string | null;
  items: StockCountDetailItem[];
  attachments: Array<StockCountAttachment & { signed_url?: string | null }>;
};

export type StockCountWorkspaceData = {
  counts: StockCountListRow[];
  adjustments: StockAdjustmentListRow[];
  locations: StockLocation[];
  items: Array<StockItem & { location_id: string; physical_quantity: number }>;
};

export type NewStockCountData = Pick<StockCountWorkspaceData, "locations" | "items"> & {
  today: string;
};

export type StockCountScope = "all" | "category" | "items";

export function signedDifference(value: number) {
  return value > 0 ? `+${value}` : String(value);
}

export function buildStockEvidencePath(
  userId: string,
  kind: "counts" | "adjustments",
  recordId: string,
  fileName: string,
  token: string,
) {
  const safeName = fileName.replace(/[^a-zA-Z0-9._-]/g, "-").slice(-120);
  return `${userId}/${kind}/${recordId}/${token}-${safeName}`;
}

export function validateStockEvidence(file: File) {
  const allowed = ["image/jpeg", "image/png", "image/webp", "application/pdf"];
  if (!allowed.includes(file.type)) return "Use a JPG, PNG, WebP or PDF file.";
  if (file.size <= 0 || file.size > 10 * 1024 * 1024) return "Evidence must be 10 MB or smaller.";
  return null;
}

export type CountScopeInput = {
  scope: StockCountScope;
  category: StockItemCategory | null;
  stockItemIds: string[];
};

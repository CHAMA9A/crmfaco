import type {
  AppRole,
  StockDirection,
  StockItem,
  StockItemCategory,
  StockLocation,
  StockMovementHistoryRow,
  StockMovementType,
  StockUnit,
} from "@/types/database";

export const stockCategories = [
  "empty_bottle",
  "label",
  "prepared_bottle",
  "seal",
  "carton",
  "bulk_lubricant",
  "finished_product",
  "other",
] as const satisfies readonly StockItemCategory[];

export const stockUnits = ["piece", "liter", "kilogram"] as const satisfies readonly StockUnit[];

export const stockMovementTypes = [
  "opening_balance",
  "receipt",
  "preparation_consumption",
  "preparation_output",
  "production_consumption",
  "production_output",
  "dispatch",
  "adjustment_in",
  "adjustment_out",
  "loss",
  "damage",
  "correction",
  "reservation_release_related",
  "other",
] as const satisfies readonly StockMovementType[];

export const stockCategoryLabels: Record<StockItemCategory, string> = {
  empty_bottle: "Empty Bottles",
  label: "Labels",
  prepared_bottle: "Prepared Bottles",
  seal: "Seals",
  carton: "Cartons",
  bulk_lubricant: "Bulk Lubricant",
  finished_product: "Finished Products",
  other: "Other",
};

export const stockUnitLabels: Record<StockUnit, string> = {
  piece: "pieces",
  liter: "liters",
  kilogram: "kilograms",
};

export const stockMovementLabels: Record<StockMovementType, string> = {
  opening_balance: "Opening balance",
  receipt: "Receipt",
  preparation_consumption: "Preparation consumption",
  preparation_output: "Preparation output",
  production_consumption: "Production consumption",
  production_output: "Production output",
  dispatch: "Dispatch",
  adjustment_in: "Adjustment in",
  adjustment_out: "Adjustment out",
  loss: "Loss",
  damage: "Damage",
  correction: "Correction",
  reservation_release_related: "Reservation release",
  other: "Other",
};

export type StockStatus = "available" | "reserved" | "unavailable";

export type StockOverviewRow = StockItem & {
  location_id: string;
  location_name: string;
  physical_quantity: number;
  reserved_quantity: number;
  available_quantity: number;
};

export type StockOverviewData = {
  rows: StockOverviewRow[];
  locations: StockLocation[];
};

export type StockHistoryData = {
  rows: StockMovementHistoryRow[];
};

export type StockItemAdminData = {
  items: StockItem[];
};

export type LedgerEntry = { direction: StockDirection; quantity: number };
export type ReservationEntry = { status: string; quantity: number };

export type StockCapabilities = {
  read: boolean;
  recordMovement: boolean;
  manageReservations: boolean;
  correctMovement: boolean;
  configureItems: boolean;
};

export function stockCapabilities(role: AppRole): StockCapabilities {
  return {
    read: true,
    recordMovement: role === "admin" || role === "management",
    manageReservations: role === "admin" || role === "management",
    correctMovement: role === "admin",
    configureItems: role === "admin",
  };
}

export function calculatePhysicalStock(entries: readonly LedgerEntry[]) {
  return entries.reduce(
    (total, entry) => total + (entry.direction === "in" ? entry.quantity : -entry.quantity),
    0,
  );
}

export function calculateReservedStock(entries: readonly ReservationEntry[]) {
  return entries.reduce(
    (total, entry) => total + (entry.status === "active" ? entry.quantity : 0),
    0,
  );
}

export function calculateAvailableStock(physical: number, reserved: number) {
  return physical - reserved;
}

export function canRecordNormalOut(physical: number, quantity: number) {
  return quantity > 0 && physical - quantity >= 0;
}

export function canCreateReservation(physical: number, reserved: number, quantity: number) {
  return quantity > 0 && calculateAvailableStock(physical, reserved) >= quantity;
}

export function getStockStatus(available: number, reserved: number): StockStatus {
  if (available <= 0) return "unavailable";
  if (reserved > 0) return "reserved";
  return "available";
}

export function isLowStock(available: number, minimumStock: number | null) {
  return minimumStock !== null && available < minimumStock;
}

export function formatStockQuantity(value: number, locale = "en-US") {
  return new Intl.NumberFormat(locale, { maximumFractionDigits: 3 }).format(value);
}

import type {
  PlanningQuantityMode,
  ProductionExecution,
  ProductionExecutionItem,
  ProductionExecutionStatus,
  ProductionIssue,
  ProductionPlan,
  ProductionPlanItem,
  ProductionReservationResolution,
  StockMovement,
  StockUnit,
} from "@/types/database";

export type ProductionMission = {
  plan_id: string;
  plan_number: string;
  execution_id: string | null;
  execution_number: string | null;
  production_date: string;
  priority: number | null;
  product_name: string;
  format_name: string;
  planned_bottles: number;
  planned_cartons: number | null;
  execution_status: ProductionExecutionStatus;
  reservation_status: "not_reserved" | "reserved" | "released" | "consumed";
};

export type ProductionHistoryRow = {
  execution_id: string;
  execution_number: string;
  plan_id: string;
  plan_number: string;
  production_date: string;
  status: ProductionExecutionStatus;
  product_summary: string;
  planned_bottles: number;
  actual_bottles: number | null;
  variance_bottles: number | null;
  started_by_name: string | null;
  completed_by_name: string | null;
  started_at: string | null;
  completed_at: string | null;
};

export type ProductionExecutionPayload = {
  execution: ProductionExecution;
  plan: ProductionPlan;
  items: Array<{
    item: ProductionExecutionItem;
    plan_item: ProductionPlanItem;
    resolutions: ProductionReservationResolution[];
  }>;
  issues: ProductionIssue[];
  movements: StockMovement[];
  stock_items: Array<{ id: string; name: string; unit: StockUnit }>;
};

export type ProductionActual = {
  executionItemId: string;
  quantity: number;
  mode: PlanningQuantityMode;
};

export type ProductionCompletionMaterial = {
  requirement_id: string;
  stock_item_id: string;
  name: string;
  unit: StockUnit;
  reserved_quantity: number;
  consumed_quantity: number;
  released_quantity: number;
};

export type ProductionCompletionPreview = {
  execution_id: string;
  items: Array<{
    execution_item_id: string;
    planned_bottles: number;
    planned_cartons: number | null;
    actual_bottles: number;
    actual_cartons: number;
    output_stock_item_id: string;
    materials: ProductionCompletionMaterial[];
  }>;
};

export const productionStatusLabels = {
  to_do: "To Do",
  in_progress: "In Progress",
  done: "Done",
  blocked: "Blocked",
  cancelled: "Cancelled",
} as const satisfies Record<ProductionExecutionStatus, string>;

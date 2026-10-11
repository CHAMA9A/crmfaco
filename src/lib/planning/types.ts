import type {
  PackagingFormat,
  PackagingRule,
  PlanningProduct,
  PlanningQuantityMode,
  ProductionComponentRole,
  ProductionPlan,
  ProductionPlanItem,
  ProductionPlanRequirement,
  ProductionPlanStatus,
  ProductionReservationStatus,
  ProductionRecipe,
  ProductionRecipeComponent,
  StockItem,
  StockLocation,
} from "@/types/database";

export type PlanningListRow = {
  id: string;
  plan_number: string | null;
  production_date: string;
  status: ProductionPlanStatus;
  priority: number | null;
  assigned_to: string | null;
  assigned_to_name: string | null;
  created_by: string;
  created_by_name: string;
  item_count: number;
  product_summary: string;
  quantity_summary: string;
  sufficiency: "not_calculated" | "insufficient" | "warning" | "sufficient";
  reservation_status: ProductionReservationStatus;
  created_at: string;
};

export type PlanningRequirementPreview = {
  recipe_component_id: string;
  stock_item_id: string;
  name: string;
  role: ProductionComponentRole;
  unit: "piece" | "liter" | "kilogram";
  quantity_per_bottle: number;
  required_quantity: number;
  physical_quantity: number;
  reserved_quantity: number;
  available_quantity: number;
  missing_quantity: number;
  projected_available_after_plan: number;
  minimum_stock: number | null;
  sufficient: boolean;
  below_minimum_after_plan: boolean;
};

export type PlanningPreview = {
  product_format_id: string;
  product_name: string;
  format_name: string;
  recipe_id: string;
  recipe_version: number;
  location_id: string;
  quantity_mode: PlanningQuantityMode;
  entered_quantity: number;
  planned_bottles: number;
  planned_cartons: number;
  bottles_per_carton: number;
  output: { stock_item_id: string; name: string; quantity: number };
  components: PlanningRequirementPreview[];
};

export type PlanningDetail = {
  plan: ProductionPlan;
  location_name: string;
  created_by_name: string;
  assigned_to_name: string | null;
  validated_by_name: string | null;
  items: Array<{
    item: ProductionPlanItem;
    requirements: ProductionPlanRequirement[];
  }>;
  reservation: ProductionReservationPayload;
};

export type ProductionPlanReservation = {
  reservation_id: string;
  requirement_id: string;
  stock_item_id: string;
  stock_item_name: string;
  unit: "piece" | "liter" | "kilogram";
  quantity: number;
  status: "active" | "released" | "consumed" | "cancelled";
  created_by: string;
  created_at: string;
  released_at: string | null;
  physical_quantity: number;
  reserved_quantity: number;
  available_quantity: number;
  minimum_stock: number | null;
  below_minimum: boolean;
};

export type ProductionReservationPayload = {
  plan_id: string;
  plan_number: string | null;
  plan_status: ProductionPlanStatus;
  reservation_status: ProductionReservationStatus;
  reserved_by: string | null;
  reserved_at: string | null;
  released_by: string | null;
  released_at: string | null;
  active_reservation_count: number;
  reservations: ProductionPlanReservation[];
};

export type ProductFormatOption = {
  id: string;
  product_id: string;
  product_name: string;
  format_id: string;
  format_name: string;
  format_code: string;
};

export type PlanningEditorData = {
  plan: PlanningDetail | null;
  products: PlanningProduct[];
  productFormats: ProductFormatOption[];
  locations: StockLocation[];
  factoryUsers: Array<{ id: string; display_name: string }>;
};

export type FactoryMission = {
  plan_id: string;
  plan_number: string;
  production_date: string;
  priority: number | null;
  product_name: string;
  format_name: string;
  planned_bottles: number;
  planned_cartons: number;
  status: ProductionPlanStatus;
  reservation_status: ProductionReservationStatus;
};

export type ProductionRecipeAdmin = ProductionRecipe & {
  components: Array<ProductionRecipeComponent & { stock_item_name: string }>;
};

export type PlanningAdminData = {
  products: PlanningProduct[];
  formats: PackagingFormat[];
  productFormats: ProductFormatOption[];
  rules: PackagingRule[];
  recipes: ProductionRecipeAdmin[];
  stockItems: StockItem[];
};

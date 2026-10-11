import type {
  PreparationStatus,
  StockItem,
  StockItemCategory,
  StockLocation,
} from "@/types/database";

export const preparationStatuses = ["draft", "confirmed", "cancelled"] as const;

export const preparationStatusLabels: Record<PreparationStatus, string> = {
  draft: "Draft",
  confirmed: "Confirmed",
  cancelled: "Cancelled",
};

export type RecipeComponent = {
  id: string;
  stock_item_id: string;
  stock_item_name: string;
  category: StockItemCategory;
  unit: "piece" | "liter" | "kilogram";
  quantity_per_output: number;
  position: number;
};

export type PreparedBottleRecipe = {
  id: string;
  output_stock_item_id: string;
  output_stock_item_name: string;
  product_format_id: string | null;
  product_name: string;
  format_name: string;
  version: number;
  is_active: boolean;
  supersedes_recipe_id: string | null;
  created_by: string;
  created_at: string;
  updated_at: string;
  components: RecipeComponent[];
};

export type RecipeListRow = Omit<
  PreparedBottleRecipe,
  "components" | "created_by" | "created_at" | "supersedes_recipe_id"
> & {
  component_count: number;
};

export type PreparationRequirement = {
  stock_item_id: string;
  name: string;
  category: StockItemCategory;
  quantity_per_output: number;
  required_quantity: number;
  physical_quantity: number;
  reserved_quantity: number;
  available_quantity: number;
  missing_quantity: number;
  sufficient: boolean;
};

export type PreparationPreview = {
  recipe_id: string;
  location_id: string;
  quantity: number;
  product_name: string;
  format_name: string;
  output: { stock_item_id: string; name: string; quantity: number };
  components: PreparationRequirement[];
};

export type BottlePreparation = {
  id: string;
  preparation_number: string | null;
  recipe_id: string;
  location_id: string;
  output_stock_item_id: string;
  product_format_id: string | null;
  product_name_snapshot: string;
  format_name_snapshot: string;
  output_item_name_snapshot: string;
  recipe_version_snapshot: number;
  planned_quantity: number | null;
  actual_quantity: number | null;
  status: PreparationStatus;
  comment: string | null;
  created_by: string;
  confirmed_by: string | null;
  confirmed_at: string | null;
  created_at: string;
  updated_at: string;
};

export type PreparationListRow = {
  id: string;
  preparation_number: string | null;
  status: PreparationStatus;
  product_name: string;
  format_name: string;
  quantity: number | null;
  output_stock_item_id: string;
  output_stock_item_name: string;
  created_by: string;
  created_by_name: string;
  confirmed_by: string | null;
  confirmed_by_name: string | null;
  confirmed_at: string | null;
  created_at: string;
};

export type PreparationDetailComponent = {
  id: string;
  stock_item_id: string;
  name: string;
  category: StockItemCategory;
  quantity_per_output: number;
  required_quantity: number | null;
  movement_id: string | null;
  movement_quantity: number | null;
};

export type PreparationDetail = {
  preparation: BottlePreparation;
  location_name: string;
  created_by_name: string;
  confirmed_by_name: string | null;
  components: PreparationDetailComponent[];
  output_movement: {
    id: string;
    stock_item_id: string;
    quantity: number;
    direction: "in";
    created_at: string;
  } | null;
};

export type PreparationEditorData = {
  preparation: PreparationDetail | null;
  recipes: RecipeListRow[];
  locations: StockLocation[];
};

export type PreparationHistoryData = {
  rows: PreparationListRow[];
  products: string[];
  formats: string[];
  users: { id: string; display_name: string }[];
};

export type RecipeAdminData = {
  recipes: PreparedBottleRecipe[];
  outputItems: StockItem[];
  componentItems: StockItem[];
};

export function preparationAvailability(requirements: PreparationRequirement[]) {
  return {
    sufficient: requirements.length > 0 && requirements.every((item) => item.sufficient),
    missingCount: requirements.filter((item) => !item.sufficient).length,
  };
}

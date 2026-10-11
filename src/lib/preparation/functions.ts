import { createServerFn } from "@tanstack/react-start";
import { setResponseHeader } from "@tanstack/react-start/server";
import { z } from "zod";

import { getSupabaseServerClient } from "@/lib/supabase/server";
import type { AppRole, Json, PreparationStatus } from "@/types/database";
import { preparationStatuses } from "./types";
import type {
  BottlePreparation,
  PreparationDetail,
  PreparationEditorData,
  PreparationHistoryData,
  PreparationListRow,
  PreparationPreview,
  PreparedBottleRecipe,
  RecipeAdminData,
  RecipeListRow,
} from "./types";

const allRoles: AppRole[] = ["admin", "management", "factory"];
const nullableUuid = z
  .union([z.literal(""), z.string().uuid()])
  .transform((value) => value || null);
const preparationIdSchema = z.object({ preparationId: z.string().uuid() });
const editorSchema = z.object({ preparationId: z.string().uuid().nullable().default(null) });
const previewSchema = z.object({
  recipeId: z.string().uuid(),
  quantity: z.coerce.number().positive().max(999_999_999),
  locationId: nullableUuid,
});
const draftSchema = z.object({
  recipeId: z.string().uuid(),
  locationId: nullableUuid,
  plannedQuantity: z.coerce.number().positive().max(999_999_999),
  comment: z
    .string()
    .trim()
    .max(2000)
    .transform((value) => value || null),
});
const updateDraftSchema = draftSchema.extend({
  preparationId: z.string().uuid(),
  locationId: z.string().uuid(),
  actualQuantity: z.coerce.number().positive().max(999_999_999),
});
const filtersSchema = z.object({
  dateFrom: z.string().date().nullable().default(null),
  dateTo: z.string().date().nullable().default(null),
  productName: z.string().trim().max(120).nullable().default(null),
  formatName: z.string().trim().max(80).nullable().default(null),
  createdBy: z.string().uuid().nullable().default(null),
  status: z.enum(preparationStatuses).nullable().default(null),
  limit: z.coerce.number().int().min(1).max(500).default(200),
});
const recipeComponentSchema = z.object({
  stockItemId: z.string().uuid(),
  quantityPerOutput: z.coerce.number().positive().max(999_999),
});
const recipeSchema = z.object({
  recipeId: z.string().uuid().nullable(),
  outputStockItemId: z.string().uuid(),
  productName: z.string().trim().min(1).max(120),
  formatName: z.string().trim().min(1).max(80),
  components: z.array(recipeComponentSchema).min(2).max(20),
});
const recipeIdSchema = z.object({ recipeId: z.string().uuid() });

function privateResponse() {
  setResponseHeader("Cache-Control", "private, no-store");
  setResponseHeader("Vary", "Cookie, Authorization");
}

async function getPreparationClient(roles: readonly AppRole[] = allRoles) {
  privateResponse();
  const supabase = getSupabaseServerClient();
  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData.user) throw new Error("Unauthorized");
  const [{ data: profile, error: profileError }, access] = await Promise.all([
    supabase.from("profiles").select("role, is_active").eq("id", userData.user.id).maybeSingle(),
    supabase.rpc("has_environment_access", { environment_code: "FACOLUB" }),
  ]);
  if (profileError || access.error) throw new Error("Unable to verify FACOLUB access");
  if (!profile?.is_active || !roles.includes(profile.role) || !access.data)
    throw new Error("Forbidden");
  return supabase;
}

async function listPreparations(
  supabase: Awaited<ReturnType<typeof getPreparationClient>>,
  filters: z.infer<typeof filtersSchema>,
) {
  const { data, error } = await supabase.rpc("list_bottle_preparations", {
    target_date_from: filters.dateFrom,
    target_date_to: filters.dateTo,
    target_product_name: filters.productName,
    target_format_name: filters.formatName,
    target_created_by: filters.createdBy,
    target_status: filters.status as PreparationStatus | null,
    target_limit: filters.limit,
  });
  if (error) throw new Error(error.message || "Unable to load preparations");
  return (data ?? []) as PreparationListRow[];
}

async function getDetail(supabase: Awaited<ReturnType<typeof getPreparationClient>>, id: string) {
  const { data, error } = await supabase.rpc("get_bottle_preparation", {
    target_preparation_id: id,
  });
  if (error || !data) throw new Error(error?.message ?? "Preparation not found");
  return data as Json as unknown as PreparationDetail;
}

export const getPreparationHomeFn = createServerFn({ method: "GET" }).handler(async () => {
  const supabase = await getPreparationClient();
  return {
    rows: await listPreparations(supabase, {
      dateFrom: null,
      dateTo: null,
      productName: null,
      formatName: null,
      createdBy: null,
      status: null,
      limit: 12,
    }),
  };
});

export const getPreparationHistoryFn = createServerFn({ method: "GET" }).handler(
  async (): Promise<PreparationHistoryData> => {
    const supabase = await getPreparationClient();
    const rows = await listPreparations(supabase, {
      dateFrom: null,
      dateTo: null,
      productName: null,
      formatName: null,
      createdBy: null,
      status: null,
      limit: 250,
    });
    return {
      rows,
      products: [...new Set(rows.map((row) => row.product_name))].sort(),
      formats: [...new Set(rows.map((row) => row.format_name))].sort(),
      users: [...new Map(rows.map((row) => [row.created_by, row.created_by_name])).entries()].map(
        ([id, display_name]) => ({ id, display_name }),
      ),
    };
  },
);

export const searchPreparationsFn = createServerFn({ method: "GET" })
  .validator((input: unknown) => filtersSchema.parse(input ?? {}))
  .handler(async ({ data }) => listPreparations(await getPreparationClient(), data));

export const getPreparationDetailFn = createServerFn({ method: "GET" })
  .validator((input: unknown) => preparationIdSchema.parse(input))
  .handler(async ({ data }) => getDetail(await getPreparationClient(), data.preparationId));

export const getPreparationEditorDataFn = createServerFn({ method: "GET" })
  .validator((input: unknown) => editorSchema.parse(input ?? {}))
  .handler(async ({ data }): Promise<PreparationEditorData> => {
    const supabase = await getPreparationClient();
    const [recipesResult, locationsResult, preparation] = await Promise.all([
      supabase.rpc("list_prepared_bottle_recipes", { target_include_inactive: false }),
      supabase.from("stock_locations").select("*").eq("is_active", true).order("name"),
      data.preparationId ? getDetail(supabase, data.preparationId) : Promise.resolve(null),
    ]);
    if (recipesResult.error || locationsResult.error)
      throw new Error("Unable to load preparation form data");
    if (preparation && preparation.preparation.status !== "draft")
      throw new Error("Only a draft preparation can be edited");
    return {
      preparation,
      recipes: (recipesResult.data ?? []) as RecipeListRow[],
      locations: locationsResult.data ?? [],
    };
  });

export const calculatePreparationRequirementsFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => previewSchema.parse(input))
  .handler(async ({ data }) => {
    const { data: result, error } = await (
      await getPreparationClient()
    ).rpc("calculate_preparation_requirements", {
      target_recipe_id: data.recipeId,
      target_quantity: data.quantity,
      target_location_id: data.locationId,
    });
    if (error || !result) throw new Error(error?.message ?? "Unable to calculate requirements");
    return result as Json as unknown as PreparationPreview;
  });

export const createPreparationDraftFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => draftSchema.parse(input))
  .handler(async ({ data }) => {
    const { data: result, error } = await (
      await getPreparationClient()
    ).rpc("create_bottle_preparation_draft", {
      target_recipe_id: data.recipeId,
      target_location_id: data.locationId,
      target_planned_quantity: data.plannedQuantity,
      target_comment: data.comment,
    });
    if (error || !result) throw new Error(error?.message ?? "Unable to create preparation draft");
    return result as BottlePreparation;
  });

export const updatePreparationDraftFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => updateDraftSchema.parse(input))
  .handler(async ({ data }) => {
    const { data: result, error } = await (
      await getPreparationClient()
    ).rpc("update_bottle_preparation_draft", {
      target_preparation_id: data.preparationId,
      target_recipe_id: data.recipeId,
      target_location_id: data.locationId,
      target_planned_quantity: data.plannedQuantity,
      target_actual_quantity: data.actualQuantity,
      target_comment: data.comment,
    });
    if (error || !result) throw new Error(error?.message ?? "Unable to update preparation draft");
    return result as BottlePreparation;
  });

export const confirmPreparationFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => preparationIdSchema.parse(input))
  .handler(async ({ data }) => {
    const { data: result, error } = await (
      await getPreparationClient()
    ).rpc("confirm_bottle_preparation", {
      target_preparation_id: data.preparationId,
    });
    if (error || !result) throw new Error(error?.message ?? "Unable to confirm preparation");
    return result as Json as unknown as PreparationDetail;
  });

export const cancelPreparationFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => preparationIdSchema.parse(input))
  .handler(async ({ data }) => {
    const { data: result, error } = await (
      await getPreparationClient()
    ).rpc("cancel_bottle_preparation", {
      target_preparation_id: data.preparationId,
    });
    if (error || !result) throw new Error(error?.message ?? "Unable to cancel preparation");
    return result as BottlePreparation;
  });

export const getRecipeAdminDataFn = createServerFn({ method: "GET" }).handler(
  async (): Promise<RecipeAdminData> => {
    const supabase = await getPreparationClient(["admin"]);
    const [listResult, outputResult, componentResult] = await Promise.all([
      supabase.rpc("list_prepared_bottle_recipes", { target_include_inactive: true }),
      supabase
        .from("stock_items")
        .select("*")
        .eq("category", "prepared_bottle")
        .eq("is_active", true)
        .order("name"),
      supabase
        .from("stock_items")
        .select("*")
        .in("category", ["empty_bottle", "label"])
        .eq("is_active", true)
        .order("name"),
    ]);
    if (listResult.error || outputResult.error || componentResult.error)
      throw new Error("Unable to load recipe settings");
    const details = await Promise.all(
      ((listResult.data ?? []) as RecipeListRow[]).map(async (row) => {
        const { data, error } = await supabase.rpc("get_prepared_bottle_recipe", {
          target_recipe_id: row.id,
        });
        if (error || !data) throw new Error(error?.message ?? "Unable to load recipe");
        return data as Json as unknown as PreparedBottleRecipe;
      }),
    );
    return {
      recipes: details,
      outputItems: outputResult.data ?? [],
      componentItems: componentResult.data ?? [],
    };
  },
);

export const saveRecipeFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => recipeSchema.parse(input))
  .handler(async ({ data }) => {
    const supabase = await getPreparationClient(["admin"]);
    const components = data.components.map((item) => ({
      stock_item_id: item.stockItemId,
      quantity_per_output: item.quantityPerOutput,
    })) as Json;
    const call = data.recipeId
      ? supabase.rpc("update_prepared_bottle_recipe", {
          target_recipe_id: data.recipeId,
          target_output_stock_item_id: data.outputStockItemId,
          target_product_format_id: null,
          target_product_name: data.productName,
          target_format_name: data.formatName,
          target_components: components,
        })
      : supabase.rpc("create_prepared_bottle_recipe", {
          target_output_stock_item_id: data.outputStockItemId,
          target_product_format_id: null,
          target_product_name: data.productName,
          target_format_name: data.formatName,
          target_components: components,
        });
    const { data: result, error } = await call;
    if (error || !result) throw new Error(error?.message ?? "Unable to save recipe");
    return result as Json as unknown as PreparedBottleRecipe;
  });

export const deactivateRecipeFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => recipeIdSchema.parse(input))
  .handler(async ({ data }) => {
    const { data: result, error } = await (
      await getPreparationClient(["admin"])
    ).rpc("deactivate_prepared_bottle_recipe", { target_recipe_id: data.recipeId });
    if (error || !result) throw new Error(error?.message ?? "Unable to deactivate recipe");
    return result as Json as unknown as PreparedBottleRecipe;
  });

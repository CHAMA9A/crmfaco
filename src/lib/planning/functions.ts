import { createServerFn } from "@tanstack/react-start";
import { setResponseHeader } from "@tanstack/react-start/server";
import { z } from "zod";
import { getSupabaseServerClient } from "@/lib/supabase/server";
import type { AppRole, Json } from "@/types/database";
import type {
  FactoryMission,
  PlanningAdminData,
  PlanningDetail,
  PlanningEditorData,
  PlanningListRow,
  PlanningPreview,
  ProductionReservationPayload,
  ProductFormatOption,
  ProductionRecipeAdmin,
} from "./types";

const managerRoles: AppRole[] = ["admin", "management"];
const nullableUuid = z
  .union([z.literal(""), z.string().uuid()])
  .transform((value) => value || null);
const planIdSchema = z.object({ planId: z.string().uuid() });
const editorSchema = z.object({ planId: z.string().uuid().nullable().default(null) });
const previewSchema = z.object({
  productFormatId: z.string().uuid(),
  quantity: z.coerce.number().int().positive().max(999_999_999),
  mode: z.enum(["bottles", "cartons"]),
  locationId: z.string().uuid(),
});
const planSchema = previewSchema.extend({
  planId: z.string().uuid().nullable(),
  planItemId: z.string().uuid().nullable(),
  productionDate: z.string().date(),
  priority: z.coerce.number().int().min(1).max(5).nullable(),
  assignedTo: nullableUuid,
  comment: z
    .string()
    .trim()
    .max(2000)
    .transform((value) => value || null),
  validateAfterSave: z.boolean(),
});

function privateResponse() {
  setResponseHeader("Cache-Control", "private, no-store");
  setResponseHeader("Vary", "Cookie, Authorization");
}

async function getPlanningClient(roles: readonly AppRole[] = managerRoles) {
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

function joinProductFormats(
  rows: Array<{ id: string; product_id: string; format_id: string }>,
  products: Array<{ id: string; name: string }>,
  formats: Array<{ id: string; name: string; code: string }>,
): ProductFormatOption[] {
  const productMap = new Map(products.map((item) => [item.id, item]));
  const formatMap = new Map(formats.map((item) => [item.id, item]));
  return rows.flatMap((row) => {
    const product = productMap.get(row.product_id);
    const format = formatMap.get(row.format_id);
    return product && format
      ? [{ ...row, product_name: product.name, format_name: format.name, format_code: format.code }]
      : [];
  });
}

async function getDetail(id: string): Promise<PlanningDetail> {
  const supabase = await getPlanningClient();
  const [detail, reservation] = await Promise.all([
    supabase.rpc("get_production_plan", { target_plan_id: id }),
    supabase.rpc("get_production_plan_reservations", { target_plan_id: id }),
  ]);
  if (detail.error || !detail.data)
    throw new Error(detail.error?.message ?? "Production plan not found");
  if (reservation.error || !reservation.data)
    throw new Error(reservation.error?.message ?? "Unable to load material reservations");
  return {
    ...(detail.data as Json as unknown as Omit<PlanningDetail, "reservation">),
    reservation: reservation.data as Json as unknown as ProductionReservationPayload,
  };
}

export const getPlanningHomeFn = createServerFn({ method: "GET" }).handler(async () => {
  const supabase = await getPlanningClient();
  const [plans, products, reservationStates] = await Promise.all([
    supabase.rpc("list_production_plans", { target_limit: 250 }),
    supabase.from("products").select("*").eq("is_active", true).order("name"),
    supabase.from("production_plans").select("id, reservation_status"),
  ]);
  if (plans.error || products.error || reservationStates.error)
    throw new Error(plans.error?.message ?? "Unable to load planning");
  const reservationByPlan = new Map(
    (reservationStates.data ?? []).map((plan) => [plan.id, plan.reservation_status]),
  );
  return {
    rows: (
      (plans.data ?? []) as Json[] as unknown as Omit<PlanningListRow, "reservation_status">[]
    ).map((plan) => ({
      ...plan,
      reservation_status: reservationByPlan.get(plan.id) ?? "not_reserved",
    })),
    products: products.data ?? [],
  };
});

export const getPlanningDetailFn = createServerFn({ method: "GET" })
  .validator((input: unknown) => planIdSchema.parse(input))
  .handler(({ data }) => getDetail(data.planId));

export const getPlanningEditorDataFn = createServerFn({ method: "GET" })
  .validator((input: unknown) => editorSchema.parse(input ?? {}))
  .handler(async ({ data }): Promise<PlanningEditorData> => {
    const supabase = await getPlanningClient();
    const [products, formats, productFormats, locations, factoryUsers, plan] = await Promise.all([
      supabase.from("products").select("*").eq("is_active", true).order("name"),
      supabase.from("packaging_formats").select("*").eq("is_active", true).order("volume_liters"),
      supabase.from("product_formats").select("*").eq("is_active", true),
      supabase.from("stock_locations").select("*").eq("is_active", true).order("name"),
      supabase
        .from("profiles")
        .select("id, display_name")
        .eq("role", "factory")
        .eq("is_active", true),
      data.planId ? getDetail(data.planId) : Promise.resolve(null),
    ]);
    if (products.error || formats.error || productFormats.error || locations.error)
      throw new Error("Unable to load planning form data");
    if (plan && plan.plan.status !== "draft") throw new Error("Only a draft plan can be edited");
    return {
      plan,
      products: products.data ?? [],
      productFormats: joinProductFormats(
        productFormats.data ?? [],
        products.data ?? [],
        formats.data ?? [],
      ),
      locations: locations.data ?? [],
      factoryUsers: factoryUsers.data ?? [],
    };
  });

export const calculateProductionRequirementsFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => previewSchema.parse(input))
  .handler(async ({ data }) => {
    const { data: result, error } = await (
      await getPlanningClient()
    ).rpc("calculate_production_requirements", {
      target_product_format_id: data.productFormatId,
      target_quantity: data.quantity,
      target_mode: data.mode,
      target_location_id: data.locationId,
    });
    if (error || !result)
      throw new Error(error?.message ?? "Unable to calculate production requirements");
    return result as Json as unknown as PlanningPreview;
  });

export const saveProductionPlanFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => planSchema.parse(input))
  .handler(async ({ data }) => {
    const supabase = await getPlanningClient();
    const planCall = data.planId
      ? supabase.rpc("update_production_plan_draft", {
          target_plan_id: data.planId,
          target_production_date: data.productionDate,
          target_location_id: data.locationId,
          target_priority: data.priority,
          target_assigned_to: data.assignedTo,
          target_comment: data.comment,
        })
      : supabase.rpc("create_production_plan_draft", {
          target_production_date: data.productionDate,
          target_location_id: data.locationId,
          target_priority: data.priority,
          target_assigned_to: data.assignedTo,
          target_comment: data.comment,
        });
    const { data: plan, error: planError } = await planCall;
    if (planError || !plan) throw new Error(planError?.message ?? "Unable to save production plan");
    const { error: itemError } = await supabase.rpc("save_production_plan_item", {
      target_plan_id: plan.id,
      target_item_id: data.planItemId,
      target_product_format_id: data.productFormatId,
      target_quantity: data.quantity,
      target_mode: data.mode,
      target_position: 1,
    });
    if (itemError) throw new Error(itemError.message || "Unable to save production line");
    if (data.validateAfterSave) {
      const { error } = await supabase.rpc("validate_production_plan", { target_plan_id: plan.id });
      if (error) throw new Error(error.message || "Unable to validate production plan");
    }
    return { id: plan.id };
  });

export const validateProductionPlanFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => planIdSchema.parse(input))
  .handler(async ({ data }) => {
    const { error } = await (
      await getPlanningClient()
    ).rpc("validate_production_plan", { target_plan_id: data.planId });
    if (error) throw new Error(error.message || "Unable to validate production plan");
    return { ok: true };
  });
export const markProductionPlanPlannedFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => planIdSchema.parse(input))
  .handler(async ({ data }) => {
    const { error } = await (
      await getPlanningClient()
    ).rpc("plan_production_plan", { target_plan_id: data.planId });
    if (error) throw new Error(error.message || "Unable to mark production plan planned");
    return { ok: true };
  });
export const cancelProductionPlanFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => planIdSchema.parse(input))
  .handler(async ({ data }) => {
    const { error } = await (
      await getPlanningClient()
    ).rpc("cancel_production_plan", { target_plan_id: data.planId });
    if (error) throw new Error(error.message || "Unable to cancel production plan");
    return { ok: true };
  });

export const reserveProductionPlanFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => planIdSchema.parse(input))
  .handler(async ({ data }) => {
    const { data: result, error } = await (
      await getPlanningClient()
    ).rpc("reserve_production_plan", { target_plan_id: data.planId });
    if (error || !result) throw new Error(error?.message || "Unable to reserve plan materials");
    return result as Json as unknown as ProductionReservationPayload;
  });

export const releaseProductionPlanReservationsFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => planIdSchema.parse(input))
  .handler(async ({ data }) => {
    const { data: result, error } = await (
      await getPlanningClient()
    ).rpc("release_production_plan_reservations", { target_plan_id: data.planId });
    if (error || !result) throw new Error(error?.message || "Unable to release plan reservations");
    return result as Json as unknown as ProductionReservationPayload;
  });

export const getFactoryMissionsFn = createServerFn({ method: "GET" }).handler(async () => {
  const supabase = await getPlanningClient(["factory"]);
  const { data, error } = await supabase.rpc("list_factory_production_missions", {});
  if (error) throw new Error(error.message || "Unable to load factory missions");
  const missions = (data ?? []) as Json[] as unknown as Omit<
    FactoryMission,
    "reservation_status"
  >[];
  const planIds = [...new Set(missions.map((mission) => mission.plan_id))];
  const states = planIds.length
    ? await supabase.from("production_plans").select("id, reservation_status").in("id", planIds)
    : { data: [], error: null };
  if (states.error) throw new Error(states.error.message || "Unable to load reservation status");
  const stateByPlan = new Map(
    (states.data ?? []).map((plan) => [plan.id, plan.reservation_status]),
  );
  return missions.map((mission) => ({
    ...mission,
    reservation_status: stateByPlan.get(mission.plan_id) ?? "not_reserved",
  }));
});

const productSchema = z.object({
  productId: z.string().uuid().nullable(),
  code: z
    .string()
    .trim()
    .max(60)
    .transform((value) => value || null),
  name: z.string().trim().min(1).max(120),
});
const productFormatSchema = z.object({ productId: z.string().uuid(), formatId: z.string().uuid() });
const ruleSchema = z.object({
  formatId: z.string().uuid(),
  bottlesPerCarton: z.coerce.number().int().positive(),
});
const recipeSchema = z.object({
  recipeId: z.string().uuid().nullable(),
  productFormatId: z.string().uuid(),
  outputStockItemId: z.string().uuid(),
  components: z
    .array(
      z.object({
        stockItemId: z.string().uuid(),
        role: z.enum(["prepared_bottle", "bulk_lubricant", "seal", "carton", "other"]),
        quantityPerBottle: z.coerce.number().positive().max(999_999),
      }),
    )
    .min(4)
    .max(5),
});

export const getPlanningAdminDataFn = createServerFn({ method: "GET" }).handler(
  async (): Promise<PlanningAdminData> => {
    const supabase = await getPlanningClient(["admin"]);
    const [products, formats, productFormats, rules, recipes, components, stockItems] =
      await Promise.all([
        supabase.from("products").select("*").order("name"),
        supabase.from("packaging_formats").select("*").order("volume_liters"),
        supabase.from("product_formats").select("*"),
        supabase.from("packaging_rules").select("*").eq("is_active", true),
        supabase.from("production_recipes").select("*").order("created_at", { ascending: false }),
        supabase.from("production_recipe_components").select("*").order("position"),
        supabase
          .from("stock_items")
          .select("*")
          .in("category", [
            "prepared_bottle",
            "bulk_lubricant",
            "seal",
            "carton",
            "finished_product",
            "other",
          ])
          .eq("is_active", true)
          .order("name"),
      ]);
    const failure = [
      products,
      formats,
      productFormats,
      rules,
      recipes,
      components,
      stockItems,
    ].find((result) => result.error)?.error;
    if (failure) throw new Error(failure.message || "Unable to load production settings");
    const itemNames = new Map((stockItems.data ?? []).map((item) => [item.id, item.name]));
    const recipeRows: ProductionRecipeAdmin[] = (recipes.data ?? []).map((recipe) => ({
      ...recipe,
      components: (components.data ?? [])
        .filter((component) => component.recipe_id === recipe.id)
        .map((component) => ({
          ...component,
          stock_item_name: itemNames.get(component.component_stock_item_id) ?? "Unknown item",
        })),
    }));
    return {
      products: products.data ?? [],
      formats: formats.data ?? [],
      productFormats: joinProductFormats(
        productFormats.data ?? [],
        products.data ?? [],
        formats.data ?? [],
      ),
      rules: rules.data ?? [],
      recipes: recipeRows,
      stockItems: stockItems.data ?? [],
    };
  },
);

export const savePlanningProductFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => productSchema.parse(input))
  .handler(async ({ data }) => {
    const { error } = await (
      await getPlanningClient(["admin"])
    ).rpc("save_planning_product", {
      target_id: data.productId,
      target_code: data.code,
      target_name: data.name,
      target_is_active: true,
    });
    if (error) throw new Error(error.message || "Unable to save product");
    return { ok: true };
  });
export const saveProductFormatFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => productFormatSchema.parse(input))
  .handler(async ({ data }) => {
    const { error } = await (
      await getPlanningClient(["admin"])
    ).rpc("save_product_format", {
      target_id: null,
      target_product_id: data.productId,
      target_format_id: data.formatId,
      target_is_active: true,
    });
    if (error) throw new Error(error.message || "Unable to save product format");
    return { ok: true };
  });
export const configurePackagingRuleFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => ruleSchema.parse(input))
  .handler(async ({ data }) => {
    const { error } = await (
      await getPlanningClient(["admin"])
    ).rpc("configure_packaging_rule", {
      target_format_id: data.formatId,
      target_bottles_per_carton: data.bottlesPerCarton,
    });
    if (error) throw new Error(error.message || "Unable to configure packaging rule");
    return { ok: true };
  });
export const saveProductionRecipeFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => recipeSchema.parse(input))
  .handler(async ({ data }) => {
    const supabase = await getPlanningClient(["admin"]);
    const target_components = data.components.map((component) => ({
      stock_item_id: component.stockItemId,
      component_role: component.role,
      quantity_per_bottle: component.quantityPerBottle,
    })) as Json;
    const call = data.recipeId
      ? supabase.rpc("update_production_recipe", {
          target_recipe_id: data.recipeId,
          target_output_stock_item_id: data.outputStockItemId,
          target_components,
        })
      : supabase.rpc("create_production_recipe", {
          target_product_format_id: data.productFormatId,
          target_output_stock_item_id: data.outputStockItemId,
          target_components,
        });
    const { error } = await call;
    if (error) throw new Error(error.message || "Unable to save production recipe");
    return { ok: true };
  });

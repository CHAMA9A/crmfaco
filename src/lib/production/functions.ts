import { createServerFn } from "@tanstack/react-start";
import { setResponseHeader } from "@tanstack/react-start/server";
import { z } from "zod";
import { getSupabaseServerClient } from "@/lib/supabase/server";
import type { AppRole, Json } from "@/types/database";
import type {
  ProductionActual,
  ProductionCompletionPreview,
  ProductionExecutionPayload,
  ProductionHistoryRow,
  ProductionMission,
} from "./types";

const allRoles: AppRole[] = ["admin", "management", "factory"];
const managerRoles: AppRole[] = ["admin", "management"];
const uuid = z.string().uuid();
const executionSchema = z.object({ executionId: uuid });
const actualSchema = z.object({
  executionItemId: uuid,
  quantity: z.coerce.number().int().positive().max(999_999_999),
  mode: z.enum(["bottles", "cartons"]),
});
const completionSchema = executionSchema.extend({ actuals: z.array(actualSchema).min(1) });

function privateResponse() {
  setResponseHeader("Cache-Control", "private, no-store");
  setResponseHeader("Vary", "Cookie, Authorization");
}

async function getProductionClient(roles: readonly AppRole[]) {
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

function toRpcActuals(actuals: ProductionActual[]): Json {
  return actuals.map((actual) => ({
    execution_item_id: actual.executionItemId,
    quantity: actual.quantity,
    mode: actual.mode,
  }));
}

export const getFactoryProductionMissionsFn = createServerFn({ method: "GET" }).handler(
  async () => {
    const { data, error } = await (
      await getProductionClient(["factory"])
    ).rpc("list_factory_production_execution_missions", {});
    if (error) throw new Error(error.message || "Unable to load production missions");
    return (data ?? []) as Json[] as unknown as ProductionMission[];
  },
);

export const prepareAndStartProductionFn = createServerFn({ method: "POST" })
  .validator((input: unknown) =>
    z.object({ planId: uuid, executionId: uuid.nullable().default(null) }).parse(input),
  )
  .handler(async ({ data }) => {
    const supabase = await getProductionClient(allRoles);
    let executionId = data.executionId;
    if (!executionId) {
      const prepared = await supabase.rpc("prepare_production_execution", {
        target_plan_id: data.planId,
      });
      if (prepared.error || !prepared.data)
        throw new Error(prepared.error?.message || "Unable to prepare production");
      executionId = (prepared.data as Json as unknown as ProductionExecutionPayload).execution.id;
    }
    const { error } = await supabase.rpc("start_production_execution", {
      target_execution_id: executionId,
    });
    if (error) throw new Error(error.message || "Unable to start production");
    return { executionId };
  });

export const getProductionHistoryFn = createServerFn({ method: "GET" }).handler(async () => {
  const { data, error } = await (
    await getProductionClient(managerRoles)
  ).rpc("list_production_executions", { target_limit: 500 });
  if (error) throw new Error(error.message || "Unable to load production history");
  return (data ?? []) as Json[] as unknown as ProductionHistoryRow[];
});

export const getProductionExecutionFn = createServerFn({ method: "GET" })
  .validator((input: unknown) => executionSchema.parse(input))
  .handler(async ({ data }) => {
    const supabase = await getProductionClient(allRoles);
    const { data: result, error } = await supabase.rpc("get_production_execution", {
      target_execution_id: data.executionId,
    });
    if (error || !result) throw new Error(error?.message || "Production execution not found");
    const payload = result as Json as unknown as Omit<ProductionExecutionPayload, "stock_items">;
    const stockItemIds = [
      ...new Set([
        ...payload.movements.map((movement) => movement.stock_item_id),
        ...payload.items.flatMap(({ item, resolutions }) => [
          item.output_stock_item_id,
          ...resolutions.map((resolution) => resolution.stock_item_id),
        ]),
      ]),
    ];
    const stockItems = stockItemIds.length
      ? await supabase.from("stock_items").select("id, name, unit").in("id", stockItemIds)
      : { data: [], error: null };
    if (stockItems.error) throw new Error(stockItems.error.message || "Unable to load stock items");
    return { ...payload, stock_items: stockItems.data ?? [] };
  });

export const startProductionExecutionFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => executionSchema.parse(input))
  .handler(async ({ data }) => {
    const { error } = await (
      await getProductionClient(allRoles)
    ).rpc("start_production_execution", { target_execution_id: data.executionId });
    if (error) throw new Error(error.message || "Unable to start production");
    return { ok: true };
  });

export const reportProductionIssueFn = createServerFn({ method: "POST" })
  .validator((input: unknown) =>
    executionSchema
      .extend({
        category: z.enum([
          "missing_stock",
          "damaged_material",
          "machine_issue",
          "wrong_quantity",
          "other",
        ]),
        description: z.string().trim().min(1).max(2000),
      })
      .parse(input),
  )
  .handler(async ({ data }) => {
    const { error } = await (
      await getProductionClient(allRoles)
    ).rpc("report_production_issue", {
      target_execution_id: data.executionId,
      target_category: data.category,
      target_description: data.description,
    });
    if (error) throw new Error(error.message || "Unable to report production issue");
    return { ok: true };
  });

export const resolveProductionIssueFn = createServerFn({ method: "POST" })
  .validator((input: unknown) =>
    z
      .object({
        issueId: uuid,
        targetStatus: z.enum(["to_do", "in_progress"]),
        resolutionNote: z.string().trim().min(1).max(2000),
      })
      .parse(input),
  )
  .handler(async ({ data }) => {
    const { error } = await (
      await getProductionClient(managerRoles)
    ).rpc("resolve_production_issue", {
      target_issue_id: data.issueId,
      target_resume_status: data.targetStatus,
      target_resolution_note: data.resolutionNote,
    });
    if (error) throw new Error(error.message || "Unable to resolve production issue");
    return { ok: true };
  });

export const calculateProductionCompletionFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => completionSchema.parse(input))
  .handler(async ({ data }) => {
    const { data: result, error } = await (
      await getProductionClient(allRoles)
    ).rpc("calculate_production_execution_completion", {
      target_execution_id: data.executionId,
      target_actuals: toRpcActuals(data.actuals),
    });
    if (error || !result) throw new Error(error?.message || "Unable to calculate completion");
    return result as Json as unknown as ProductionCompletionPreview;
  });

export const completeProductionExecutionFn = createServerFn({ method: "POST" })
  .validator((input: unknown) =>
    completionSchema
      .extend({
        comment: z
          .string()
          .trim()
          .max(2000)
          .transform((value) => value || null),
      })
      .parse(input),
  )
  .handler(async ({ data }) => {
    const { error } = await (
      await getProductionClient(allRoles)
    ).rpc("complete_production_execution", {
      target_execution_id: data.executionId,
      target_actuals: toRpcActuals(data.actuals),
      target_comment: data.comment,
    });
    if (error) throw new Error(error.message || "Unable to complete production");
    return { ok: true };
  });

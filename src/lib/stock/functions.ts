import { createServerFn } from "@tanstack/react-start";
import { setResponseHeader } from "@tanstack/react-start/server";
import { z } from "zod";

import { getSupabaseServerClient } from "@/lib/supabase/server";
import type { AppRole, Json, StockItemCategory, StockMovementType } from "@/types/database";
import {
  stockCategories,
  stockMovementTypes,
  stockUnits,
  type StockHistoryData,
  type StockItemAdminData,
  type StockOverviewData,
} from "./types";

const allRoles: AppRole[] = ["admin", "management", "factory"];
const managerRoles: AppRole[] = ["admin", "management"];

const nullableUuid = z
  .union([z.literal(""), z.string().uuid()])
  .transform((value) => value || null);
const nullableText = (max: number) =>
  z
    .string()
    .trim()
    .max(max)
    .transform((value) => value || null);

const movementSchema = z.object({
  stockItemId: z.string().uuid(),
  locationId: nullableUuid,
  movementType: z.enum(stockMovementTypes),
  quantity: z.coerce.number().positive().max(999_999_999),
  direction: z.enum(["in", "out"]),
  referenceType: nullableText(80),
  referenceId: nullableUuid,
  reason: nullableText(1000),
  metadata: z.record(z.string(), z.json()).default({}),
  allowNegative: z.boolean().default(false),
});

const correctionSchema = z.object({
  movementId: z.string().uuid(),
  quantity: z.coerce.number().positive().max(999_999_999),
  reason: z.string().trim().min(1).max(1000),
  allowNegative: z.boolean().default(false),
});

const reservationSchema = z.object({
  stockItemId: z.string().uuid(),
  locationId: nullableUuid,
  quantity: z.coerce.number().positive().max(999_999_999),
  referenceType: z.string().trim().min(1).max(80),
  referenceId: z.string().uuid(),
});

const reservationIdSchema = z.object({ reservationId: z.string().uuid() });
const balanceSchema = z.object({ stockItemId: z.string().uuid(), locationId: nullableUuid });
const historySchema = z.object({
  stockItemId: z.string().uuid().nullable().default(null),
  category: z.enum(stockCategories).nullable().default(null),
  dateFrom: z.string().date().nullable().default(null),
  dateTo: z.string().date().nullable().default(null),
  movementType: z.enum(stockMovementTypes).nullable().default(null),
  createdBy: z.string().uuid().nullable().default(null),
  limit: z.coerce.number().int().min(1).max(1000).default(500),
});
const stockItemSchema = z.object({
  id: nullableUuid,
  code: nullableText(60),
  name: z.string().trim().min(1).max(200),
  category: z.enum(stockCategories),
  unit: z.enum(stockUnits),
  productFormatId: nullableUuid,
  minimumStock: z
    .union([z.literal(""), z.coerce.number().min(0).max(999_999_999)])
    .transform((value) => (value === "" ? null : value)),
  notes: nullableText(2000),
  isActive: z.boolean(),
});

function privateResponse() {
  setResponseHeader("Cache-Control", "private, no-store");
  setResponseHeader("Vary", "Cookie, Authorization");
}

async function getStockClient(roles: readonly AppRole[]) {
  privateResponse();
  const supabase = getSupabaseServerClient();
  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData.user) throw new Error("Unauthorized");

  const [{ data: profile, error: profileError }, accessResult] = await Promise.all([
    supabase.from("profiles").select("role, is_active").eq("id", userData.user.id).maybeSingle(),
    supabase.rpc("has_environment_access", { environment_code: "FACOLUB" }),
  ]);
  if (profileError || accessResult.error) throw new Error("Unable to verify FACOLUB access");
  if (!profile?.is_active || !roles.includes(profile.role) || !accessResult.data) {
    throw new Error("Forbidden");
  }
  return supabase;
}

export const getStockOverviewFn = createServerFn({ method: "GET" }).handler(
  async (): Promise<StockOverviewData> => {
    const supabase = await getStockClient(allRoles);
    const [itemsResult, locationsResult, balancesResult] = await Promise.all([
      supabase.from("stock_items").select("*").eq("is_active", true).order("name"),
      supabase.from("stock_locations").select("*").eq("is_active", true).order("name"),
      supabase.from("stock_balances").select("*"),
    ]);
    if (itemsResult.error || locationsResult.error || balancesResult.error) {
      throw new Error("Unable to load stock balances");
    }
    const balances = new Map(
      (balancesResult.data ?? []).map((balance) => [
        `${balance.stock_item_id}:${balance.location_id}`,
        balance,
      ]),
    );
    const locations = locationsResult.data ?? [];
    return {
      locations,
      rows: (itemsResult.data ?? []).flatMap((item) =>
        locations.map((location) => {
          const balance = balances.get(`${item.id}:${location.id}`);
          return {
            ...item,
            location_id: location.id,
            location_name: location.name,
            physical_quantity: balance?.physical_quantity ?? 0,
            reserved_quantity: balance?.reserved_quantity ?? 0,
            available_quantity: balance?.available_quantity ?? 0,
          };
        }),
      ),
    };
  },
);

export const getStockHistoryFn = createServerFn({ method: "GET" })
  .validator((input: unknown) => historySchema.parse(input ?? {}))
  .handler(async ({ data }): Promise<StockHistoryData> => {
    const supabase = await getStockClient(allRoles);
    const { data: rows, error } = await supabase.rpc("get_stock_movement_history", {
      target_stock_item_id: data.stockItemId,
      target_category: data.category,
      target_date_from: data.dateFrom,
      target_date_to: data.dateTo,
      target_movement_type: data.movementType,
      target_created_by: data.createdBy,
      target_limit: data.limit,
    });
    if (error) throw new Error(error.message || "Unable to load stock movement history");
    return { rows: rows ?? [] };
  });

export const getStockItemsForAdminFn = createServerFn({ method: "GET" }).handler(
  async (): Promise<StockItemAdminData> => {
    const supabase = await getStockClient(["admin"]);
    const { data, error } = await supabase.from("stock_items").select("*").order("name");
    if (error) throw new Error("Unable to load stock items");
    return { items: data ?? [] };
  },
);

export const createStockMovementFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => movementSchema.parse(input))
  .handler(async ({ data }) => {
    const supabase = await getStockClient(managerRoles);
    const { data: result, error } = await supabase.rpc("record_stock_movement", {
      target_stock_item_id: data.stockItemId,
      target_location_id: data.locationId,
      target_movement_type: data.movementType,
      target_quantity: data.quantity,
      target_direction: data.direction,
      target_reference_type: data.referenceType,
      target_reference_id: data.referenceId,
      target_reason: data.reason,
      target_metadata: data.metadata as Json,
      target_allow_negative: data.allowNegative,
    });
    if (error || !result?.[0]) throw new Error(error?.message ?? "Unable to record stock movement");
    return result[0];
  });

export const createStockCorrectionFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => correctionSchema.parse(input))
  .handler(async ({ data }) => {
    const supabase = await getStockClient(["admin"]);
    const { data: result, error } = await supabase.rpc("record_stock_correction", {
      target_movement_id: data.movementId,
      target_quantity: data.quantity,
      target_reason: data.reason,
      target_allow_negative: data.allowNegative,
    });
    if (error || !result?.[0]) throw new Error(error?.message ?? "Unable to record correction");
    return result[0];
  });

export const getStockBalanceFn = createServerFn({ method: "GET" })
  .validator((input: unknown) => balanceSchema.parse(input))
  .handler(async ({ data }) => {
    const supabase = await getStockClient(allRoles);
    const { data: result, error } = await supabase.rpc("get_stock_balance", {
      target_stock_item_id: data.stockItemId,
      target_location_id: data.locationId,
    });
    if (error || !result?.[0]) throw new Error(error?.message ?? "Unable to load stock balance");
    return result[0];
  });

export const createReservationFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => reservationSchema.parse(input))
  .handler(async ({ data }) => {
    const supabase = await getStockClient(managerRoles);
    const { data: result, error } = await supabase.rpc("create_stock_reservation", {
      target_stock_item_id: data.stockItemId,
      target_location_id: data.locationId,
      target_quantity: data.quantity,
      target_reference_type: data.referenceType,
      target_reference_id: data.referenceId,
    });
    if (error || !result) throw new Error(error?.message ?? "Unable to create stock reservation");
    return result;
  });

export const releaseReservationFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => reservationIdSchema.parse(input))
  .handler(async ({ data }) => {
    const supabase = await getStockClient(managerRoles);
    const { data: result, error } = await supabase.rpc("release_stock_reservation", {
      target_reservation_id: data.reservationId,
    });
    if (error || !result) throw new Error(error?.message ?? "Unable to release reservation");
    return result;
  });

export const consumeReservationFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => reservationIdSchema.parse(input))
  .handler(async ({ data }) => {
    const supabase = await getStockClient(managerRoles);
    const { data: result, error } = await supabase.rpc("consume_stock_reservation", {
      target_reservation_id: data.reservationId,
    });
    if (error || !result) throw new Error(error?.message ?? "Unable to consume reservation");
    return result;
  });

export const saveStockItemFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => stockItemSchema.parse(input))
  .handler(async ({ data }) => {
    const supabase = await getStockClient(["admin"]);
    const { data: result, error } = await supabase.rpc("save_stock_item", {
      target_id: data.id,
      target_code: data.code,
      target_name: data.name,
      target_category: data.category as StockItemCategory,
      target_unit: data.unit,
      target_product_format_id: data.productFormatId,
      target_minimum_stock: data.minimumStock,
      target_notes: data.notes,
      target_is_active: data.isActive,
    });
    if (error || !result) throw new Error(error?.message ?? "Unable to save stock item");
    return result;
  });

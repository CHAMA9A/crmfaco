import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";

import { getSupabaseServerClient } from "@/lib/supabase/server";
import { stockCategories } from "@/lib/stock/types";
import type { AppRole, StockAdjustmentType, StockCountStatus } from "@/types/database";
import {
  stockAdjustmentStatuses,
  stockAdjustmentTypes,
  stockCountStatuses,
  type NewStockCountData,
  type StockAdjustmentListRow,
  type StockCountDetail,
  type StockCountListRow,
  type StockCountWorkspaceData,
} from "./types";

const allRoles: AppRole[] = ["admin", "management", "factory"];
const managerRoles: AppRole[] = ["admin", "management"];
const uuid = z.string().uuid();
const nullableUuid = z.union([z.literal(""), uuid]).transform((value) => value || null);
const reason = z.string().trim().min(1).max(2000);

async function getClient(roles: readonly AppRole[]) {
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
  return { supabase, userId: userData.user.id, role: profile.role };
}

async function loadReferenceData(
  supabase: ReturnType<typeof getSupabaseServerClient>,
): Promise<Pick<StockCountWorkspaceData, "locations" | "items">> {
  const [locations, items, balances] = await Promise.all([
    supabase.from("stock_locations").select("*").eq("is_active", true).order("name"),
    supabase.from("stock_items").select("*").eq("is_active", true).order("name"),
    supabase.from("stock_balances").select("stock_item_id, location_id, physical_quantity"),
  ]);
  if (locations.error || items.error || balances.error)
    throw new Error("Unable to load stock count references");
  const physical = new Map(
    (balances.data ?? []).map((row) => [
      `${row.stock_item_id}:${row.location_id}`,
      row.physical_quantity,
    ]),
  );
  return {
    locations: locations.data ?? [],
    items: (items.data ?? []).flatMap((item) =>
      (locations.data ?? []).map((location) => ({
        ...item,
        location_id: location.id,
        physical_quantity: physical.get(`${item.id}:${location.id}`) ?? 0,
      })),
    ),
  };
}

const listCountsSchema = z.object({
  dateFrom: z.string().date().nullable().default(null),
  dateTo: z.string().date().nullable().default(null),
  status: z.enum(stockCountStatuses).nullable().default(null),
  locationId: uuid.nullable().default(null),
  createdBy: uuid.nullable().default(null),
  limit: z.coerce.number().int().min(1).max(500).default(200),
});

const listAdjustmentsSchema = z.object({
  dateFrom: z.string().date().nullable().default(null),
  dateTo: z.string().date().nullable().default(null),
  status: z.enum(stockAdjustmentStatuses).nullable().default(null),
  type: z.enum(stockAdjustmentTypes).nullable().default(null),
  requestedBy: uuid.nullable().default(null),
  limit: z.coerce.number().int().min(1).max(500).default(200),
});

async function listCounts(
  supabase: ReturnType<typeof getSupabaseServerClient>,
  input: z.infer<typeof listCountsSchema>,
) {
  const { data, error } = await supabase.rpc("list_stock_counts", {
    target_date_from: input.dateFrom,
    target_date_to: input.dateTo,
    target_status: input.status as StockCountStatus | null,
    target_location_id: input.locationId,
    target_created_by: input.createdBy,
    target_limit: input.limit,
  });
  if (error) throw new Error(error.message || "Unable to load stock counts");
  return (data ?? []) as unknown as StockCountListRow[];
}

async function listAdjustments(
  supabase: ReturnType<typeof getSupabaseServerClient>,
  input: z.infer<typeof listAdjustmentsSchema>,
) {
  const { data, error } = await supabase.rpc("list_stock_adjustments", {
    target_date_from: input.dateFrom,
    target_date_to: input.dateTo,
    target_status: input.status,
    target_type: input.type as StockAdjustmentType | null,
    target_requested_by: input.requestedBy,
    target_limit: input.limit,
  });
  if (error) throw new Error(error.message || "Unable to load stock adjustments");
  return (data ?? []) as unknown as StockAdjustmentListRow[];
}

export const getStockCountWorkspaceFn = createServerFn({ method: "GET" }).handler(
  async (): Promise<StockCountWorkspaceData> => {
    const { supabase } = await getClient(allRoles);
    const [reference, counts, adjustments] = await Promise.all([
      loadReferenceData(supabase),
      listCounts(supabase, listCountsSchema.parse({})),
      listAdjustments(supabase, listAdjustmentsSchema.parse({})),
    ]);
    return { ...reference, counts, adjustments };
  },
);

export const getNewStockCountDataFn = createServerFn({ method: "GET" }).handler(
  async (): Promise<NewStockCountData> => {
    const { supabase } = await getClient(allRoles);
    return {
      ...(await loadReferenceData(supabase)),
      today: new Date().toISOString().slice(0, 10),
    };
  },
);

export const listStockCountsFn = createServerFn({ method: "GET" })
  .validator((input: unknown) => listCountsSchema.parse(input ?? {}))
  .handler(async ({ data }) => {
    const { supabase } = await getClient(allRoles);
    return listCounts(supabase, data);
  });

export const listStockAdjustmentsFn = createServerFn({ method: "GET" })
  .validator((input: unknown) => listAdjustmentsSchema.parse(input ?? {}))
  .handler(async ({ data }) => {
    const { supabase } = await getClient(allRoles);
    return listAdjustments(supabase, data);
  });

export const getStockCountFn = createServerFn({ method: "GET" })
  .validator((input: unknown) => z.object({ countId: uuid }).parse(input))
  .handler(async ({ data }): Promise<StockCountDetail> => {
    const { supabase } = await getClient(allRoles);
    const result = await supabase.rpc("get_stock_count", { target_count_id: data.countId });
    if (result.error || !result.data)
      throw new Error(result.error?.message ?? "Unable to load stock count");
    const detail = result.data as unknown as StockCountDetail;
    const attachments = await Promise.all(
      detail.attachments.map(async (attachment) => {
        const signed = await supabase.storage
          .from("facolub-stock-evidence")
          .createSignedUrl(attachment.storage_path, 900);
        return { ...attachment, signed_url: signed.data?.signedUrl ?? null };
      }),
    );
    return { ...detail, attachments };
  });

const createSchema = z.object({
  locationId: nullableUuid,
  countDate: z.string().date(),
  comment: z
    .string()
    .trim()
    .max(2000)
    .transform((value) => value || null),
  category: z.enum(stockCategories).nullable(),
  stockItemIds: z.array(uuid).nullable(),
});

export const createStockCountFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => createSchema.parse(input))
  .handler(async ({ data }) => {
    const { supabase } = await getClient(allRoles);
    const created = await supabase.rpc("create_stock_count_draft", {
      target_location_id: data.locationId,
      target_count_date: data.countDate,
      target_comment: data.comment,
    });
    if (created.error || !created.data)
      throw new Error(created.error?.message ?? "Unable to create stock count");
    const initialized = await supabase.rpc("initialize_stock_count", {
      target_count_id: created.data.id,
      target_category: data.category,
      target_stock_item_ids: data.stockItemIds,
    });
    if (initialized.error)
      throw new Error(initialized.error.message || "Unable to initialize stock count");
    return initialized.data as unknown as StockCountDetail;
  });

export const updateCountedQuantityFn = createServerFn({ method: "POST" })
  .validator((input: unknown) =>
    z
      .object({
        countItemId: uuid,
        quantity: z.coerce.number().min(0).max(999_999_999),
        comment: z
          .string()
          .trim()
          .max(2000)
          .transform((v) => v || null),
      })
      .parse(input),
  )
  .handler(async ({ data }) => {
    const { supabase } = await getClient(allRoles);
    const result = await supabase.rpc("update_counted_quantity", {
      target_count_item_id: data.countItemId,
      target_counted_quantity: data.quantity,
      target_comment: data.comment,
    });
    if (result.error || !result.data)
      throw new Error(result.error?.message ?? "Unable to save counted quantity");
    return result.data;
  });

export const submitStockCountFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => z.object({ countId: uuid }).parse(input))
  .handler(async ({ data }) => {
    const { supabase } = await getClient(allRoles);
    const result = await supabase.rpc("submit_stock_count", { target_count_id: data.countId });
    if (result.error) throw new Error(result.error.message || "Unable to submit stock count");
    return result.data;
  });

export const approveStockCountFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => z.object({ countId: uuid }).parse(input))
  .handler(async ({ data }) => {
    const { supabase } = await getClient(managerRoles);
    const result = await supabase.rpc("approve_stock_count", { target_count_id: data.countId });
    if (result.error) throw new Error(result.error.message || "Unable to approve stock count");
    return result.data;
  });

export const cancelStockCountFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => z.object({ countId: uuid }).parse(input))
  .handler(async ({ data }) => {
    const { supabase } = await getClient(allRoles);
    const result = await supabase.rpc("cancel_stock_count", { target_count_id: data.countId });
    if (result.error) throw new Error(result.error.message || "Unable to cancel stock count");
    return result.data;
  });

export const rejectStockCountFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => z.object({ countId: uuid, reason }).parse(input))
  .handler(async ({ data }) => {
    const { supabase } = await getClient(managerRoles);
    const result = await supabase.rpc("reject_stock_count", {
      target_count_id: data.countId,
      target_reason: data.reason,
    });
    if (result.error) throw new Error(result.error.message || "Unable to reject stock count");
    return result.data;
  });

const adjustmentSchema = z.object({
  stockItemId: uuid,
  locationId: uuid,
  quantity: z.coerce.number().positive().max(999_999_999),
  reason,
});
const otherAdjustmentSchema = adjustmentSchema.extend({
  quantity: z.coerce
    .number()
    .refine((v) => v !== 0 && Math.abs(v) <= 999_999_999, "Quantity cannot be zero"),
});

export const reportStockLossFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => adjustmentSchema.parse(input))
  .handler(async ({ data }) => {
    const { supabase } = await getClient(allRoles);
    const result = await supabase.rpc("report_stock_loss", {
      target_stock_item_id: data.stockItemId,
      target_location_id: data.locationId,
      target_quantity: data.quantity,
      target_reason: data.reason,
    });
    if (result.error || !result.data)
      throw new Error(result.error?.message ?? "Unable to report stock loss");
    return result.data;
  });

export const reportStockDamageFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => adjustmentSchema.parse(input))
  .handler(async ({ data }) => {
    const { supabase } = await getClient(allRoles);
    const result = await supabase.rpc("report_stock_damage", {
      target_stock_item_id: data.stockItemId,
      target_location_id: data.locationId,
      target_quantity: data.quantity,
      target_reason: data.reason,
    });
    if (result.error || !result.data)
      throw new Error(result.error?.message ?? "Unable to report stock damage");
    return result.data;
  });

export const requestOtherStockAdjustmentFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => otherAdjustmentSchema.parse(input))
  .handler(async ({ data }) => {
    const { supabase } = await getClient(allRoles);
    const result = await supabase.rpc("request_other_stock_adjustment", {
      target_stock_item_id: data.stockItemId,
      target_location_id: data.locationId,
      target_signed_quantity: data.quantity,
      target_reason: data.reason,
    });
    if (result.error || !result.data)
      throw new Error(result.error?.message ?? "Unable to request adjustment");
    return result.data;
  });

export const requestStockCorrectionFn = createServerFn({ method: "POST" })
  .validator((input: unknown) =>
    z
      .object({ movementId: uuid, quantity: z.coerce.number().positive().max(999_999_999), reason })
      .parse(input),
  )
  .handler(async ({ data }) => {
    const { supabase } = await getClient(allRoles);
    const result = await supabase.rpc("request_stock_correction", {
      target_movement_id: data.movementId,
      target_quantity: data.quantity,
      target_reason: data.reason,
    });
    if (result.error || !result.data)
      throw new Error(result.error?.message ?? "Unable to request correction");
    return result.data;
  });

export const approveStockAdjustmentFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => z.object({ adjustmentId: uuid }).parse(input))
  .handler(async ({ data }) => {
    const { supabase } = await getClient(managerRoles);
    const result = await supabase.rpc("approve_stock_adjustment", {
      target_adjustment_id: data.adjustmentId,
    });
    if (result.error) throw new Error(result.error.message || "Unable to approve adjustment");
    return result.data;
  });

export const rejectStockAdjustmentFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => z.object({ adjustmentId: uuid, reason }).parse(input))
  .handler(async ({ data }) => {
    const { supabase } = await getClient(managerRoles);
    const result = await supabase.rpc("reject_stock_adjustment", {
      target_adjustment_id: data.adjustmentId,
      target_reason: data.reason,
    });
    if (result.error) throw new Error(result.error.message || "Unable to reject adjustment");
    return result.data;
  });

export const attachStockCountEvidenceFn = createServerFn({ method: "POST" })
  .validator((input: unknown) =>
    z
      .object({
        countId: uuid,
        countItemId: uuid.nullable(),
        storagePath: z.string().min(1).max(500),
        fileName: z.string().min(1).max(255),
        mimeType: z.enum(["image/jpeg", "image/png", "image/webp", "application/pdf"]),
        fileSize: z
          .number()
          .int()
          .positive()
          .max(10 * 1024 * 1024),
      })
      .parse(input),
  )
  .handler(async ({ data }) => {
    const { supabase } = await getClient(allRoles);
    const result = await supabase.rpc("attach_stock_count_evidence", {
      target_count_id: data.countId,
      target_count_item_id: data.countItemId,
      target_storage_path: data.storagePath,
      target_file_name: data.fileName,
      target_mime_type: data.mimeType,
      target_file_size: data.fileSize,
    });
    if (result.error || !result.data)
      throw new Error(result.error?.message ?? "Unable to attach evidence");
    return result.data;
  });

export const attachStockAdjustmentEvidenceFn = createServerFn({ method: "POST" })
  .validator((input: unknown) =>
    z
      .object({
        adjustmentId: uuid,
        storagePath: z.string().min(1).max(500),
        fileName: z.string().min(1).max(255),
        mimeType: z.enum(["image/jpeg", "image/png", "image/webp", "application/pdf"]),
        fileSize: z
          .number()
          .int()
          .positive()
          .max(10 * 1024 * 1024),
      })
      .parse(input),
  )
  .handler(async ({ data }) => {
    const { supabase } = await getClient(allRoles);
    const result = await supabase.rpc("attach_stock_adjustment_evidence", {
      target_adjustment_id: data.adjustmentId,
      target_storage_path: data.storagePath,
      target_file_name: data.fileName,
      target_mime_type: data.mimeType,
      target_file_size: data.fileSize,
    });
    if (result.error || !result.data)
      throw new Error(result.error?.message ?? "Unable to attach evidence");
    return result.data;
  });

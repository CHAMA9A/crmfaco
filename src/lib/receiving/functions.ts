import { createServerFn } from "@tanstack/react-start";
import { setResponseHeader } from "@tanstack/react-start/server";
import { z } from "zod";

import { getSupabaseServerClient } from "@/lib/supabase/server";
import type {
  AppRole,
  Json,
  ReceiptAttachment,
  ReceiptListRow,
  ReceiptStatus,
} from "@/types/database";
import { receiptStatuses } from "./types";
import type {
  ReceiptConfirmation,
  ReceiptDetail,
  ReceiptEditorData,
  ReceivingHistoryData,
  ReceivingHomeData,
  SupplierAdminData,
} from "./types";

const allRoles: AppRole[] = ["admin", "management", "factory"];
const nullableText = (max: number) =>
  z
    .string()
    .trim()
    .max(max)
    .transform((value) => value || null);
const nullableUuid = z
  .union([z.literal(""), z.string().uuid()])
  .transform((value) => value || null);

const receiptIdSchema = z.object({ receiptId: z.string().uuid() });
const editorSchema = z.object({ receiptId: z.string().uuid().nullable().default(null) });
const receiptDraftSchema = z.object({
  receiptDate: z.string().date(),
  locationId: nullableUuid,
  supplierId: nullableUuid,
  supplierName: nullableText(200),
  reference: nullableText(200),
  comment: nullableText(2000),
});
const updateReceiptSchema = receiptDraftSchema.extend({ receiptId: z.string().uuid() });
const receiptItemSchema = z.object({
  receiptId: z.string().uuid(),
  stockItemId: z.string().uuid(),
  quantity: z.coerce.number().positive().max(999_999_999),
  position: z.coerce.number().int().positive().max(100),
});
const removeItemSchema = z.object({ receiptItemId: z.string().uuid() });
const attachmentSchema = z.object({
  receiptId: z.string().uuid(),
  storagePath: z.string().trim().min(38).max(1000),
  fileName: z.string().trim().min(1).max(255),
  mimeType: z.enum(["image/jpeg", "image/png", "image/webp", "image/heic", "image/heif"]),
  fileSize: z.coerce
    .number()
    .int()
    .positive()
    .max(8 * 1024 * 1024),
});
const attachmentIdSchema = z.object({ attachmentId: z.string().uuid() });
const supplierSchema = z.object({
  id: nullableUuid,
  name: z.string().trim().min(1).max(200),
  phone: nullableText(80),
  email: z
    .union([z.literal(""), z.string().trim().email().max(320)])
    .transform((value) => value || null),
  address: nullableText(1000),
  isActive: z.boolean(),
});
const receiptFiltersSchema = z.object({
  dateFrom: z.string().date().nullable().default(null),
  dateTo: z.string().date().nullable().default(null),
  supplierId: z.string().uuid().nullable().default(null),
  stockItemId: z.string().uuid().nullable().default(null),
  createdBy: z.string().uuid().nullable().default(null),
  status: z.enum(receiptStatuses).nullable().default(null),
  search: z.string().trim().max(200).nullable().default(null),
  limit: z.coerce.number().int().min(1).max(500).default(200),
});

function privateResponse() {
  setResponseHeader("Cache-Control", "private, no-store");
  setResponseHeader("Vary", "Cookie, Authorization");
}

async function getReceivingClient(roles: readonly AppRole[] = allRoles) {
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

async function listReceipts(
  supabase: Awaited<ReturnType<typeof getReceivingClient>>,
  filters: z.infer<typeof receiptFiltersSchema>,
) {
  const { data, error } = await supabase.rpc("list_receipts", {
    target_date_from: filters.dateFrom,
    target_date_to: filters.dateTo,
    target_supplier_id: filters.supplierId,
    target_stock_item_id: filters.stockItemId,
    target_created_by: filters.createdBy,
    target_status: filters.status as ReceiptStatus | null,
    target_search: filters.search,
    target_limit: filters.limit,
  });
  if (error) throw new Error(error.message || "Unable to load receipts");
  return (data ?? []) as ReceiptListRow[];
}

async function loadReceiptDetail(
  supabase: Awaited<ReturnType<typeof getReceivingClient>>,
  receiptId: string,
) {
  const { data, error } = await supabase.rpc("get_receipt", { target_receipt_id: receiptId });
  if (error || !data) throw new Error(error?.message ?? "Receipt not found");
  const detail = data as unknown as Omit<ReceiptDetail, "attachments"> & {
    attachments: ReceiptAttachment[];
  };
  const paths = detail.attachments.map((attachment) => attachment.storage_path);
  if (!paths.length) return { ...detail, attachments: [] } satisfies ReceiptDetail;

  const signed = await supabase.storage.from("facolub-receipts").createSignedUrls(paths, 10 * 60);
  const urls = new Map(
    (signed.data ?? []).map((item, index) => [paths[index], item.signedUrl ?? null]),
  );
  return {
    ...detail,
    attachments: detail.attachments.map((attachment) => ({
      ...attachment,
      signed_url: urls.get(attachment.storage_path) ?? null,
    })),
  } satisfies ReceiptDetail;
}

export const getReceivingHomeFn = createServerFn({ method: "GET" }).handler(
  async (): Promise<ReceivingHomeData> => {
    const supabase = await getReceivingClient();
    return {
      rows: await listReceipts(supabase, {
        dateFrom: null,
        dateTo: null,
        supplierId: null,
        stockItemId: null,
        createdBy: null,
        status: null,
        search: null,
        limit: 12,
      }),
    };
  },
);

export const getReceivingHistoryFn = createServerFn({ method: "GET" }).handler(
  async (): Promise<ReceivingHistoryData> => {
    const supabase = await getReceivingClient();
    const [rows, suppliersResult, itemsResult] = await Promise.all([
      listReceipts(supabase, {
        dateFrom: null,
        dateTo: null,
        supplierId: null,
        stockItemId: null,
        createdBy: null,
        status: null,
        search: null,
        limit: 250,
      }),
      supabase.from("suppliers").select("*").order("name"),
      supabase.from("stock_items").select("id, name").eq("is_active", true).order("name"),
    ]);
    if (suppliersResult.error || itemsResult.error) {
      throw new Error("Unable to load receiving filters");
    }
    const users = new Map(rows.map((row) => [row.created_by, row.created_by_name]));
    return {
      rows,
      suppliers: suppliersResult.data ?? [],
      stockItems: itemsResult.data ?? [],
      users: [...users].map(([id, display_name]) => ({ id, display_name })),
    };
  },
);

export const searchReceiptsFn = createServerFn({ method: "GET" })
  .validator((input: unknown) => receiptFiltersSchema.parse(input ?? {}))
  .handler(async ({ data }) => {
    const supabase = await getReceivingClient();
    return listReceipts(supabase, data);
  });

export const getReceiptDetailFn = createServerFn({ method: "GET" })
  .validator((input: unknown) => receiptIdSchema.parse(input))
  .handler(async ({ data }): Promise<ReceiptDetail> => {
    const supabase = await getReceivingClient();
    return loadReceiptDetail(supabase, data.receiptId);
  });

export const getReceiptEditorDataFn = createServerFn({ method: "GET" })
  .validator((input: unknown) => editorSchema.parse(input ?? {}))
  .handler(async ({ data }): Promise<ReceiptEditorData> => {
    const supabase = await getReceivingClient();
    const [itemsResult, locationsResult, balancesResult, suppliersResult, receipt] =
      await Promise.all([
        supabase.from("stock_items").select("*").eq("is_active", true).order("name"),
        supabase.from("stock_locations").select("*").eq("is_active", true).order("name"),
        supabase.from("stock_balances").select("*"),
        supabase.from("suppliers").select("*").eq("is_active", true).order("name"),
        data.receiptId ? loadReceiptDetail(supabase, data.receiptId) : Promise.resolve(null),
      ]);
    if (
      itemsResult.error ||
      locationsResult.error ||
      balancesResult.error ||
      suppliersResult.error
    ) {
      throw new Error("Unable to load receiving form data");
    }
    if (receipt && receipt.receipt.status !== "draft") {
      throw new Error("Only a draft receipt can be edited");
    }
    const balances = new Map(
      (balancesResult.data ?? []).map((balance) => [
        `${balance.stock_item_id}:${balance.location_id}`,
        balance,
      ]),
    );
    const locations = locationsResult.data ?? [];
    return {
      today: new Date().toISOString().slice(0, 10),
      receipt,
      locations,
      suppliers: suppliersResult.data ?? [],
      stockItems: (itemsResult.data ?? []).flatMap((item) =>
        locations.map((location) => {
          const balance = balances.get(`${item.id}:${location.id}`);
          return {
            ...item,
            location_id: location.id,
            physical_quantity: balance?.physical_quantity ?? 0,
            reserved_quantity: balance?.reserved_quantity ?? 0,
            available_quantity: balance?.available_quantity ?? 0,
          };
        }),
      ),
    };
  });

export const createReceiptDraftFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => receiptDraftSchema.parse(input))
  .handler(async ({ data }) => {
    const supabase = await getReceivingClient();
    const { data: receipt, error } = await supabase.rpc("create_receipt_draft", {
      target_receipt_date: data.receiptDate,
      target_location_id: data.locationId,
      target_supplier_id: data.supplierId,
      target_supplier_name: data.supplierName,
      target_reference: data.reference,
      target_comment: data.comment,
    });
    if (error || !receipt) throw new Error(error?.message ?? "Unable to create receipt draft");
    return receipt;
  });

export const updateReceiptDraftFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => updateReceiptSchema.parse(input))
  .handler(async ({ data }) => {
    const supabase = await getReceivingClient();
    const { data: receipt, error } = await supabase.rpc("update_receipt_draft", {
      target_receipt_id: data.receiptId,
      target_receipt_date: data.receiptDate,
      target_location_id: data.locationId,
      target_supplier_id: data.supplierId,
      target_supplier_name: data.supplierName,
      target_reference: data.reference,
      target_comment: data.comment,
    });
    if (error || !receipt) throw new Error(error?.message ?? "Unable to update receipt draft");
    return receipt;
  });

export const addReceiptItemFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => receiptItemSchema.parse(input))
  .handler(async ({ data }) => {
    const supabase = await getReceivingClient();
    const { data: item, error } = await supabase.rpc("add_receipt_item", {
      target_receipt_id: data.receiptId,
      target_stock_item_id: data.stockItemId,
      target_quantity: data.quantity,
      target_position: data.position,
    });
    if (error || !item) throw new Error(error?.message ?? "Unable to save receipt item");
    return item;
  });

export const removeReceiptItemFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => removeItemSchema.parse(input))
  .handler(async ({ data }) => {
    const supabase = await getReceivingClient();
    const { error } = await supabase.rpc("remove_receipt_item", {
      target_receipt_item_id: data.receiptItemId,
    });
    if (error) throw new Error(error.message || "Unable to remove receipt item");
    return { removed: true };
  });

export const attachReceiptPhotoFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => attachmentSchema.parse(input))
  .handler(async ({ data }) => {
    const supabase = await getReceivingClient();
    const { data: attachment, error } = await supabase.rpc("attach_receipt_photo", {
      target_receipt_id: data.receiptId,
      target_storage_path: data.storagePath,
      target_file_name: data.fileName,
      target_mime_type: data.mimeType,
      target_file_size: data.fileSize,
    });
    if (error || !attachment) throw new Error(error?.message ?? "Unable to attach receipt photo");
    return attachment;
  });

export const detachReceiptPhotoFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => attachmentIdSchema.parse(input))
  .handler(async ({ data }) => {
    const supabase = await getReceivingClient();
    const { data: storagePath, error } = await supabase.rpc("detach_receipt_photo", {
      target_attachment_id: data.attachmentId,
    });
    if (error || !storagePath) throw new Error(error?.message ?? "Unable to detach receipt photo");
    return { storagePath };
  });

export const cancelReceiptFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => receiptIdSchema.parse(input))
  .handler(async ({ data }) => {
    const supabase = await getReceivingClient();
    const { data: receipt, error } = await supabase.rpc("cancel_receipt", {
      target_receipt_id: data.receiptId,
    });
    if (error || !receipt) throw new Error(error?.message ?? "Unable to cancel receipt");
    return receipt;
  });

export const confirmReceiptFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => receiptIdSchema.parse(input))
  .handler(async ({ data }) => {
    const supabase = await getReceivingClient();
    const { data: result, error } = await supabase.rpc("confirm_receipt", {
      target_receipt_id: data.receiptId,
    });
    if (error || !result) throw new Error(error?.message ?? "Unable to confirm receipt");
    return result as Json as unknown as ReceiptConfirmation;
  });

export const getSuppliersForAdminFn = createServerFn({ method: "GET" }).handler(
  async (): Promise<SupplierAdminData> => {
    const supabase = await getReceivingClient(["admin"]);
    const { data, error } = await supabase.from("suppliers").select("*").order("name");
    if (error) throw new Error(error.message || "Unable to load suppliers");
    return { suppliers: data ?? [] };
  },
);

export const saveSupplierFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => supplierSchema.parse(input))
  .handler(async ({ data }) => {
    const supabase = await getReceivingClient(["admin"]);
    const { data: supplier, error } = await supabase.rpc("save_supplier", {
      target_id: data.id,
      target_name: data.name,
      target_phone: data.phone,
      target_email: data.email,
      target_address: data.address,
      target_is_active: data.isActive,
    });
    if (error || !supplier) throw new Error(error?.message ?? "Unable to save supplier");
    return supplier;
  });

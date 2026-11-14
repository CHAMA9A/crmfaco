import { createServerFn } from "@tanstack/react-start";
import { setResponseHeader } from "@tanstack/react-start/server";
import { z } from "zod";
import { getSupabaseServerClient } from "@/lib/supabase/server";
import type { Json } from "@/types/database";
import type {
  DispatchDetail,
  DispatchHistoryRow,
  DispatchMission,
  DispatchRemainingLine,
} from "./types";

const idSchema = z.object({ dispatchId: z.string().uuid() });
const createSchema = z.object({ orderId: z.string().uuid(), locationId: z.string().uuid() });
const saveSchema = z.object({
  dispatchId: z.string().uuid(),
  vehicleDescription: z.string().trim().max(200),
  vehicleRegistration: z.string().trim().max(100),
  driverName: z.string().trim().max(200),
  driverPhone: z.string().trim().max(100),
  transportCompany: z.string().trim().max(200),
  notes: z.string().trim().max(2000),
  items: z
    .array(
      z.object({ order_item_id: z.string().uuid(), quantity_loaded: z.coerce.number().positive() }),
    )
    .min(1),
});
const photoSchema = z.object({
  dispatchId: z.string().uuid(),
  category: z.enum(["goods", "vehicle", "registration", "other"]),
  storagePath: z.string().min(38).max(1000),
  fileName: z.string().max(200),
  mimeType: z.string().max(100),
  fileSize: z
    .number()
    .int()
    .positive()
    .max(8 * 1024 * 1024),
});

function privateResponse() {
  setResponseHeader("Cache-Control", "private, no-store");
  setResponseHeader("Vary", "Cookie, Authorization");
}
async function getDispatchClient() {
  privateResponse();
  const supabase = getSupabaseServerClient();
  const { data: user, error } = await supabase.auth.getUser();
  if (error || !user.user) throw new Error("Unauthorized");
  const [{ data: profile }, { data: access }] = await Promise.all([
    supabase.from("profiles").select("role,is_active").eq("id", user.user.id).single(),
    supabase.rpc("has_environment_access", { environment_code: "FACOLUB" }),
  ]);
  if (!profile?.is_active || !access) throw new Error("Forbidden");
  return { supabase, profile };
}

export const getDispatchMissionsFn = createServerFn({ method: "GET" }).handler(async () => {
  const { supabase } = await getDispatchClient();
  const [{ data, error }, { data: locations, error: locationError }] = await Promise.all([
    supabase.rpc("get_factory_dispatch_missions"),
    supabase.from("stock_locations").select("id,name").eq("is_active", true).order("name"),
  ]);
  if (error || locationError) throw new Error(error?.message ?? "Unable to load dispatch missions");
  return { missions: (data ?? []) as unknown as DispatchMission[], locations: locations ?? [] };
});

export const createDispatchDraftFn = createServerFn({ method: "POST" })
  .validator((x: unknown) => createSchema.parse(x))
  .handler(async ({ data }) => {
    const { supabase } = await getDispatchClient();
    const { data: dispatch, error } = await supabase.rpc("create_dispatch_draft", {
      target_order_id: data.orderId,
      target_location_id: data.locationId,
      target_destination_type: "customer",
      target_destination_name: null,
      target_delivery_address: null,
      target_delivery_city: null,
      target_delivery_contact: null,
    });
    if (error || !dispatch) throw new Error(error?.message ?? "Unable to start loading");
    return dispatch;
  });

export const getDispatchDetailFn = createServerFn({ method: "GET" })
  .validator((x: unknown) => idSchema.parse(x))
  .handler(async ({ data }): Promise<DispatchDetail> => {
    const { supabase } = await getDispatchClient();
    const { data: raw, error } = await supabase.rpc("get_dispatch_detail", {
      target_dispatch_id: data.dispatchId,
    });
    if (error || !raw) throw new Error(error?.message ?? "Dispatch not found");
    const detail = raw as unknown as Omit<DispatchDetail, "remaining">;
    let remaining: DispatchRemainingLine[] = [];
    if (detail.dispatch.order_id) {
      const result = await supabase.rpc("get_order_dispatch_remaining", {
        target_order_id: detail.dispatch.order_id,
      });
      if (result.error) throw new Error(result.error.message);
      remaining = (result.data ?? []) as DispatchRemainingLine[];
    }
    const attachments = await Promise.all(
      detail.attachments.map(async (a) => {
        const signed = await supabase.storage
          .from("facolub-dispatch")
          .createSignedUrl(a.storage_path, 600);
        return { ...a, signed_url: signed.data?.signedUrl ?? null };
      }),
    );
    return { ...detail, attachments, remaining };
  });

export const saveDispatchDraftFn = createServerFn({ method: "POST" })
  .validator((x: unknown) => saveSchema.parse(x))
  .handler(async ({ data }) => {
    const { supabase } = await getDispatchClient();
    const update = await supabase.rpc("update_dispatch_draft", {
      target_dispatch_id: data.dispatchId,
      target_vehicle_description: data.vehicleDescription || null,
      target_vehicle_registration: data.vehicleRegistration || null,
      target_driver_name: data.driverName || null,
      target_driver_phone: data.driverPhone || null,
      target_transport_company: data.transportCompany || null,
      target_notes: data.notes || null,
    });
    if (update.error) throw new Error(update.error.message);
    const items = await supabase.rpc("replace_dispatch_items", {
      target_dispatch_id: data.dispatchId,
      target_items: data.items as unknown as Json,
    });
    if (items.error) throw new Error(items.error.message);
    return update.data;
  });

export const attachDispatchPhotoFn = createServerFn({ method: "POST" })
  .validator((x: unknown) => photoSchema.parse(x))
  .handler(async ({ data }) => {
    const { supabase } = await getDispatchClient();
    const result = await supabase.rpc("attach_dispatch_photo", {
      target_dispatch_id: data.dispatchId,
      target_category: data.category,
      target_storage_path: data.storagePath,
      target_file_name: data.fileName,
      target_mime_type: data.mimeType,
      target_file_size: data.fileSize,
    });
    if (result.error) throw new Error(result.error.message);
    return result.data;
  });

export const confirmDispatchFn = createServerFn({ method: "POST" })
  .validator((x: unknown) => idSchema.parse(x))
  .handler(async ({ data }) => {
    const { supabase } = await getDispatchClient();
    const result = await supabase.rpc("confirm_dispatch", { target_dispatch_id: data.dispatchId });
    if (result.error) throw new Error(result.error.message);
    return result.data;
  });

export const prepareDispatchDocumentsFn = createServerFn({ method: "POST" })
  .validator((x: unknown) => idSchema.parse(x))
  .handler(async ({ data }) => {
    const { supabase, profile } = await getDispatchClient();
    if (profile.role === "factory") throw new Error("Forbidden");
    const result = await supabase.rpc("prepare_dispatch_documents", {
      target_dispatch_id: data.dispatchId,
    });
    if (result.error) throw new Error(result.error.message);
    return result.data;
  });

export const getDispatchHistoryFn = createServerFn({ method: "GET" }).handler(async () => {
  const { supabase } = await getDispatchClient();
  const { data, error } = await supabase
    .from("dispatches")
    .select(
      "id,dispatch_number,dispatch_date,order_id,destination_name,vehicle_registration,confirmed_at,created_by,status",
    )
    .order("created_at", { ascending: false })
    .limit(200);
  if (error) throw new Error("Unable to load dispatch history");
  const ids = (data ?? []).map((x) => x.id);
  const users = [...new Set((data ?? []).map((x) => x.created_by))];
  const [items, profiles] = await Promise.all([
    supabase.from("dispatch_items").select("dispatch_id,quantity_loaded").in("dispatch_id", ids),
    supabase.from("profiles").select("id,display_name").in("id", users),
  ]);
  const totals = new Map<string, number>();
  for (const item of items.data ?? [])
    totals.set(
      item.dispatch_id,
      (totals.get(item.dispatch_id) ?? 0) + Number(item.quantity_loaded),
    );
  const names = new Map((profiles.data ?? []).map((p) => [p.id, p.display_name]));
  return (data ?? []).map((row) => ({
    ...row,
    total_loaded: totals.get(row.id) ?? 0,
    employee_name: names.get(row.created_by) ?? "—",
  })) as DispatchHistoryRow[];
});

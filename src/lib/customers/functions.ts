import { createServerFn } from "@tanstack/react-start";
import { setResponseHeader } from "@tanstack/react-start/server";
import { z } from "zod";
import { getSupabaseServerClient } from "@/lib/supabase/server";
import type { Customer, CustomerPriceCategory, Json } from "@/types/database";
import type {
  CustomerDetailData,
  CustomerDuplicate,
  CustomerHistory,
  CustomerListRow,
} from "./types";
import { customerInputSchema, customerPayload } from "./validation";

const customerIdSchema = z.object({ customerId: z.string().uuid() });
const filtersSchema = z.object({
  search: z.string().trim().max(200).nullable().default(null),
  active: z.boolean().nullable().default(null),
  city: z.string().trim().max(120).nullable().default(null),
  priceCategory: z.enum(["intercompany", "wholesale", "retail", "custom"]).nullable().default(null),
});
const duplicateSchema = z.object({
  customerId: z.string().uuid().nullable().default(null),
  companyName: z.string().trim().max(200).nullable().default(null),
  ice: z.string().trim().max(80).nullable().default(null),
  email: z.string().trim().max(320).nullable().default(null),
  phone: z.string().trim().max(80).nullable().default(null),
});
const noteSchema = customerIdSchema.extend({ note: z.string().trim().min(1).max(4000) });

function privateResponse() {
  setResponseHeader("Cache-Control", "private, no-store");
  setResponseHeader("Vary", "Cookie, Authorization");
}

async function getCustomerClient() {
  privateResponse();
  const supabase = getSupabaseServerClient();
  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData.user) throw new Error("Unauthorized");
  const [{ data: profile, error: profileError }, access] = await Promise.all([
    supabase.from("profiles").select("role, is_active").eq("id", userData.user.id).maybeSingle(),
    supabase.rpc("has_environment_access", { environment_code: "FACOLUB" }),
  ]);
  if (profileError || access.error) throw new Error("Unable to verify FACOLUB access");
  if (!profile?.is_active || profile.role === "factory" || !access.data)
    throw new Error("Forbidden");
  return supabase;
}

async function listCustomers(filters: z.infer<typeof filtersSchema>): Promise<CustomerListRow[]> {
  const supabase = await getCustomerClient();
  const { data, error } = await supabase.rpc("list_customers", {
    target_search: filters.search,
    target_active: filters.active,
    target_city: filters.city,
    target_price_category: filters.priceCategory as CustomerPriceCategory | null,
    target_limit: 300,
  });
  if (error) throw new Error(error.message || "Unable to load customers");
  return (data ?? []) as CustomerListRow[];
}

export const getCustomersFn = createServerFn({ method: "GET" }).handler(async () => {
  const rows = await listCustomers({ search: null, active: null, city: null, priceCategory: null });
  return { rows, cities: [...new Set(rows.map((row) => row.city).filter(Boolean))] as string[] };
});

export const searchCustomersFn = createServerFn({ method: "GET" })
  .validator((input: unknown) => filtersSchema.parse(input ?? {}))
  .handler(async ({ data }) => listCustomers(data));

export const getCustomerFn = createServerFn({ method: "GET" })
  .validator((input: unknown) => customerIdSchema.parse(input))
  .handler(async ({ data }): Promise<CustomerDetailData> => {
    const supabase = await getCustomerClient();
    const [customerResult, notesResult, pricesResult, historyResult] = await Promise.all([
      supabase.from("customers").select("*").eq("id", data.customerId).maybeSingle(),
      supabase
        .from("customer_notes")
        .select("*")
        .eq("customer_id", data.customerId)
        .order("created_at", { ascending: false }),
      supabase
        .from("customer_product_prices")
        .select("id", { count: "exact", head: true })
        .eq("customer_id", data.customerId)
        .eq("is_active", true),
      supabase.rpc("get_customer_document_history", { target_customer_id: data.customerId }),
    ]);
    if (customerResult.error || !customerResult.data) throw new Error("Customer not found");
    if (notesResult.error || pricesResult.error || historyResult.error) {
      throw new Error("Unable to load customer details");
    }
    return {
      customer: customerResult.data as Customer,
      notes: notesResult.data ?? [],
      customPriceCount: pricesResult.count ?? 0,
      history: historyResult.data as Json as unknown as CustomerHistory,
    };
  });

export const saveCustomerFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => customerInputSchema.parse(input))
  .handler(async ({ data }) => {
    const supabase = await getCustomerClient();
    const { data: customer, error } = await supabase.rpc("save_customer", {
      target_customer_id: data.customerId,
      target_payload: customerPayload(data) as Json,
    });
    if (error || !customer) throw new Error(error?.message ?? "Unable to save customer");
    return customer;
  });

export const getCustomerPossibleDuplicatesFn = createServerFn({ method: "GET" })
  .validator((input: unknown) => duplicateSchema.parse(input ?? {}))
  .handler(async ({ data }): Promise<CustomerDuplicate[]> => {
    const supabase = await getCustomerClient();
    const { data: matches, error } = await supabase.rpc("get_customer_possible_duplicates", {
      target_company_name: data.companyName,
      target_ice: data.ice,
      target_email: data.email,
      target_phone: data.phone,
      target_exclude_customer_id: data.customerId,
    });
    if (error) throw new Error(error.message || "Unable to check duplicates");
    return (matches ?? []) as CustomerDuplicate[];
  });

export const deactivateCustomerFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => customerIdSchema.parse(input))
  .handler(async ({ data }) => {
    const supabase = await getCustomerClient();
    const { data: customer, error } = await supabase.rpc("deactivate_customer", {
      target_customer_id: data.customerId,
    });
    if (error || !customer) throw new Error(error?.message ?? "Unable to deactivate customer");
    return customer;
  });

export const addCustomerNoteFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => noteSchema.parse(input))
  .handler(async ({ data }) => {
    const supabase = await getCustomerClient();
    const { data: note, error } = await supabase.rpc("add_customer_note", {
      target_customer_id: data.customerId,
      target_note: data.note,
    });
    if (error || !note) throw new Error(error?.message ?? "Unable to add note");
    return note;
  });

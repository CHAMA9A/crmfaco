import { createServerFn } from "@tanstack/react-start";
import { setResponseHeader } from "@tanstack/react-start/server";
import { z } from "zod";

import { getSupabaseServerClient } from "@/lib/supabase/server";
import type { InvoiceDocument, InvoiceItem, InvoiceStatus, InvoiceWorkspaceData } from "./types";

const invoiceRequestSchema = z.object({ invoiceId: z.string().uuid() });
const customerSchema = z.object({
  companyName: z.string().trim().min(1).max(200),
  contactPerson: z.string().trim().max(200),
  phone: z.string().trim().max(50),
  email: z.union([z.literal(""), z.string().trim().email().max(254)]),
  city: z.string().trim().max(120),
  address: z.string().trim().max(500),
  ice: z.string().trim().max(100),
  purchaseOrderDefault: z.string().trim().max(200),
});
const invoiceDraftSchema = z.object({
  customerId: z.string().uuid(),
  invoiceDate: z.string().date(),
  purchaseOrder: z.string().trim().max(200),
  items: z
    .array(
      z.object({
        description: z.string().trim().min(1).max(500),
        quantity: z.coerce.number().positive().max(999_999_999),
        unitPrice: z.coerce.number().nonnegative().max(999_999_999),
      }),
    )
    .min(1)
    .max(100),
});

function privateInvoiceResponse() {
  setResponseHeader("Cache-Control", "private, no-store");
  setResponseHeader("Vary", "Cookie, Authorization");
}

async function getInvoiceManagerClient() {
  privateInvoiceResponse();
  const supabase = getSupabaseServerClient();
  const { data: userData } = await supabase.auth.getUser();
  if (!userData.user) throw new Error("Unauthorized");

  const { data: profile } = await supabase
    .from("profiles")
    .select("role, is_active")
    .eq("id", userData.user.id)
    .maybeSingle();
  if (!profile?.is_active || profile.role === "factory") throw new Error("Forbidden");
  return supabase;
}

export const getInvoiceWorkspaceFn = createServerFn({ method: "GET" }).handler(
  async (): Promise<InvoiceWorkspaceData> => {
    const supabase = await getInvoiceManagerClient();
    const [
      { data: customers, error: customerError },
      { data: invoices, error: invoiceError },
      { data: taxSettings, error: taxSettingsError },
    ] = await Promise.all([
      supabase
        .from("customers")
        .select("id, company_name, city, address, ice, purchase_order_default")
        .eq("is_active", true)
        .not("company_name", "like", "[TEST]%")
        .order("company_name"),
      supabase
        .from("invoices")
        .select(
          "id, invoice_number, invoice_date, customer_name_snapshot, purchase_order, status, total, total_ttc, created_at",
        )
        .not("purchase_order", "like", "TEST-%")
        .order("created_at", { ascending: false })
        .limit(50),
      supabase
        .from("invoice_tax_settings")
        .select("default_tax_rate")
        .eq("singleton", true)
        .maybeSingle(),
    ]);

    if (customerError || invoiceError || taxSettingsError)
      throw new Error("Unable to load invoices");
    return {
      customers: customers ?? [],
      invoices: (invoices ?? []).map((invoice) => ({
        ...invoice,
        status: invoice.status as InvoiceStatus,
      })),
      today: new Date().toISOString().slice(0, 10),
      defaultTaxRate: taxSettings?.default_tax_rate ?? null,
    };
  },
);

export const createCustomerFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => customerSchema.parse(input))
  .handler(async ({ data }) => {
    const supabase = await getInvoiceManagerClient();
    const emptyToNull = (value: string) => value || null;
    const { data: duplicates, error: duplicateError } = await supabase.rpc(
      "get_customer_possible_duplicates",
      {
        target_company_name: data.companyName,
        target_ice: emptyToNull(data.ice),
        target_email: emptyToNull(data.email),
        target_phone: emptyToNull(data.phone),
        target_exclude_customer_id: null,
      },
    );
    if (duplicateError) throw new Error("Unable to check customer duplicates");
    if (duplicates?.length) {
      throw new Error("Possible duplicate customer. Verify or create it from the Customers CRM.");
    }

    const { data: customer, error } = await supabase.rpc("save_customer", {
      target_customer_id: null,
      target_payload: {
        company_name: data.companyName,
        contact_person: emptyToNull(data.contactPerson),
        phone: emptyToNull(data.phone),
        email: emptyToNull(data.email),
        city: emptyToNull(data.city),
        address_line1: emptyToNull(data.address),
        ice: emptyToNull(data.ice),
        purchase_order_default: emptyToNull(data.purchaseOrderDefault),
      },
    });

    if (error || !customer) throw new Error("Unable to create customer");
    return {
      id: customer.id,
      company_name: customer.company_name,
      city: customer.city,
      address: customer.address,
      ice: customer.ice,
      purchase_order_default: customer.purchase_order_default,
    };
  });

export const createInvoiceDraftFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => invoiceDraftSchema.parse(input))
  .handler(async ({ data }) => {
    const supabase = await getInvoiceManagerClient();
    const { data: invoice, error } = await supabase.rpc("create_invoice_draft", {
      target_customer_id: data.customerId,
      target_invoice_date: data.invoiceDate,
      target_purchase_order: data.purchaseOrder || null,
      target_items: data.items.map((item) => ({
        description: item.description,
        quantity: item.quantity,
        unit_price: item.unitPrice,
      })),
    });

    if (error || !invoice) throw new Error("Unable to create invoice");
    return invoice;
  });

export const issueInvoiceFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => invoiceRequestSchema.parse(input))
  .handler(async ({ data }) => {
    const supabase = await getInvoiceManagerClient();
    const { data: invoice, error } = await supabase.rpc("issue_invoice", {
      target_invoice_id: data.invoiceId,
    });
    if (error || !invoice) throw new Error("Unable to issue invoice");
    return invoice;
  });

export const getInvoiceDocumentFn = createServerFn({ method: "GET" })
  .validator((input: unknown) => invoiceRequestSchema.parse(input))
  .handler(async ({ data }): Promise<InvoiceDocument> => {
    const supabase = await getInvoiceManagerClient();

    const [
      { data: invoice, error: invoiceError },
      { data: items, error: itemsError },
      { data: total, error: totalError },
    ] = await Promise.all([
      supabase
        .from("invoices")
        .select(
          "id, order_id, invoice_number, invoice_date, purchase_order, customer_name_snapshot, customer_city_snapshot, customer_address_snapshot, customer_ice_snapshot, customer_if_snapshot, customer_rc_snapshot, status, currency, subtotal_ht, tax_rate, tax_total, total_ttc, prices_confirmed_at",
        )
        .eq("id", data.invoiceId)
        .single(),
      supabase
        .from("invoice_items")
        .select("id, order_item_id, description, quantity, unit_price, line_total, position")
        .eq("invoice_id", data.invoiceId)
        .order("position", { ascending: true }),
      supabase.rpc("invoice_authoritative_total", { target_invoice_id: data.invoiceId }),
    ]);

    if (invoiceError || !invoice) throw new Error("Invoice not found");
    if (itemsError || totalError) throw new Error("Unable to calculate invoice total");

    return {
      ...invoice,
      status: invoice.status as InvoiceStatus,
      subtotal_ht: String(invoice.subtotal_ht),
      tax_rate: invoice.tax_rate === null ? null : String(invoice.tax_rate),
      tax_total: String(invoice.tax_total),
      total_ttc: String(invoice.total_ttc),
      authoritative_total: String(total ?? invoice.total_ttc),
      items: (items ?? []).map((item) => ({
        ...item,
        quantity: String(item.quantity),
        unit_price: String(item.unit_price),
        line_total: String(item.line_total),
      })) as InvoiceItem[],
    };
  });

import { createServerFn } from "@tanstack/react-start";
import { setResponseHeader } from "@tanstack/react-start/server";
import { z } from "zod";

import { getSupabaseServerClient } from "@/lib/supabase/server";
import type { Json } from "@/types/database";
import type {
  DeliveryNoteDocument,
  DraftOrderEditorData,
  OrderDetailData,
  OrderEditorData,
  OrderWorkspaceData,
  TransportNoteDocument,
} from "./types";

const uuidRequest = z.object({ orderId: z.string().uuid() });
const lineSchema = z.object({
  description: z.string().trim().min(1).max(500),
  quantity: z.coerce.number().positive().max(999_999_999),
});
const orderSchema = z.object({
  customerId: z.string().uuid(),
  orderDate: z.string().date(),
  purchaseOrder: z.string().trim().max(200),
  destinationCity: z.string().trim().max(120),
  destinationAddress: z.string().trim().max(500),
  items: z.array(lineSchema).min(1).max(100),
});
const updateOrderSchema = orderSchema.extend({ orderId: z.string().uuid() });
const pricesSchema = z.object({
  invoiceId: z.string().uuid(),
  prices: z
    .array(z.object({ orderItemId: z.string().uuid(), unitPrice: z.coerce.number().nonnegative() }))
    .min(1),
});
const deliverySchema = z.object({
  deliveryNoteId: z.string().uuid(),
  deliveryDate: z.string().date(),
  preparedFor: z.string().trim().min(1).max(200),
  object: z.string().trim().min(1).max(300),
  handoverDate: z.string().date(),
  transportReceptionName: z.string().trim().max(200),
});
const transportSchema = z.object({
  transportNoteId: z.string().uuid(),
  transportDate: z.string().date(),
  transportPerson: z.string().trim().min(1).max(200),
  sender: z.string().trim().min(1).max(200),
  pickupDate: z.string().date(),
  loadingLocation: z.string().trim().min(1).max(200),
  destination: z.string().trim().min(1).max(500),
  vehicleRegistration: z.string().trim().min(1).max(100),
});

function privateResponse() {
  setResponseHeader("Cache-Control", "private, no-store");
  setResponseHeader("Vary", "Cookie, Authorization");
}

async function getManagerClient() {
  privateResponse();
  const supabase = getSupabaseServerClient();
  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData.user) throw new Error("Unauthorized");

  const [{ data: profile, error: profileError }, accessResult] = await Promise.all([
    supabase.from("profiles").select("role, is_active").eq("id", userData.user.id).maybeSingle(),
    supabase.rpc("has_environment_access", { environment_code: "FACOLUB" }),
  ]);
  if (profileError || accessResult.error) throw new Error("Unable to verify FACOLUB access");
  if (!profile?.is_active || profile.role === "factory" || !accessResult.data)
    throw new Error("Forbidden");
  return supabase;
}

export const getOrdersWorkspaceFn = createServerFn({ method: "GET" }).handler(
  async (): Promise<OrderWorkspaceData> => {
    const supabase = await getManagerClient();
    const { data: orders, error } = await supabase
      .from("orders")
      .select(
        "id, order_number, order_date, purchase_order, customer_id, customer_name_snapshot, status",
      )
      .order("created_at", { ascending: false })
      .limit(100);
    if (error) throw new Error("Unable to load orders");
    if (!orders?.length) return { orders: [] };
    const ids = orders.map((order) => order.id);
    const customerIds = [...new Set(orders.map((order) => order.customer_id))];
    const [customersResult, invoicesResult, deliveryResult, transportResult] = await Promise.all([
      supabase.from("customers").select("id, company_name").in("id", customerIds),
      supabase.from("invoices").select("id, order_id, invoice_number, status").in("order_id", ids),
      supabase
        .from("delivery_notes")
        .select("id, order_id, delivery_note_number, status")
        .in("order_id", ids),
      supabase
        .from("transport_notes")
        .select("id, order_id, transport_note_number, status")
        .in("order_id", ids),
    ]);
    if (
      customersResult.error ||
      invoicesResult.error ||
      deliveryResult.error ||
      transportResult.error
    )
      throw new Error("Unable to load order documents");
    const customerMap = new Map(
      (customersResult.data ?? []).map((row) => [row.id, row.company_name]),
    );
    const invoiceMap = new Map((invoicesResult.data ?? []).map((row) => [row.order_id!, row]));
    const deliveryMap = new Map((deliveryResult.data ?? []).map((row) => [row.order_id, row]));
    const transportMap = new Map((transportResult.data ?? []).map((row) => [row.order_id, row]));
    return {
      orders: orders.map((order) => {
        const invoice = invoiceMap.get(order.id);
        const delivery = deliveryMap.get(order.id);
        const transport = transportMap.get(order.id);
        return {
          id: order.id,
          order_number: order.order_number,
          order_date: order.order_date,
          purchase_order: order.purchase_order,
          customer_name:
            order.customer_name_snapshot ?? customerMap.get(order.customer_id) ?? "Client",
          status: order.status,
          invoice: invoice
            ? { id: invoice.id, number: invoice.invoice_number, status: invoice.status }
            : null,
          delivery_note: delivery
            ? { id: delivery.id, number: delivery.delivery_note_number, status: delivery.status }
            : null,
          transport_note: transport
            ? {
                id: transport.id,
                number: transport.transport_note_number,
                status: transport.status,
              }
            : null,
        };
      }),
    };
  },
);

export const getOrderEditorDataFn = createServerFn({ method: "GET" }).handler(
  async (): Promise<OrderEditorData> => {
    const supabase = await getManagerClient();
    const { data, error } = await supabase
      .from("customers")
      .select("id, company_name, city, address, purchase_order_default")
      .eq("is_active", true)
      .order("company_name");
    if (error) throw new Error("Unable to load customers");
    return { customers: data ?? [], today: new Date().toISOString().slice(0, 10) };
  },
);

export const getDraftOrderEditorFn = createServerFn({ method: "GET" })
  .validator((input: unknown) => uuidRequest.parse(input))
  .handler(async ({ data }): Promise<DraftOrderEditorData> => {
    const supabase = await getManagerClient();
    const [customersResult, orderResult, itemsResult] = await Promise.all([
      supabase
        .from("customers")
        .select("id, company_name, city, address, purchase_order_default")
        .eq("is_active", true)
        .order("company_name"),
      supabase
        .from("orders")
        .select(
          "id, customer_id, order_date, purchase_order, destination_city, destination_address",
        )
        .eq("id", data.orderId)
        .eq("status", "draft")
        .single(),
      supabase
        .from("order_items")
        .select("id, description, quantity, position")
        .eq("order_id", data.orderId)
        .order("position"),
    ]);
    if (customersResult.error || orderResult.error || !orderResult.data || itemsResult.error) {
      throw new Error("Draft order not found");
    }
    return {
      today: new Date().toISOString().slice(0, 10),
      customers: customersResult.data ?? [],
      order: orderResult.data,
      items: (itemsResult.data ?? []).map((item) => ({ ...item, quantity: String(item.quantity) })),
    };
  });

export const createOrderFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => orderSchema.parse(input))
  .handler(async ({ data }) => {
    const supabase = await getManagerClient();
    const { data: order, error } = await supabase.rpc("create_order", {
      target_customer_id: data.customerId,
      target_order_date: data.orderDate,
      target_purchase_order: data.purchaseOrder || null,
      target_destination_city: data.destinationCity || null,
      target_destination_address: data.destinationAddress || null,
      target_items: data.items as Json,
    });
    if (error || !order) throw new Error(error?.message ?? "Unable to create order");
    return order;
  });

export const updateOrderFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => updateOrderSchema.parse(input))
  .handler(async ({ data }) => {
    const supabase = await getManagerClient();
    const { data: order, error } = await supabase.rpc("update_draft_order", {
      target_order_id: data.orderId,
      target_customer_id: data.customerId,
      target_order_date: data.orderDate,
      target_purchase_order: data.purchaseOrder || null,
      target_destination_city: data.destinationCity || null,
      target_destination_address: data.destinationAddress || null,
      target_items: data.items as Json,
    });
    if (error || !order) throw new Error(error?.message ?? "Unable to update order");
    return order;
  });

export const confirmOrderFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => uuidRequest.parse(input))
  .handler(async ({ data }) => {
    const supabase = await getManagerClient();
    const { data: order, error } = await supabase.rpc("confirm_order", {
      target_order_id: data.orderId,
    });
    if (error || !order) throw new Error(error?.message ?? "Unable to confirm order");
    return order;
  });

export const prepareBundleFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => uuidRequest.parse(input))
  .handler(async ({ data }) => {
    const supabase = await getManagerClient();
    const { data: order, error } = await supabase.rpc("prepare_document_bundle", {
      target_order_id: data.orderId,
    });
    if (error || !order) throw new Error(error?.message ?? "Unable to prepare documents");
    return order;
  });

export const getOrderDetailFn = createServerFn({ method: "GET" })
  .validator((input: unknown) => uuidRequest.parse(input))
  .handler(async ({ data }): Promise<OrderDetailData> => {
    const supabase = await getManagerClient();
    const [
      { data: order, error },
      { data: items },
      { data: invoice },
      { data: delivery },
      { data: transport },
    ] = await Promise.all([
      supabase
        .from("orders")
        .select(
          "id, order_number, order_reference, order_date, purchase_order, destination_city, destination_address, customer_id, customer_name_snapshot, status",
        )
        .eq("id", data.orderId)
        .single(),
      supabase
        .from("order_items")
        .select("id, description, quantity, position")
        .eq("order_id", data.orderId)
        .order("position"),
      supabase
        .from("invoices")
        .select("id, invoice_number, status, prices_confirmed_at")
        .eq("order_id", data.orderId)
        .maybeSingle(),
      supabase
        .from("delivery_notes")
        .select("id, delivery_note_number, status")
        .eq("order_id", data.orderId)
        .maybeSingle(),
      supabase
        .from("transport_notes")
        .select("id, transport_note_number, status")
        .eq("order_id", data.orderId)
        .maybeSingle(),
    ]);
    if (error || !order) throw new Error("Order not found");
    let customerName = order.customer_name_snapshot;
    if (!customerName) {
      const { data: customer } = await supabase
        .from("customers")
        .select("company_name")
        .eq("id", order.customer_id)
        .single();
      customerName = customer?.company_name ?? "Client";
    }
    return {
      order: { ...order, customer_name: customerName },
      items: (items ?? []).map((item) => ({ ...item, quantity: String(item.quantity) })),
      invoice: invoice
        ? {
            id: invoice.id,
            number: invoice.invoice_number,
            status: invoice.status,
            prices_confirmed_at: invoice.prices_confirmed_at,
          }
        : null,
      delivery_note: delivery
        ? { id: delivery.id, number: delivery.delivery_note_number, status: delivery.status }
        : null,
      transport_note: transport
        ? { id: transport.id, number: transport.transport_note_number, status: transport.status }
        : null,
    };
  });

export const updateInvoicePricesFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => pricesSchema.parse(input))
  .handler(async ({ data }) => {
    const supabase = await getManagerClient();
    const { data: invoice, error } = await supabase.rpc("update_invoice_prices", {
      target_invoice_id: data.invoiceId,
      target_prices: data.prices.map((p) => ({
        order_item_id: p.orderItemId,
        unit_price: p.unitPrice,
      })),
    });
    if (error || !invoice) throw new Error(error?.message ?? "Unable to update prices");
    return invoice;
  });

export const updateDeliveryNoteFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => deliverySchema.parse(input))
  .handler(async ({ data }) => {
    const supabase = await getManagerClient();
    const { data: note, error } = await supabase.rpc("update_delivery_note", {
      target_delivery_note_id: data.deliveryNoteId,
      target_delivery_date: data.deliveryDate,
      target_prepared_for: data.preparedFor,
      target_object: data.object,
      target_handover_date: data.handoverDate,
      target_transport_reception_name: data.transportReceptionName || null,
    });
    if (error || !note) throw new Error(error?.message ?? "Unable to update delivery note");
    return note;
  });

export const updateTransportNoteFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => transportSchema.parse(input))
  .handler(async ({ data }) => {
    const supabase = await getManagerClient();
    const { data: note, error } = await supabase.rpc("update_transport_note", {
      target_transport_note_id: data.transportNoteId,
      target_transport_date: data.transportDate,
      target_transport_person: data.transportPerson,
      target_sender: data.sender,
      target_pickup_date: data.pickupDate,
      target_loading_location: data.loadingLocation,
      target_destination: data.destination,
      target_vehicle_registration: data.vehicleRegistration,
    });
    if (error || !note) throw new Error(error?.message ?? "Unable to update transport note");
    return note;
  });

export const issueDeliveryNoteFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => z.object({ documentId: z.string().uuid() }).parse(input))
  .handler(async ({ data }) => {
    const supabase = await getManagerClient();
    const { data: note, error } = await supabase.rpc("issue_delivery_note", {
      target_delivery_note_id: data.documentId,
    });
    if (error || !note) throw new Error(error?.message ?? "Unable to issue delivery note");
    return note;
  });

export const issueTransportNoteFn = createServerFn({ method: "POST" })
  .validator((input: unknown) => z.object({ documentId: z.string().uuid() }).parse(input))
  .handler(async ({ data }) => {
    const supabase = await getManagerClient();
    const { data: note, error } = await supabase.rpc("issue_transport_note", {
      target_transport_note_id: data.documentId,
    });
    if (error || !note) throw new Error(error?.message ?? "Unable to issue transport note");
    return note;
  });

export const getDeliveryNoteDocumentFn = createServerFn({ method: "GET" })
  .validator((input: unknown) => uuidRequest.parse(input))
  .handler(async ({ data }): Promise<DeliveryNoteDocument> => {
    const supabase = await getManagerClient();
    const [{ data: note, error }, { data: order }, { data: items }] = await Promise.all([
      supabase.from("delivery_notes").select("*").eq("order_id", data.orderId).single(),
      supabase.from("orders").select("order_number").eq("id", data.orderId).single(),
      supabase
        .from("order_items")
        .select("id, description, quantity, position")
        .eq("order_id", data.orderId)
        .order("position"),
    ]);
    if (error || !note || !order) throw new Error("Delivery note not found");
    return {
      ...note,
      order_number: order.order_number ?? "Commande",
      items: (items ?? []).map((i) => ({ ...i, quantity: String(i.quantity) })),
    };
  });

export const getTransportNoteDocumentFn = createServerFn({ method: "GET" })
  .validator((input: unknown) => uuidRequest.parse(input))
  .handler(async ({ data }): Promise<TransportNoteDocument> => {
    const supabase = await getManagerClient();
    const [{ data: note, error }, { data: order }, { data: items }] = await Promise.all([
      supabase.from("transport_notes").select("*").eq("order_id", data.orderId).single(),
      supabase.from("orders").select("order_number").eq("id", data.orderId).single(),
      supabase
        .from("order_items")
        .select("id, description, quantity, position")
        .eq("order_id", data.orderId)
        .order("position"),
    ]);
    if (error || !note || !order) throw new Error("Transport note not found");
    return {
      ...note,
      order_number: order.order_number ?? "Commande",
      items: (items ?? []).map((i) => ({ ...i, quantity: String(i.quantity) })),
    };
  });

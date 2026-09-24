export type InvoiceStatus = "draft" | "issued" | "cancelled";

export type InvoiceItem = {
  id: string;
  description: string;
  quantity: string;
  unit_price: string;
  line_total: string;
  position: number;
};

export type InvoiceDocument = {
  id: string;
  invoice_number: string | null;
  invoice_date: string;
  purchase_order: string | null;
  customer_name_snapshot: string;
  customer_city_snapshot: string | null;
  customer_address_snapshot: string | null;
  customer_ice_snapshot: string | null;
  status: InvoiceStatus;
  currency: string;
  authoritative_total: string;
  items: InvoiceItem[];
};

export type InvoiceWorkspaceCustomer = {
  id: string;
  company_name: string;
  city: string | null;
  address: string | null;
  ice: string | null;
  purchase_order_default: string | null;
};

export type InvoiceWorkspaceRow = {
  id: string;
  invoice_number: string | null;
  invoice_date: string;
  customer_name_snapshot: string;
  purchase_order: string | null;
  status: InvoiceStatus;
  total: number;
  created_at: string;
};

export type InvoiceWorkspaceData = {
  customers: InvoiceWorkspaceCustomer[];
  invoices: InvoiceWorkspaceRow[];
  today: string;
};

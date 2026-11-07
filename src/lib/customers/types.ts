import type { Customer, CustomerNote, CustomerPriceCategory } from "@/types/database";

export type CustomerListRow = {
  id: string;
  company_name: string;
  customer_code: string | null;
  contact_person: string | null;
  phone: string | null;
  email: string | null;
  city: string | null;
  ice: string | null;
  if_number: string | null;
  rc: string | null;
  default_price_category: CustomerPriceCategory | null;
  is_active: boolean;
  last_activity: string | null;
  order_count: number;
  invoice_count: number;
  delivery_note_count: number;
  transport_note_count: number;
};

export type CustomerDuplicate = Pick<
  Customer,
  "id" | "customer_code" | "company_name" | "ice" | "email" | "phone" | "is_active"
> & { matched_on: string[] };

export type CustomerDocument = {
  id: string;
  status: string;
  created_at: string;
  order_number?: string | null;
  order_date?: string;
  invoice_number?: string | null;
  invoice_date?: string;
  total_ttc?: number;
  delivery_note_number?: string | null;
  delivery_date?: string | null;
  transport_note_number?: string | null;
  transport_date?: string | null;
};

export type CustomerHistory = {
  orders: CustomerDocument[];
  invoices: CustomerDocument[];
  delivery_notes: CustomerDocument[];
  transport_notes: CustomerDocument[];
};

export type CustomerDetailData = {
  customer: Customer;
  notes: CustomerNote[];
  customPriceCount: number;
  history: CustomerHistory;
};

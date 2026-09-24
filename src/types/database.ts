export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[];

export type AppRole = "admin" | "management" | "factory";

export type Profile = {
  id: string;
  display_name: string;
  username: string | null;
  role: AppRole;
  is_active: boolean;
  created_at: string;
  updated_at: string;
};

export type Environment = {
  id: string;
  code: string;
  name: string;
  description: string | null;
  is_active: boolean;
  created_at: string;
  updated_at: string;
};

export type UserEnvironmentAccess = {
  id: string;
  user_id: string;
  environment_id: string;
  is_active: boolean;
  created_at: string;
  updated_at: string;
};

export type InvoiceStatus = "draft" | "issued" | "cancelled";

export type Customer = {
  id: string;
  company_name: string;
  contact_person: string | null;
  phone: string | null;
  email: string | null;
  city: string | null;
  address: string | null;
  ice: string | null;
  purchase_order_default: string | null;
  is_active: boolean;
  created_at: string;
  updated_at: string;
};

export type Invoice = {
  id: string;
  invoice_number: string | null;
  invoice_date: string;
  customer_id: string;
  purchase_order: string | null;
  customer_name_snapshot: string;
  customer_city_snapshot: string | null;
  customer_address_snapshot: string | null;
  customer_ice_snapshot: string | null;
  status: InvoiceStatus;
  currency: string;
  total: number;
  created_by: string | null;
  created_at: string;
  updated_at: string;
  issued_at: string | null;
  cancelled_at: string | null;
};

export type InvoiceItem = {
  id: string;
  invoice_id: string;
  description: string;
  quantity: number;
  unit_price: number;
  line_total: number;
  position: number;
  created_at: string;
};

export type Database = {
  public: {
    Tables: {
      environments: {
        Row: Environment;
        Insert: Omit<Environment, "id" | "created_at" | "updated_at"> & {
          id?: string;
          created_at?: string;
          updated_at?: string;
        };
        Update: Partial<Omit<Environment, "id" | "created_at">>;
        Relationships: [];
      };
      profiles: {
        Row: Profile;
        Insert: Omit<Profile, "created_at" | "updated_at"> & {
          created_at?: string;
          updated_at?: string;
        };
        Update: Partial<Omit<Profile, "id" | "created_at">>;
        Relationships: [];
      };
      user_environment_access: {
        Row: UserEnvironmentAccess;
        Insert: Omit<UserEnvironmentAccess, "id" | "created_at" | "updated_at"> & {
          id?: string;
          created_at?: string;
          updated_at?: string;
        };
        Update: Partial<Omit<UserEnvironmentAccess, "id" | "created_at">>;
        Relationships: [];
      };
      customers: {
        Row: Customer;
        Insert: Omit<Customer, "id" | "created_at" | "updated_at"> & {
          id?: string;
          created_at?: string;
          updated_at?: string;
        };
        Update: Partial<Omit<Customer, "id" | "created_at">>;
        Relationships: [];
      };
      invoices: {
        Row: Invoice;
        Insert: Omit<Invoice, "id" | "total" | "created_at" | "updated_at"> & {
          id?: string;
          total?: number;
          created_at?: string;
          updated_at?: string;
        };
        Update: Partial<Omit<Invoice, "id" | "created_at" | "total">>;
        Relationships: [];
      };
      invoice_items: {
        Row: InvoiceItem;
        Insert: Omit<InvoiceItem, "id" | "line_total" | "created_at"> & {
          id?: string;
          created_at?: string;
        };
        Update: Partial<Omit<InvoiceItem, "id" | "line_total" | "created_at">>;
        Relationships: [];
      };
      invoice_number_sequences: {
        Row: { invoice_year: number; last_value: number };
        Insert: { invoice_year: number; last_value: number };
        Update: { last_value?: number };
        Relationships: [];
      };
    };
    Views: Record<string, never>;
    Functions: {
      current_app_role: { Args: Record<PropertyKey, never>; Returns: AppRole | null };
      has_environment_access: { Args: { environment_code: string }; Returns: boolean };
      is_admin: { Args: Record<PropertyKey, never>; Returns: boolean };
      invoice_authoritative_total: { Args: { target_invoice_id: string }; Returns: number };
      create_invoice_draft: {
        Args: {
          target_customer_id: string;
          target_invoice_date: string;
          target_purchase_order: string | null;
          target_items: Json;
        };
        Returns: Invoice;
      };
      issue_invoice: { Args: { target_invoice_id: string }; Returns: Invoice };
    };
    Enums: { app_role: AppRole; invoice_status: InvoiceStatus };
    CompositeTypes: Record<string, never>;
  };
};

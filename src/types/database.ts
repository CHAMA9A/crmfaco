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
  order_id: string | null;
  prices_confirmed_by: string | null;
  prices_confirmed_at: string | null;
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
  order_item_id: string | null;
};

export type OrderStatus = "draft" | "confirmed" | "documents_ready" | "completed" | "cancelled";
export type DocumentStatus = "draft" | "issued" | "cancelled";

export type Order = {
  id: string;
  order_number: string | null;
  order_reference: string | null;
  customer_id: string;
  order_date: string;
  purchase_order: string | null;
  destination_city: string | null;
  destination_address: string | null;
  status: OrderStatus;
  customer_name_snapshot: string | null;
  customer_city_snapshot: string | null;
  customer_address_snapshot: string | null;
  customer_ice_snapshot: string | null;
  created_by: string;
  confirmed_by: string | null;
  confirmed_at: string | null;
  created_at: string;
  updated_at: string;
};

export type OrderItem = {
  id: string;
  order_id: string;
  product_format_id: string | null;
  description: string;
  quantity: number;
  position: number;
  created_at: string;
  updated_at: string;
};

export type DeliveryNote = {
  id: string;
  order_id: string;
  delivery_note_number: string | null;
  delivery_date: string | null;
  prepared_for: string | null;
  object: string;
  handover_date: string | null;
  transport_reception_name: string | null;
  status: DocumentStatus;
  issued_by: string | null;
  issued_at: string | null;
  cancelled_at: string | null;
  created_at: string;
  updated_at: string;
};

export type TransportNote = {
  id: string;
  order_id: string;
  transport_note_number: string | null;
  transport_date: string | null;
  transport_person: string | null;
  sender: string;
  pickup_date: string | null;
  loading_location: string;
  destination: string | null;
  vehicle_registration: string | null;
  status: DocumentStatus;
  issued_by: string | null;
  issued_at: string | null;
  cancelled_at: string | null;
  created_at: string;
  updated_at: string;
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
        Insert: Omit<
          Invoice,
          | "id"
          | "total"
          | "created_at"
          | "updated_at"
          | "order_id"
          | "prices_confirmed_by"
          | "prices_confirmed_at"
        > & {
          id?: string;
          total?: number;
          created_at?: string;
          updated_at?: string;
          order_id?: string | null;
          prices_confirmed_by?: string | null;
          prices_confirmed_at?: string | null;
        };
        Update: Partial<Omit<Invoice, "id" | "created_at" | "total">>;
        Relationships: [];
      };
      orders: {
        Row: Order;
        Insert: Omit<Order, "id" | "created_at" | "updated_at"> & {
          id?: string;
          created_at?: string;
          updated_at?: string;
        };
        Update: Partial<Omit<Order, "id" | "created_at">>;
        Relationships: [];
      };
      order_items: {
        Row: OrderItem;
        Insert: Omit<OrderItem, "id" | "created_at" | "updated_at"> & {
          id?: string;
          created_at?: string;
          updated_at?: string;
        };
        Update: Partial<Omit<OrderItem, "id" | "created_at">>;
        Relationships: [];
      };
      delivery_notes: {
        Row: DeliveryNote;
        Insert: Omit<DeliveryNote, "id" | "created_at" | "updated_at"> & {
          id?: string;
          created_at?: string;
          updated_at?: string;
        };
        Update: Partial<Omit<DeliveryNote, "id" | "created_at">>;
        Relationships: [];
      };
      transport_notes: {
        Row: TransportNote;
        Insert: Omit<TransportNote, "id" | "created_at" | "updated_at"> & {
          id?: string;
          created_at?: string;
          updated_at?: string;
        };
        Update: Partial<Omit<TransportNote, "id" | "created_at">>;
        Relationships: [];
      };
      order_number_sequences: {
        Row: { sequence_date: string; last_value: number };
        Insert: { sequence_date: string; last_value: number };
        Update: { last_value?: number };
        Relationships: [];
      };
      invoice_items: {
        Row: InvoiceItem;
        Insert: Omit<InvoiceItem, "id" | "line_total" | "created_at" | "order_item_id"> & {
          id?: string;
          created_at?: string;
          order_item_id?: string | null;
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
      create_order: {
        Args: {
          target_customer_id: string;
          target_order_date: string;
          target_purchase_order: string | null;
          target_destination_city: string | null;
          target_destination_address: string | null;
          target_items: Json;
        };
        Returns: Order;
      };
      update_draft_order: {
        Args: {
          target_order_id: string;
          target_customer_id: string;
          target_order_date: string;
          target_purchase_order: string | null;
          target_destination_city: string | null;
          target_destination_address: string | null;
          target_items: Json;
        };
        Returns: Order;
      };
      confirm_order: { Args: { target_order_id: string }; Returns: Order };
      prepare_document_bundle: { Args: { target_order_id: string }; Returns: Order };
      update_invoice_prices: {
        Args: { target_invoice_id: string; target_prices: Json };
        Returns: Invoice;
      };
      update_delivery_note: {
        Args: {
          target_delivery_note_id: string;
          target_delivery_date: string | null;
          target_prepared_for: string | null;
          target_object: string;
          target_handover_date: string | null;
          target_transport_reception_name: string | null;
        };
        Returns: DeliveryNote;
      };
      issue_delivery_note: { Args: { target_delivery_note_id: string }; Returns: DeliveryNote };
      update_transport_note: {
        Args: {
          target_transport_note_id: string;
          target_transport_date: string | null;
          target_transport_person: string | null;
          target_sender: string;
          target_pickup_date: string | null;
          target_loading_location: string;
          target_destination: string | null;
          target_vehicle_registration: string | null;
        };
        Returns: TransportNote;
      };
      issue_transport_note: { Args: { target_transport_note_id: string }; Returns: TransportNote };
      cancel_document: {
        Args: { target_document_type: string; target_document_id: string };
        Returns: undefined;
      };
    };
    Enums: {
      app_role: AppRole;
      invoice_status: InvoiceStatus;
      order_status: OrderStatus;
      document_status: DocumentStatus;
    };
    CompositeTypes: Record<string, never>;
  };
};

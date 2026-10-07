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

export type StockItemCategory =
  | "empty_bottle"
  | "label"
  | "prepared_bottle"
  | "seal"
  | "carton"
  | "bulk_lubricant"
  | "finished_product"
  | "other";

export type StockUnit = "piece" | "liter" | "kilogram";
export type StockDirection = "in" | "out";
export type StockMovementType =
  | "opening_balance"
  | "receipt"
  | "preparation_consumption"
  | "preparation_output"
  | "production_consumption"
  | "production_output"
  | "dispatch"
  | "adjustment_in"
  | "adjustment_out"
  | "loss"
  | "damage"
  | "correction"
  | "reservation_release_related"
  | "other";
export type StockReservationStatus = "active" | "released" | "consumed" | "cancelled";
export type StockAdjustmentStatus = "draft" | "pending" | "approved" | "rejected" | "posted";

export type StockItem = {
  id: string;
  code: string | null;
  name: string;
  category: StockItemCategory;
  unit: StockUnit;
  product_format_id: string | null;
  is_active: boolean;
  minimum_stock: number | null;
  notes: string | null;
  created_at: string;
  updated_at: string;
};

export type StockLocation = {
  id: string;
  code: string;
  name: string;
  description: string | null;
  is_active: boolean;
  created_at: string;
  updated_at: string;
};

export type StockMovement = {
  id: string;
  stock_item_id: string;
  location_id: string;
  movement_type: StockMovementType;
  quantity: number;
  direction: StockDirection;
  reference_type: string | null;
  reference_id: string | null;
  reason: string | null;
  created_by: string;
  created_at: string;
  corrected_movement_id: string | null;
  metadata: Json;
};

export type StockReservation = {
  id: string;
  stock_item_id: string;
  location_id: string;
  quantity: number;
  status: StockReservationStatus;
  reference_type: string;
  reference_id: string;
  created_by: string;
  created_at: string;
  released_at: string | null;
  consumed_at: string | null;
};

export type StockBalance = {
  stock_item_id: string;
  location_id: string;
  physical_quantity: number;
  reserved_quantity: number;
  available_quantity: number;
};

export type StockAdjustment = {
  id: string;
  stock_item_id: string;
  location_id: string;
  expected_quantity: number;
  counted_quantity: number;
  difference_quantity: number;
  reason: string;
  status: StockAdjustmentStatus;
  requested_by: string;
  approved_by: string | null;
  approved_at: string | null;
  created_at: string;
  updated_at: string;
};

export type StockMovementResult = {
  movement_id: string;
  physical_quantity: number;
  reserved_quantity: number;
  available_quantity: number;
};

export type StockMovementHistoryRow = {
  id: string;
  created_at: string;
  stock_item_id: string;
  stock_item_name: string;
  category: StockItemCategory;
  location_id: string;
  location_name: string;
  movement_type: StockMovementType;
  direction: StockDirection;
  quantity: number;
  created_by: string;
  created_by_name: string;
  reason: string | null;
  reference_type: string | null;
  reference_id: string | null;
  corrected_movement_id: string | null;
};

export type ReceiptStatus = "draft" | "confirmed" | "cancelled";

export type Supplier = {
  id: string;
  name: string;
  phone: string | null;
  email: string | null;
  address: string | null;
  is_active: boolean;
  created_at: string;
  updated_at: string;
};

export type Receipt = {
  id: string;
  receipt_number: string | null;
  supplier_id: string | null;
  supplier_name_snapshot: string | null;
  reference: string | null;
  receipt_date: string;
  location_id: string | null;
  status: ReceiptStatus;
  comment: string | null;
  created_by: string;
  confirmed_by: string | null;
  confirmed_at: string | null;
  created_at: string;
  updated_at: string;
};

export type ReceiptItem = {
  id: string;
  receipt_id: string;
  stock_item_id: string;
  quantity: number;
  unit: StockUnit;
  position: number;
  created_at: string;
};

export type ReceiptAttachment = {
  id: string;
  receipt_id: string;
  storage_path: string;
  file_name: string | null;
  mime_type: string;
  file_size: number | null;
  uploaded_by: string;
  created_at: string;
};

export type ReceiptListRow = {
  id: string;
  receipt_number: string | null;
  receipt_date: string;
  status: ReceiptStatus;
  supplier_id: string | null;
  supplier_name: string | null;
  reference: string | null;
  location_id: string;
  location_name: string;
  created_by: string;
  created_by_name: string;
  confirmed_at: string | null;
  item_count: number;
  quantity_summary: string;
  photo_count: number;
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
      stock_items: {
        Row: StockItem;
        Insert: Omit<StockItem, "id" | "created_at" | "updated_at"> & {
          id?: string;
          created_at?: string;
          updated_at?: string;
        };
        Update: Partial<Omit<StockItem, "id" | "created_at">>;
        Relationships: [];
      };
      stock_locations: {
        Row: StockLocation;
        Insert: Omit<StockLocation, "id" | "created_at" | "updated_at"> & {
          id?: string;
          created_at?: string;
          updated_at?: string;
        };
        Update: Partial<Omit<StockLocation, "id" | "created_at">>;
        Relationships: [];
      };
      stock_movements: {
        Row: StockMovement;
        Insert: Omit<StockMovement, "id" | "created_at" | "metadata"> & {
          id?: string;
          created_at?: string;
          metadata?: Json;
        };
        Update: Partial<Omit<StockMovement, "id" | "created_at">>;
        Relationships: [];
      };
      stock_reservations: {
        Row: StockReservation;
        Insert: Omit<
          StockReservation,
          "id" | "status" | "created_at" | "released_at" | "consumed_at"
        > & {
          id?: string;
          status?: StockReservationStatus;
          created_at?: string;
          released_at?: string | null;
          consumed_at?: string | null;
        };
        Update: Partial<Omit<StockReservation, "id" | "created_at">>;
        Relationships: [];
      };
      stock_adjustments: {
        Row: StockAdjustment;
        Insert: Omit<
          StockAdjustment,
          "id" | "difference_quantity" | "created_at" | "updated_at"
        > & { id?: string; created_at?: string; updated_at?: string };
        Update: Partial<Omit<StockAdjustment, "id" | "difference_quantity" | "created_at">>;
        Relationships: [];
      };
      suppliers: {
        Row: Supplier;
        Insert: Omit<Supplier, "id" | "created_at" | "updated_at"> & {
          id?: string;
          created_at?: string;
          updated_at?: string;
        };
        Update: Partial<Omit<Supplier, "id" | "created_at">>;
        Relationships: [];
      };
      receipts: {
        Row: Receipt;
        Insert: Omit<
          Receipt,
          | "id"
          | "receipt_number"
          | "status"
          | "confirmed_by"
          | "confirmed_at"
          | "created_at"
          | "updated_at"
        > & {
          id?: string;
          receipt_number?: string | null;
          status?: ReceiptStatus;
          confirmed_by?: string | null;
          confirmed_at?: string | null;
          created_at?: string;
          updated_at?: string;
        };
        Update: Partial<Omit<Receipt, "id" | "created_at">>;
        Relationships: [];
      };
      receipt_items: {
        Row: ReceiptItem;
        Insert: Omit<ReceiptItem, "id" | "created_at"> & {
          id?: string;
          created_at?: string;
        };
        Update: Partial<Omit<ReceiptItem, "id" | "created_at">>;
        Relationships: [];
      };
      receipt_attachments: {
        Row: ReceiptAttachment;
        Insert: Omit<ReceiptAttachment, "id" | "created_at"> & {
          id?: string;
          created_at?: string;
        };
        Update: Partial<Omit<ReceiptAttachment, "id" | "created_at">>;
        Relationships: [];
      };
      receipt_number_sequences: {
        Row: { receipt_date: string; last_value: number };
        Insert: { receipt_date: string; last_value: number };
        Update: { last_value?: number };
        Relationships: [];
      };
    };
    Views: {
      stock_balances: {
        Row: StockBalance;
        Relationships: [];
      };
    };
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
      record_stock_movement: {
        Args: {
          target_stock_item_id: string;
          target_location_id: string | null;
          target_movement_type: StockMovementType;
          target_quantity: number;
          target_direction: StockDirection;
          target_reference_type?: string | null;
          target_reference_id?: string | null;
          target_reason?: string | null;
          target_metadata?: Json;
          target_allow_negative?: boolean;
        };
        Returns: StockMovementResult[];
      };
      record_stock_correction: {
        Args: {
          target_movement_id: string;
          target_quantity: number;
          target_reason: string;
          target_allow_negative?: boolean;
        };
        Returns: StockMovementResult[];
      };
      get_stock_balance: {
        Args: { target_stock_item_id: string; target_location_id?: string | null };
        Returns: StockBalance[];
      };
      get_stock_movement_history: {
        Args: {
          target_stock_item_id?: string | null;
          target_category?: StockItemCategory | null;
          target_date_from?: string | null;
          target_date_to?: string | null;
          target_movement_type?: StockMovementType | null;
          target_created_by?: string | null;
          target_limit?: number;
        };
        Returns: StockMovementHistoryRow[];
      };
      create_stock_reservation: {
        Args: {
          target_stock_item_id: string;
          target_location_id: string | null;
          target_quantity: number;
          target_reference_type: string;
          target_reference_id: string;
        };
        Returns: StockReservation;
      };
      release_stock_reservation: {
        Args: { target_reservation_id: string };
        Returns: StockReservation;
      };
      consume_stock_reservation: {
        Args: { target_reservation_id: string };
        Returns: StockReservation;
      };
      save_stock_item: {
        Args: {
          target_id: string | null;
          target_code: string | null;
          target_name: string;
          target_category: StockItemCategory;
          target_unit: StockUnit;
          target_product_format_id: string | null;
          target_minimum_stock: number | null;
          target_notes: string | null;
          target_is_active: boolean;
        };
        Returns: StockItem;
      };
      save_supplier: {
        Args: {
          target_id: string | null;
          target_name: string;
          target_phone?: string | null;
          target_email?: string | null;
          target_address?: string | null;
          target_is_active?: boolean;
        };
        Returns: Supplier;
      };
      create_receipt_draft: {
        Args: {
          target_receipt_date?: string;
          target_location_id?: string | null;
          target_supplier_id?: string | null;
          target_supplier_name?: string | null;
          target_reference?: string | null;
          target_comment?: string | null;
        };
        Returns: Receipt;
      };
      update_receipt_draft: {
        Args: {
          target_receipt_id: string;
          target_receipt_date: string;
          target_location_id: string | null;
          target_supplier_id: string | null;
          target_supplier_name: string | null;
          target_reference: string | null;
          target_comment: string | null;
        };
        Returns: Receipt;
      };
      add_receipt_item: {
        Args: {
          target_receipt_id: string;
          target_stock_item_id: string;
          target_quantity: number;
          target_position?: number | null;
        };
        Returns: ReceiptItem;
      };
      remove_receipt_item: {
        Args: { target_receipt_item_id: string };
        Returns: undefined;
      };
      attach_receipt_photo: {
        Args: {
          target_receipt_id: string;
          target_storage_path: string;
          target_file_name: string;
          target_mime_type: string;
          target_file_size?: number | null;
        };
        Returns: ReceiptAttachment;
      };
      detach_receipt_photo: {
        Args: { target_attachment_id: string };
        Returns: string;
      };
      cancel_receipt: {
        Args: { target_receipt_id: string };
        Returns: Receipt;
      };
      confirm_receipt: {
        Args: { target_receipt_id: string };
        Returns: Json;
      };
      get_receipt: {
        Args: { target_receipt_id: string };
        Returns: Json;
      };
      list_receipts: {
        Args: {
          target_date_from?: string | null;
          target_date_to?: string | null;
          target_supplier_id?: string | null;
          target_stock_item_id?: string | null;
          target_created_by?: string | null;
          target_status?: ReceiptStatus | null;
          target_search?: string | null;
          target_limit?: number;
        };
        Returns: ReceiptListRow[];
      };
    };
    Enums: {
      app_role: AppRole;
      invoice_status: InvoiceStatus;
      order_status: OrderStatus;
      document_status: DocumentStatus;
      stock_item_category: StockItemCategory;
      stock_unit: StockUnit;
      stock_direction: StockDirection;
      stock_movement_type: StockMovementType;
      stock_reservation_status: StockReservationStatus;
      stock_adjustment_status: StockAdjustmentStatus;
      receipt_status: ReceiptStatus;
    };
    CompositeTypes: Record<string, never>;
  };
};

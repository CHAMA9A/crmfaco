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
    };
    Views: Record<string, never>;
    Functions: {
      current_app_role: { Args: Record<PropertyKey, never>; Returns: AppRole | null };
      has_environment_access: { Args: { environment_code: string }; Returns: boolean };
      is_admin: { Args: Record<PropertyKey, never>; Returns: boolean };
    };
    Enums: { app_role: AppRole };
    CompositeTypes: Record<string, never>;
  };
};

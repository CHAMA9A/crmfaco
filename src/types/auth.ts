import type { AppRole, Environment, Profile, UserEnvironmentAccess } from "./database";

export type { AppRole, Environment, Profile, UserEnvironmentAccess };

export type AuthenticatedUserContext = {
  id: string;
  email: string | null;
  profile: Profile;
  environments: Environment[];
};

export type AuthState =
  | { status: "anonymous"; user: null; reason?: "unconfigured" }
  | { status: "inactive"; user: Pick<AuthenticatedUserContext, "id" | "email">; profile: Profile }
  | { status: "authenticated"; user: AuthenticatedUserContext };

export type AdminUserSummary = {
  profile: Profile;
  facolubAccess: UserEnvironmentAccess | null;
};

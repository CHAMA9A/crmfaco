import { createContext, useContext, type ReactNode } from "react";

import type { AuthenticatedUserContext } from "@/types/auth";

const AuthContext = createContext<AuthenticatedUserContext | null>(null);

export function AuthProvider({
  user,
  children,
}: {
  user: AuthenticatedUserContext;
  children: ReactNode;
}) {
  return <AuthContext.Provider value={user}>{children}</AuthContext.Provider>;
}

export function useAuthenticatedUser() {
  const user = useContext(AuthContext);
  if (!user) throw new Error("useAuthenticatedUser must be used inside AuthProvider.");
  return user;
}

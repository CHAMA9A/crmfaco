import { Link, useRouterState } from "@tanstack/react-router";
import { useServerFn } from "@tanstack/react-start";
import { useState, type ReactNode } from "react";
import {
  Building2,
  ChevronRight,
  CircleUserRound,
  Factory,
  FileQuestion,
  LoaderCircle,
  LogOut,
  Menu,
  ShieldX,
  WifiOff,
} from "lucide-react";
import { LanguageToggle } from "@/components/app/language-toggle";
import { Button } from "@/components/ui/button";
import { Sheet, SheetContent, SheetHeader, SheetTitle, SheetTrigger } from "@/components/ui/sheet";
import { useAuthenticatedUser } from "@/lib/auth/context";
import { signOutFn } from "@/lib/auth/functions";
import { useLanguage } from "@/lib/i18n/use-language";
import { cn } from "@/lib/utils";
import {
  appLabels,
  factoryDesktopNav,
  factoryNav,
  navigationForRole,
  type NavGroup,
} from "@/lib/navigation";
import type { AppRole, AuthenticatedUserContext } from "@/types/auth";

export function StatusBadge({
  status,
}: {
  status:
    | "Available"
    | "Reserved"
    | "Unavailable"
    | "To Do"
    | "In Progress"
    | "Done"
    | "Blocked"
    | "Cancelled"
    | "Pending Approval"
    | "Active"
    | "Inactive";
}) {
  const { t } = useLanguage();
  const tone =
    status === "Done" || status === "Available" || status === "Active"
      ? "bg-success-soft text-success"
      : status === "In Progress" || status === "Reserved"
        ? "bg-info-soft text-info"
        : status === "Blocked" || status === "Unavailable"
          ? "bg-danger-soft text-danger"
          : "bg-warning-soft text-warning";
  return (
    <span
      className={cn(
        "inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-bold",
        tone,
      )}
    >
      <span className="h-1.5 w-1.5 rounded-full bg-current" />
      {t(status)}
    </span>
  );
}

export function AlertCounter({ children }: { children: ReactNode }) {
  return (
    <span className="rounded-full bg-warning-soft px-2.5 py-1 text-xs font-bold text-warning">
      {children}
    </span>
  );
}

export function PageHeader({
  title,
  description,
  eyebrow,
}: {
  title: string;
  description?: string;
  eyebrow?: string;
}) {
  const { t } = useLanguage();
  return (
    <div className="mb-6">
      <div className="mb-2 flex items-center gap-2 text-xs font-bold uppercase text-muted-foreground">
        <Link to="/facolub" className="hover:text-primary">
          FACOLUB
        </Link>
        {eyebrow && (
          <>
            <ChevronRight className="size-3" />
            <span>{t(eyebrow)}</span>
          </>
        )}
      </div>
      <h1 className="text-2xl font-bold text-foreground sm:text-3xl">{t(title)}</h1>
      {description && (
        <p className="mt-2 max-w-2xl text-sm leading-6 text-muted-foreground sm:text-base">
          {t(description)}
        </p>
      )}
    </div>
  );
}

export function EmptyState({
  title,
  description,
  icon: Icon,
}: {
  title: string;
  description: string;
  icon: typeof Factory;
}) {
  const { t } = useLanguage();
  return (
    <div className="border border-dashed border-border bg-card px-5 py-14 text-center">
      <div className="mx-auto grid size-12 place-items-center rounded-md bg-secondary text-primary">
        <Icon className="size-6" />
      </div>
      <h2 className="mt-5 text-lg font-bold">{t(title)}</h2>
      <p className="mx-auto mt-2 max-w-md text-sm leading-6 text-muted-foreground">
        {t(description)}
      </p>
      <span className="mt-5 inline-flex rounded-full bg-secondary px-3 py-1 text-xs font-bold uppercase text-secondary-foreground">
        {t("Progressive rollout")}
      </span>
    </div>
  );
}

export function AppState({ state }: { state: "loading" | "no-data" | "error" | "no-permission" }) {
  const states = {
    loading: {
      title: "Loading",
      description: "Preparing the latest information.",
      icon: LoaderCircle,
    },
    "no-data": {
      title: "No data yet",
      description: "Information will appear here when it becomes available.",
      icon: FileQuestion,
    },
    error: {
      title: "Unable to load",
      description: "Check your connection and try again.",
      icon: WifiOff,
    },
    "no-permission": {
      title: "Access restricted",
      description: "Your current role does not have access to this area.",
      icon: ShieldX,
    },
  } as const;
  const current = states[state];
  return <EmptyState title={current.title} description={current.description} icon={current.icon} />;
}

function NavGroups({ groups, close }: { groups: NavGroup[]; close?: () => void }) {
  const path = useRouterState({ select: (s) => s.location.pathname });
  const { t } = useLanguage();
  return (
    <nav className="space-y-5">
      {groups.map((group) => (
        <div key={group.label}>
          <p className="mb-1.5 px-3 text-[11px] font-bold uppercase text-sidebar-muted">
            {t(group.label)}
          </p>
          <div className="space-y-1">
            {group.items.map((item) => {
              const active = path === item.to;
              return (
                <Link
                  key={item.to}
                  to={item.to}
                  onClick={close}
                  className={cn(
                    "flex h-10 items-center gap-3 rounded-md px-3 text-sm font-medium transition-colors",
                    active
                      ? "bg-sidebar-accent text-sidebar-accent-foreground"
                      : "text-sidebar-foreground hover:bg-sidebar-hover",
                  )}
                >
                  <item.icon className="size-4 shrink-0" />
                  {t(item.label)}
                </Link>
              );
            })}
          </div>
        </div>
      ))}
    </nav>
  );
}

function BrandMark({ compact = false }: { compact?: boolean }) {
  return (
    <div className="flex min-w-0 items-center gap-3">
      <div className="grid size-9 shrink-0 place-items-center rounded-md bg-brand text-brand-foreground">
        <span className="text-sm font-black">S</span>
      </div>
      {!compact && (
        <div className="min-w-0">
          <p className="truncate text-sm font-bold text-foreground">{appLabels.environment}</p>
          <p className="truncate text-[11px] font-semibold uppercase text-muted-foreground">
            {appLabels.company}
          </p>
        </div>
      )}
    </div>
  );
}

export function UserControl({ user }: { user: AuthenticatedUserContext }) {
  const signOut = useServerFn(signOutFn);
  const { t } = useLanguage();
  const [pending, setPending] = useState(false);

  const handleSignOut = async () => {
    if (pending) return;
    setPending(true);
    try {
      await signOut();
    } finally {
      window.location.replace("/login");
    }
  };

  return (
    <details className="group relative">
      <summary className="flex h-10 cursor-pointer list-none items-center gap-2 rounded-md px-2 text-sm font-medium hover:bg-accent [&::-webkit-details-marker]:hidden">
        <CircleUserRound className="size-4" />
        <span className="hidden max-w-40 truncate text-sm font-semibold sm:inline">
          {user.profile.display_name}
        </span>
      </summary>
      <div className="absolute right-0 z-50 mt-1 w-64 rounded-md border bg-popover p-1 text-popover-foreground shadow-md">
        <div className="px-2 py-1.5 text-sm font-semibold">
          <span className="block truncate">{user.profile.display_name}</span>
          <span className="mt-1 block text-xs font-normal text-muted-foreground">
            {user.profile.role} ·{" "}
            {user.environments.map((item) => item.code).join(", ") || t("No environment")}
          </span>
        </div>
        <div className="-mx-1 my-1 h-px bg-muted" />
        <button
          type="button"
          disabled={pending}
          onClick={() => void handleSignOut()}
          className="flex w-full items-center gap-2 rounded-sm px-2 py-1.5 text-left text-sm outline-none hover:bg-accent disabled:opacity-50"
        >
          <LogOut className="size-4" />
          {pending ? t("Signing out…") : t("Sign out")}
        </button>
      </div>
    </details>
  );
}

function AppHeader({ role }: { role: AppRole }) {
  const user = useAuthenticatedUser();
  const { t } = useLanguage();
  return (
    <header className="facolub-shell-chrome sticky top-0 z-30 border-b border-border bg-background/95 backdrop-blur">
      <div className="grid h-16 grid-cols-[auto_minmax(0,1fr)_auto] items-center gap-3 px-4 lg:px-6">
        <div className="lg:hidden">
          <MobileMenu role={role} />
        </div>
        <div className="lg:hidden">
          <BrandMark />
        </div>
        <div className="hidden lg:block">
          <p className="text-xs font-semibold text-muted-foreground">
            {role === "factory"
              ? t("Factory workspace")
              : t(role === "admin" ? "Admin workspace" : "Management workspace")}
          </p>
        </div>
        <div className="flex items-center gap-2">
          <LanguageToggle />
          <Button asChild variant="outline" size="sm" className="hidden sm:inline-flex">
            <Link to="/environments">
              <Building2 />
              {t("Environments")}
            </Link>
          </Button>
          <UserControl user={user} />
        </div>
      </div>
    </header>
  );
}

function MobileMenu({ role }: { role: AppRole }) {
  const { t } = useLanguage();
  return (
    <Sheet>
      <SheetTrigger asChild>
        <Button variant="ghost" size="icon" aria-label={t("Open menu")}>
          <Menu />
        </Button>
      </SheetTrigger>
      <SheetContent side="left" className="w-[86vw] max-w-xs p-0">
        <SheetHeader className="border-b p-5 text-left">
          <SheetTitle>
            <BrandMark />
          </SheetTitle>
        </SheetHeader>
        <div className="p-4">
          <NavGroups
            groups={
              role === "factory"
                ? [{ label: t("Factory tools"), items: factoryNav }]
                : navigationForRole(role)
            }
          />
          <div className="mt-6 border-t pt-4">
            <Button asChild variant="ghost" className="w-full justify-start">
              <Link to="/environments">
                <Building2 />
                {t("Change environment")}
              </Link>
            </Button>
          </div>
        </div>
      </SheetContent>
    </Sheet>
  );
}

function FactoryBottomNavigation() {
  const path = useRouterState({ select: (s) => s.location.pathname });
  const { t } = useLanguage();
  return (
    <nav className="fixed inset-x-0 bottom-0 z-30 grid grid-cols-5 border-t border-border bg-background pb-[env(safe-area-inset-bottom)] lg:hidden">
      {factoryNav.map((item) => (
        <Link
          key={item.to}
          to={item.to}
          className={cn(
            "flex h-16 flex-col items-center justify-center gap-1 text-[10px] font-bold",
            path === item.to ? "text-primary" : "text-muted-foreground",
          )}
        >
          <item.icon className="size-5" />
          {t(item.label)}
        </Link>
      ))}
    </nav>
  );
}

function FactoryDesktopNavigation() {
  const path = useRouterState({ select: (s) => s.location.pathname });
  const { t } = useLanguage();
  return (
    <nav
      aria-label={t("Factory workspace navigation")}
      className="hidden border-b border-border bg-background px-6 lg:block"
    >
      <div className="mx-auto flex max-w-7xl items-center gap-1 overflow-x-auto py-2">
        {factoryDesktopNav.map((item) => (
          <Link
            key={item.to}
            to={item.to}
            className={cn(
              "inline-flex h-10 shrink-0 items-center gap-2 rounded-md px-3 text-sm font-semibold transition-colors",
              path === item.to
                ? "bg-primary text-primary-foreground"
                : "text-muted-foreground hover:bg-secondary hover:text-foreground",
            )}
          >
            <item.icon className="size-4" />
            {t(item.label)}
          </Link>
        ))}
      </div>
    </nav>
  );
}

export function FacolubShell({ children }: { children: ReactNode }) {
  const { profile } = useAuthenticatedUser();
  const { t } = useLanguage();
  const role = profile.role;
  return (
    <div className="min-h-screen bg-background">
      {role !== "factory" && (
        <aside className="facolub-shell-chrome fixed inset-y-0 left-0 z-40 hidden w-64 flex-col border-r border-sidebar-border bg-sidebar lg:flex">
          <div className="border-b border-sidebar-border p-5">
            <BrandMark />
          </div>
          <div className="flex-1 overflow-y-auto p-4">
            <NavGroups groups={navigationForRole(role)} />
          </div>
          <div className="border-t border-sidebar-border p-4">
            <Button
              asChild
              variant="ghost"
              className="w-full justify-start text-sidebar-foreground"
            >
              <Link to="/environments">
                <Building2 />
                {t("Change environment")}
              </Link>
            </Button>
          </div>
        </aside>
      )}
      <div className={cn("facolub-shell-body", role !== "factory" && "lg:pl-64")}>
        <AppHeader role={role} />
        {role === "factory" && <FactoryDesktopNavigation />}
        <main
          className={cn(
            "facolub-content mx-auto max-w-7xl px-4 py-6 sm:px-6 lg:px-8",
            role === "factory" && "max-w-5xl pb-24 lg:pb-8",
          )}
        >
          {children}
        </main>
      </div>
      {role === "factory" && <FactoryBottomNavigation />}
    </div>
  );
}

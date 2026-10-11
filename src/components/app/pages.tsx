import { Link } from "@tanstack/react-router";
import { useServerFn } from "@tanstack/react-start";
import { useState, type FormEvent } from "react";
import {
  ArrowRight,
  Building2,
  CalendarDays,
  ChartNoAxesCombined,
  CheckCircle2,
  ClipboardList,
  Eye,
  EyeOff,
  Factory,
  FileText,
  History,
  LockKeyhole,
  Package,
  PackagePlus,
  ShieldCheck,
  ShoppingCart,
  Truck,
  UserRound,
  Wallet,
  Boxes,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  AlertCounter,
  EmptyState,
  PageHeader,
  StatusBadge,
  UserControl,
} from "@/components/app/facolub-ui";
import { LanguageToggle } from "@/components/app/language-toggle";
import { FactoryMissionList } from "@/components/production/factory-missions";
import { appLabels, moduleDetails } from "@/lib/navigation";
import { signInFn } from "@/lib/auth/functions";
import { useLanguage } from "@/lib/i18n/use-language";
import type { AdminUserSummary, AuthenticatedUserContext } from "@/types/auth";
import type { ProductionMission } from "@/lib/production/types";

type ManagementModule = {
  title: string;
  description: string;
  to: string;
  icon: typeof Factory;
  badge?: string;
};
type FactoryAction = { label: string; to: string; icon: typeof Factory; primary?: boolean };

export function LoginPage({ inactive = false }: { inactive?: boolean }) {
  const signIn = useServerFn(signInFn);
  const { t } = useLanguage();
  const [showPassword, setShowPassword] = useState(false);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState(
    inactive ? "Your account is inactive. Contact an administrator." : "",
  );
  const submit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (pending) return;
    setPending(true);
    setError("");
    const form = new FormData(event.currentTarget);
    try {
      const result = await signIn({
        data: {
          email: String(form.get("email") ?? ""),
          password: String(form.get("password") ?? ""),
        },
      });
      if (result.ok) {
        window.location.replace("/environments");
        return;
      }
      setError(
        result.code === "inactive"
          ? "Your account is inactive. Contact an administrator."
          : result.code === "unavailable"
            ? "Sign-in is temporarily unavailable. Contact an administrator."
            : "The email or password is incorrect.",
      );
    } catch {
      setError("Sign-in could not be completed. Please try again.");
    } finally {
      setPending(false);
    }
  };
  return (
    <main className="relative grid min-h-screen bg-background lg:grid-cols-[minmax(0,1.05fr)_minmax(420px,.95fr)]">
      <div className="absolute right-4 top-4 z-20 sm:right-6 sm:top-5">
        <LanguageToggle />
      </div>
      <section className="relative hidden overflow-hidden bg-industrial p-12 text-industrial-foreground lg:flex lg:flex-col lg:justify-between">
        <div className="absolute inset-y-0 right-0 w-px bg-industrial-line" />
        <div className="flex items-center gap-3">
          <div className="grid size-11 place-items-center rounded-md bg-brand text-brand-foreground">
            <span className="text-lg font-black">S</span>
          </div>
          <div>
            <p className="font-bold">{appLabels.company}</p>
            <p className="text-xs text-industrial-muted">{t("Internal systems")}</p>
          </div>
        </div>
        <div className="max-w-xl">
          <div className="mb-6 h-1 w-14 bg-brand" />
          <h1 className="text-5xl font-bold leading-tight">{t("Clarity for every operation.")}</h1>
          <p className="mt-5 max-w-lg text-lg leading-8 text-industrial-muted">
            {t(
              "One reliable workspace for SOMA Lubrifiants teams, from the factory floor to management.",
            )}
          </p>
        </div>
        <p className="text-xs font-semibold uppercase text-industrial-muted">
          {t("Authorized personnel only")}
        </p>
      </section>
      <section className="flex items-center justify-center px-5 py-10 sm:px-10">
        <div className="w-full max-w-md">
          <div className="mb-10 flex items-center gap-3 lg:hidden">
            <div className="grid size-10 place-items-center rounded-md bg-brand text-brand-foreground">
              <span className="font-black">S</span>
            </div>
            <div>
              <p className="font-bold">{appLabels.company}</p>
              <p className="text-xs text-muted-foreground">{t("Internal systems")}</p>
            </div>
          </div>
          <div className="mb-8">
            <span className="inline-flex items-center gap-2 text-xs font-bold uppercase text-primary">
              <ShieldCheck className="size-4" />
              {t("Secure internal access")}
            </span>
            <h1 className="mt-3 text-3xl font-bold">{t("Welcome back")}</h1>
            <p className="mt-2 text-sm text-muted-foreground">
              {t(`Sign in to the ${appLabels.product}.`)}
            </p>
          </div>
          <form onSubmit={submit} className="space-y-5">
            <div className="space-y-2">
              <Label htmlFor="email">{t("Email")}</Label>
              <div className="relative">
                <UserRound className="absolute left-3 top-3 size-4 text-muted-foreground" />
                <Input
                  id="email"
                  name="email"
                  type="email"
                  required
                  autoComplete="username"
                  placeholder={t("Enter your email")}
                  className="h-11 pl-10"
                />
              </div>
            </div>
            <div className="space-y-2">
              <div className="flex items-center justify-between gap-4">
                <Label htmlFor="password">{t("Password")}</Label>
                <Link
                  to="/forgot-password"
                  className="text-sm font-semibold text-primary hover:underline"
                >
                  {t("Forgot password?")}
                </Link>
              </div>
              <div className="relative">
                <LockKeyhole className="absolute left-3 top-3 size-4 text-muted-foreground" />
                <Input
                  id="password"
                  name="password"
                  required
                  type={showPassword ? "text" : "password"}
                  autoComplete="current-password"
                  placeholder={t("Enter your password")}
                  className="h-11 px-10"
                />
                <Button
                  type="button"
                  variant="ghost"
                  size="icon"
                  className="absolute right-1 top-1"
                  aria-label={t(showPassword ? "Hide password" : "Show password")}
                  onClick={() => setShowPassword(!showPassword)}
                >
                  {showPassword ? <EyeOff /> : <Eye />}
                </Button>
              </div>
            </div>
            {error && (
              <p role="alert" className="text-sm font-medium text-danger">
                {t(error)}
              </p>
            )}
            <Button type="submit" size="lg" className="h-12 w-full" disabled={pending}>
              {pending ? t("Signing in…") : t("Sign in")}
              <ArrowRight />
            </Button>
          </form>
        </div>
      </section>
    </main>
  );
}

export function EnvironmentsPage({ user }: { user: AuthenticatedUserContext }) {
  const { t } = useLanguage();
  return (
    <main className="min-h-screen bg-secondary/40">
      <header className="border-b bg-background">
        <div className="mx-auto flex h-16 max-w-6xl items-center justify-between px-4 sm:px-6">
          <div className="flex min-w-0 items-center gap-3">
            <div className="grid size-9 shrink-0 place-items-center rounded-md bg-brand text-brand-foreground">
              <span className="font-black">S</span>
            </div>
            <div className="min-w-0">
              <p className="truncate text-sm font-bold">{appLabels.company}</p>
              <p className="truncate text-xs text-muted-foreground">{appLabels.product}</p>
            </div>
          </div>
          <div className="flex items-center gap-2">
            <LanguageToggle />
            <UserControl user={user} />
          </div>
        </div>
      </header>
      <section className="mx-auto max-w-6xl px-4 py-10 sm:px-6 sm:py-16">
        <p className="text-xs font-bold uppercase text-primary">{t("Workspace access")}</p>
        <h1 className="mt-2 text-3xl font-bold sm:text-4xl">{t("Select your environment")}</h1>
        <p className="mt-3 text-muted-foreground">
          {t("Choose the operational environment you want to open.")}
        </p>
        {user.environments.length === 0 ? (
          <div className="mt-9 border border-dashed border-border bg-card p-10 text-center">
            <Building2 className="mx-auto size-10 text-muted-foreground" />
            <h2 className="mt-4 text-lg font-bold">{t("No environment assigned")}</h2>
            <p className="mt-2 text-sm text-muted-foreground">
              {t("Contact an administrator to request access to an operational environment.")}
            </p>
          </div>
        ) : (
          <div className="mt-9 grid gap-5 md:grid-cols-2 xl:grid-cols-3">
            {user.environments.map((environment) =>
              environment.code === "FACOLUB" ? (
                <Link
                  key={environment.id}
                  to="/facolub"
                  className="group border border-border bg-card p-6 shadow-sm transition hover:border-primary hover:shadow-md"
                >
                  <div className="flex items-start justify-between gap-4">
                    <div className="grid size-12 place-items-center rounded-md bg-primary text-primary-foreground">
                      <Factory className="size-6" />
                    </div>
                    <StatusBadge status="Active" />
                  </div>
                  <h2 className="mt-7 text-xl font-bold group-hover:text-primary">
                    {environment.name}
                  </h2>
                  <p className="mt-2 min-h-12 text-sm leading-6 text-muted-foreground">
                    {environment.description ?? t("Internal operations")}
                  </p>
                  <div className="mt-6 flex items-center justify-between border-t pt-4 text-sm font-bold">
                    <span>{t("Open environment")}</span>
                    <ArrowRight className="size-4 transition-transform group-hover:translate-x-1" />
                  </div>
                </Link>
              ) : (
                <div
                  key={environment.id}
                  className="border border-border bg-card p-6 text-muted-foreground"
                >
                  <Building2 className="size-8" />
                  <h2 className="mt-5 font-bold text-foreground">{environment.name}</h2>
                  <p className="mt-2 text-sm">
                    {t("This environment is not available in this release.")}
                  </p>
                </div>
              ),
            )}
          </div>
        )}
      </section>
    </main>
  );
}

const managementModules: ManagementModule[] = [
  {
    title: "Stock & Operations",
    description: "Warehouse visibility and daily movements",
    to: "/facolub/stock",
    icon: Package,
    badge: "3 alerts",
  },
  {
    title: "Documents & Dispatch",
    description: "Documents, loading and shipments",
    to: "/facolub/documents",
    icon: FileText,
    badge: "1 pending",
  },
  {
    title: "Analytics",
    description: "Operational performance overview",
    to: "/facolub/analytics",
    icon: ChartNoAxesCombined,
  },
  { title: "Costs", description: "Operational cost tracking", to: "/facolub/costs", icon: Wallet },
  {
    title: "Planning",
    description: "Schedules and production priorities",
    to: "/facolub/planning",
    icon: CalendarDays,
    badge: "2 planned",
  },
  {
    title: "Purchases / Input Prices",
    description: "Supplier purchases and input pricing",
    to: "/facolub/purchases",
    icon: ShoppingCart,
  },
];

export function ManagementHomePage() {
  const { t } = useLanguage();
  // Six-area operational hierarchy, fixed order (2 columns x 3 rows on desktop/tablet):
  // Row 1: Stock & Operations | Documents & Dispatch · Row 2: Analytics | Costs · Row 3: Planning | Purchases / Input Prices
  // Keep this grid strictly two columns (grid-cols-1 md:grid-cols-2) — do not widen to three columns.
  return (
    <>
      <PageHeader
        title="Operations overview"
        description="Choose an area to continue managing FACOLUB operations."
      />
      <div className="mb-6 grid grid-cols-2 gap-3 sm:grid-cols-3">
        <div className="border-l-4 border-success bg-card p-4 shadow-sm">
          <p className="text-xs font-bold uppercase text-muted-foreground">{t("Environment")}</p>
          <p className="mt-1 font-bold">{t("Operational")}</p>
        </div>
        <div className="border-l-4 border-warning bg-card p-4 shadow-sm">
          <p className="text-xs font-bold uppercase text-muted-foreground">{t("Attention")}</p>
          <p className="mt-1 font-bold">{t("3 alerts")}</p>
        </div>
        <div className="col-span-2 border-l-4 border-info bg-card p-4 shadow-sm sm:col-span-1">
          <p className="text-xs font-bold uppercase text-muted-foreground">{t("Today")}</p>
          <p className="mt-1 font-bold">{t("2 planned runs")}</p>
        </div>
      </div>
      <div className="grid gap-4 md:grid-cols-2">
        {managementModules.map((module) => (
          <Link
            key={module.title}
            to={module.to}
            className="group flex min-h-48 flex-col justify-between border border-border bg-card p-5 shadow-sm transition hover:-translate-y-0.5 hover:border-primary hover:shadow-md"
          >
            <div className="flex items-start justify-between gap-3">
              <div className="grid size-11 place-items-center rounded-md bg-secondary text-primary">
                <module.icon className="size-5" />
              </div>
              {module.badge && <AlertCounter>{t(module.badge)}</AlertCounter>}
            </div>
            <div>
              <h2 className="text-lg font-bold group-hover:text-primary">{t(module.title)}</h2>
              <p className="mt-1 text-sm leading-6 text-muted-foreground">
                {t(module.description)}
              </p>
              <div className="mt-4 flex items-center gap-2 text-sm font-bold text-primary">
                {t("Open module")}
                <ArrowRight className="size-4 transition-transform group-hover:translate-x-1" />
              </div>
            </div>
          </Link>
        ))}
      </div>
    </>
  );
}

const factoryActions: FactoryAction[] = [
  { label: "Today", to: "/facolub/today", icon: ClipboardList, primary: true },
  { label: "Stock", to: "/facolub/stock", icon: Boxes },
  { label: "Receive", to: "/facolub/receiving", icon: PackagePlus },
  { label: "Load / Send", to: "/facolub/dispatch", icon: Truck },
  { label: "Production", to: "/facolub/production", icon: CalendarDays },
  { label: "History / Problems", to: "/facolub/history", icon: History },
];

export function TodayPage({
  productionMissions = [],
}: {
  productionMissions?: ProductionMission[];
}) {
  const { t } = useLanguage();
  return (
    <>
      <PageHeader title="Today" description="Your assigned factory work for today." />
      <div className="mb-8 grid grid-cols-2 gap-3 sm:grid-cols-3">
        {factoryActions.map((action) => (
          <Link
            key={action.label}
            to={action.to}
            className={`flex min-h-28 flex-col justify-between border p-4 shadow-sm transition active:scale-[.98] ${action.primary ? "border-primary bg-primary text-primary-foreground" : "border-border bg-card"}`}
          >
            <action.icon className="size-6" />
            <span className="text-sm font-bold leading-tight">{t(action.label)}</span>
          </Link>
        ))}
      </div>
      <section>
        <div className="mb-3 flex items-center justify-between">
          <h2 className="text-lg font-bold">{t("Today’s missions")}</h2>
          <span className="text-xs font-semibold text-muted-foreground">
            {productionMissions.length} {t("tasks")}
          </span>
        </div>
        <FactoryMissionList missions={productionMissions} />
      </section>
    </>
  );
}

export function PlaceholderPage({ module }: { module: string }) {
  const detail = moduleDetails[module] ?? moduleDetails["stock"];
  if (!detail) return null;
  return (
    <>
      <PageHeader title={detail.title} description={detail.description} eyebrow={detail.title} />
      <EmptyState
        title={`${detail.title} is coming soon`}
        description="This area is prepared for progressive implementation. Workflows and live operational data will be added in a future phase."
        icon={detail.icon}
      />
    </>
  );
}

export function UsersPage({ users }: { users: AdminUserSummary[] }) {
  return (
    <>
      <PageHeader
        title="Users"
        description="Read-only identity, role and FACOLUB access overview. Changes remain administrator-controlled in Supabase."
        eyebrow="Users"
      />
      <div className="overflow-x-auto border border-border bg-card shadow-sm">
        <table className="w-full min-w-[760px] text-left text-sm">
          <thead className="border-b bg-secondary/60 text-xs uppercase text-muted-foreground">
            <tr>
              <th className="px-4 py-3">Display name</th>
              <th className="px-4 py-3">Username</th>
              <th className="px-4 py-3">Role</th>
              <th className="px-4 py-3">Account</th>
              <th className="px-4 py-3">FACOLUB access</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-border">
            {users.map(({ profile, facolubAccess }) => (
              <tr key={profile.id}>
                <td className="px-4 py-4 font-semibold">{profile.display_name}</td>
                <td className="px-4 py-4 text-muted-foreground">{profile.username ?? "—"}</td>
                <td className="px-4 py-4 capitalize">{profile.role}</td>
                <td className="px-4 py-4">
                  <StatusBadge status={profile.is_active ? "Active" : "Inactive"} />
                </td>
                <td className="px-4 py-4">
                  <span
                    className={
                      facolubAccess?.is_active
                        ? "font-semibold text-success"
                        : "text-muted-foreground"
                    }
                  >
                    {facolubAccess?.is_active ? "Assigned" : "Not assigned"}
                  </span>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        {users.length === 0 && (
          <p className="p-8 text-center text-sm text-muted-foreground">No profiles found.</p>
        )}
      </div>
      <p className="mt-3 text-xs text-muted-foreground">
        Email addresses are intentionally omitted because the browser client does not receive
        privileged auth.users data.
      </p>
    </>
  );
}

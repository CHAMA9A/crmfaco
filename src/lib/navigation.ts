import {
  Boxes,
  CalendarDays,
  ChartNoAxesCombined,
  ClipboardList,
  FileText,
  History,
  PackagePlus,
  PackageCheck,
  Settings,
  ShoppingCart,
  Truck,
  Users,
  Wallet,
  Factory,
  CircleDollarSign,
  UserRound,
  TriangleAlert,
} from "lucide-react";
import type { AppRole } from "@/types/auth";

export const appLabels = {
  company: "SOMA Lubrifiants",
  product: "Internal Management System",
  environment: "FACOLUB",
  demo: "Demo data",
};

export type NavItem = { label: string; to: string; icon: typeof Boxes; description?: string };
export type NavGroup = { label: string; items: NavItem[] };

const managementNav: NavGroup[] = [
  { label: "Overview", items: [{ label: "Home", to: "/facolub", icon: Factory }] },
  {
    label: "Operations",
    items: [
      { label: "Stock", to: "/facolub/stock", icon: Boxes },
      { label: "Planning", to: "/facolub/planning", icon: CalendarDays },
      { label: "Production", to: "/facolub/production", icon: Factory },
      { label: "Receiving", to: "/facolub/receiving", icon: PackagePlus },
      { label: "Prepare bottles", to: "/facolub/preparation", icon: PackageCheck },
      { label: "Dispatch", to: "/facolub/dispatch", icon: Truck },
    ],
  },
  {
    label: "Commercial",
    items: [
      { label: "Customers", to: "/facolub/customers", icon: UserRound },
      { label: "Prices", to: "/facolub/prices", icon: CircleDollarSign },
      { label: "Documents", to: "/facolub/documents", icon: FileText },
    ],
  },
  {
    label: "Management",
    items: [
      { label: "Purchases", to: "/facolub/purchases", icon: ShoppingCart },
      { label: "Costs", to: "/facolub/costs", icon: Wallet },
      { label: "Analytics", to: "/facolub/analytics", icon: ChartNoAxesCombined },
    ],
  },
  {
    label: "System",
    items: [
      { label: "History", to: "/facolub/history", icon: History },
      { label: "Problems", to: "/facolub/problems", icon: TriangleAlert },
      { label: "Users", to: "/facolub/users", icon: Users },
      { label: "Settings", to: "/facolub/settings", icon: Settings },
    ],
  },
];

export function navigationForRole(role: AppRole): NavGroup[] {
  if (role === "factory") return [{ label: "Factory tools", items: factoryDesktopNav }];
  if (role === "admin") return managementNav;
  return managementNav
    .map((group) => ({
      ...group,
      items: group.items.filter(
        (item) => item.to !== "/facolub/users" && item.to !== "/facolub/settings",
      ),
    }))
    .filter((group) => group.items.length > 0);
}

export const factoryNav: NavItem[] = [
  { label: "Today", to: "/facolub/today", icon: ClipboardList },
  { label: "Receive", to: "/facolub/receiving", icon: PackagePlus },
  { label: "Prepare", to: "/facolub/preparation", icon: PackageCheck },
  { label: "Dispatch", to: "/facolub/dispatch", icon: Truck },
  { label: "More", to: "/facolub/history", icon: History },
];

export const factoryDesktopNav: NavItem[] = [
  { label: "Today", to: "/facolub/today", icon: ClipboardList },
  { label: "Stock", to: "/facolub/stock", icon: Boxes },
  { label: "Receive", to: "/facolub/receiving", icon: PackagePlus },
  { label: "Prepare bottles", to: "/facolub/preparation", icon: PackageCheck },
  { label: "Production", to: "/facolub/production", icon: Factory },
  { label: "Load / Send", to: "/facolub/dispatch", icon: Truck },
  { label: "History / Problems", to: "/facolub/history", icon: History },
  { label: "Problems", to: "/facolub/problems", icon: TriangleAlert },
];

export const moduleDetails: Record<
  string,
  { title: string; description: string; icon: typeof Boxes }
> = {
  stock: {
    title: "Stock & Operations",
    description: "Inventory visibility and warehouse operations will be managed here.",
    icon: Boxes,
  },
  receiving: {
    title: "Receiving",
    description: "Incoming materials and receipt checks will be managed here.",
    icon: PackagePlus,
  },
  preparation: {
    title: "Prepared Bottles",
    description: "Empty bottles and labels are transformed into filling-ready packaging here.",
    icon: PackageCheck,
  },
  planning: {
    title: "Planning",
    description: "Production and operations schedules will be coordinated here.",
    icon: CalendarDays,
  },
  production: {
    title: "Production",
    description: "Production orders and shop-floor progress will be managed here.",
    icon: Factory,
  },
  dispatch: {
    title: "Dispatch",
    description: "Loading, shipment preparation and dispatch confirmation will be managed here.",
    icon: Truck,
  },
  documents: {
    title: "Documents & Dispatch",
    description: "Operational documents and delivery paperwork will be managed here.",
    icon: FileText,
  },
  customers: {
    title: "Customers",
    description: "Customer records and operational context will be managed here.",
    icon: UserRound,
  },
  prices: {
    title: "Prices",
    description: "Commercial and input price references will be managed here.",
    icon: CircleDollarSign,
  },
  purchases: {
    title: "Purchases / Input Prices",
    description: "Purchasing activity and supplier inputs will be managed here.",
    icon: ShoppingCart,
  },
  costs: {
    title: "Costs",
    description: "Operational cost structures will be managed here.",
    icon: Wallet,
  },
  analytics: {
    title: "Analytics",
    description: "Operational performance and reporting will be available here.",
    icon: ChartNoAxesCombined,
  },
  history: {
    title: "History",
    description: "Operational activity and traceability records will be available here.",
    icon: History,
  },
  problems: {
    title: "Problems",
    description: "Blocked work and reported operational issues will be managed here.",
    icon: TriangleAlert,
  },
  settings: {
    title: "Settings",
    description: "FACOLUB environment preferences will be managed here.",
    icon: Settings,
  },
  users: {
    title: "Users",
    description: "User access and future role assignments will be managed here.",
    icon: Users,
  },
};

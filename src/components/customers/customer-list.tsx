import { Link, useRouter } from "@tanstack/react-router";
import { useServerFn } from "@tanstack/react-start";
import { useMemo, useState } from "react";
import { Building2, Plus, Search } from "lucide-react";
import { PageHeader, StatusBadge } from "@/components/app/facolub-ui";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { searchCustomersFn } from "@/lib/customers/functions";
import type { CustomerListRow } from "@/lib/customers/types";

const categories = ["intercompany", "wholesale", "retail", "custom"] as const;
const label = (value: string | null) => (value ? value[0]!.toUpperCase() + value.slice(1) : "—");
const date = (value: string | null) =>
  value ? new Intl.DateTimeFormat("fr-FR").format(new Date(value)) : "—";

export function CustomerList({
  initialRows,
  cities,
}: {
  initialRows: CustomerListRow[];
  cities: string[];
}) {
  const searchFn = useServerFn(searchCustomersFn);
  const router = useRouter();
  const [rows, setRows] = useState(initialRows);
  const [query, setQuery] = useState("");
  const [active, setActive] = useState("all");
  const [city, setCity] = useState("");
  const [category, setCategory] = useState("");
  const [pending, setPending] = useState(false);
  const summary = useMemo(() => `${rows.length} client${rows.length === 1 ? "" : "s"}`, [rows]);

  async function runSearch() {
    setPending(true);
    try {
      setRows(
        await searchFn({
          data: {
            search: query || null,
            active: active === "all" ? null : active === "active",
            city: city || null,
            priceCategory: category ? (category as (typeof categories)[number]) : null,
          },
        }),
      );
    } finally {
      setPending(false);
    }
  }

  return (
    <>
      <div className="flex flex-wrap items-start justify-between gap-3">
        <PageHeader
          eyebrow="Commercial"
          title="Clients"
          description="Référentiel CRM interne, activité documentaire et informations de livraison."
        />
        <Button asChild>
          <Link to="/facolub/customers/new">
            <Plus />
            Nouveau client
          </Link>
        </Button>
      </div>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          void runSearch();
        }}
        className="mb-5 grid gap-3 rounded-lg border bg-card p-4 lg:grid-cols-[minmax(240px,1fr)_160px_180px_180px_auto]"
      >
        <div className="relative">
          <Search className="absolute left-3 top-3 size-4 text-muted-foreground" />
          <Input
            className="pl-9"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Nom, code, contact, téléphone, ICE, IF, RC…"
          />
        </div>
        <select
          className="h-10 rounded-md border bg-background px-3"
          value={active}
          onChange={(e) => setActive(e.target.value)}
        >
          <option value="all">Tous statuts</option>
          <option value="active">Actifs</option>
          <option value="inactive">Inactifs</option>
        </select>
        <select
          className="h-10 rounded-md border bg-background px-3"
          value={city}
          onChange={(e) => setCity(e.target.value)}
        >
          <option value="">Toutes les villes</option>
          {cities.map((value) => (
            <option key={value}>{value}</option>
          ))}
        </select>
        <select
          className="h-10 rounded-md border bg-background px-3"
          value={category}
          onChange={(e) => setCategory(e.target.value)}
        >
          <option value="">Tous les tarifs</option>
          {categories.map((value) => (
            <option key={value} value={value}>
              {label(value)}
            </option>
          ))}
        </select>
        <Button disabled={pending}>{pending ? "Recherche…" : "Rechercher"}</Button>
      </form>
      <p className="mb-3 text-sm text-muted-foreground">{summary}</p>
      <div className="grid gap-3 md:hidden">
        {rows.map((row) => (
          <Card key={row.id}>
            <CardContent className="p-4">
              <div className="flex justify-between gap-3">
                <div>
                  <h2 className="font-bold">{row.company_name}</h2>
                  <p className="text-xs text-muted-foreground">
                    {row.customer_code ?? "Sans code"} · {row.city ?? "Ville non renseignée"}
                  </p>
                </div>
                <StatusBadge status={row.is_active ? "Active" : "Inactive"} />
              </div>
              <dl className="mt-4 grid grid-cols-2 gap-3 text-sm">
                <div>
                  <dt className="text-muted-foreground">Contact</dt>
                  <dd>{row.contact_person ?? "—"}</dd>
                </div>
                <div>
                  <dt className="text-muted-foreground">Téléphone</dt>
                  <dd>{row.phone ?? "—"}</dd>
                </div>
                <div>
                  <dt className="text-muted-foreground">ICE</dt>
                  <dd>{row.ice ?? "—"}</dd>
                </div>
                <div>
                  <dt className="text-muted-foreground">Tarif</dt>
                  <dd>{label(row.default_price_category)}</dd>
                </div>
              </dl>
              <Button
                className="mt-4 w-full"
                variant="outline"
                onClick={() =>
                  void router.navigate({
                    to: "/facolub/customers/$customerId",
                    params: { customerId: row.id },
                  })
                }
              >
                Ouvrir
              </Button>
            </CardContent>
          </Card>
        ))}
      </div>
      <div className="hidden overflow-x-auto rounded-lg border md:block">
        <table className="w-full text-sm">
          <thead className="bg-muted/60 text-left">
            <tr>
              {[
                "Société",
                "Code",
                "Contact",
                "Téléphone",
                "Ville",
                "ICE",
                "Tarif",
                "Statut",
                "Dernière activité",
              ].map((h) => (
                <th key={h} className="px-3 py-3 font-semibold">
                  {h}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {rows.map((row) => (
              <tr
                key={row.id}
                className="cursor-pointer border-t hover:bg-muted/40"
                onClick={() =>
                  void router.navigate({
                    to: "/facolub/customers/$customerId",
                    params: { customerId: row.id },
                  })
                }
              >
                <td className="px-3 py-3 font-semibold">
                  <span className="inline-flex items-center gap-2">
                    <Building2 className="size-4 text-muted-foreground" />
                    {row.company_name}
                  </span>
                </td>
                <td className="px-3 py-3">{row.customer_code ?? "—"}</td>
                <td className="px-3 py-3">{row.contact_person ?? "—"}</td>
                <td className="px-3 py-3">{row.phone ?? "—"}</td>
                <td className="px-3 py-3">{row.city ?? "—"}</td>
                <td className="px-3 py-3">{row.ice ?? "—"}</td>
                <td className="px-3 py-3">{label(row.default_price_category)}</td>
                <td className="px-3 py-3">
                  <StatusBadge status={row.is_active ? "Active" : "Inactive"} />
                </td>
                <td className="px-3 py-3">{date(row.last_activity)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {!rows.length && (
        <div className="rounded-lg border border-dashed p-12 text-center text-muted-foreground">
          Aucun client ne correspond aux filtres.
        </div>
      )}
    </>
  );
}

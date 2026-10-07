import { useRouter } from "@tanstack/react-router";
import { useServerFn } from "@tanstack/react-start";
import { Pencil, Plus, Truck } from "lucide-react";
import { useState, type FormEvent } from "react";

import { EmptyState, PageHeader } from "@/components/app/facolub-ui";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { useLanguage } from "@/lib/i18n/use-language";
import { saveSupplierFn } from "@/lib/receiving/functions";
import type { SupplierAdminData } from "@/lib/receiving/types";
import type { Supplier } from "@/types/database";

export function SupplierAdmin({ data }: { data: SupplierAdminData }) {
  const { t } = useLanguage();
  const [editing, setEditing] = useState<Supplier | null>(null);
  const [open, setOpen] = useState(false);
  const startCreate = () => {
    setEditing(null);
    setOpen(true);
  };
  const startEdit = (supplier: Supplier) => {
    setEditing(supplier);
    setOpen(true);
  };

  return (
    <>
      <div className="flex items-start justify-between gap-4">
        <PageHeader
          title="Suppliers"
          description="Maintain the minimal supplier directory used by receiving."
        />
        <Button onClick={startCreate}>
          <Plus /> {t("New supplier")}
        </Button>
      </div>

      {data.suppliers.length ? (
        <div className="overflow-x-auto border bg-card">
          <table className="w-full text-sm">
            <thead className="border-b bg-muted/50 text-left text-xs uppercase text-muted-foreground">
              <tr>
                <th className="px-4 py-3">{t("Supplier")}</th>
                <th className="px-4 py-3">{t("Contact")}</th>
                <th className="px-4 py-3">{t("State")}</th>
                <th className="px-4 py-3 text-right">{t("Edit")}</th>
              </tr>
            </thead>
            <tbody>
              {data.suppliers.map((supplier) => (
                <tr key={supplier.id} className="border-b last:border-0">
                  <td className="px-4 py-3 font-bold">{supplier.name}</td>
                  <td className="px-4 py-3 text-muted-foreground">
                    <p>{supplier.phone ?? "—"}</p>
                    <p>{supplier.email ?? "—"}</p>
                  </td>
                  <td className="px-4 py-3 font-semibold">
                    {t(supplier.is_active ? "Active" : "Inactive")}
                  </td>
                  <td className="px-4 py-3 text-right">
                    <Button variant="ghost" size="sm" onClick={() => startEdit(supplier)}>
                      <Pencil /> {t("Edit")}
                    </Button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : (
        <EmptyState
          title="No suppliers"
          description="Create the first supplier, or keep using an optional free-text supplier name."
          icon={Truck}
        />
      )}

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{t(editing ? "Edit supplier" : "New supplier")}</DialogTitle>
            <DialogDescription>
              {t("Operational contact data only. Purchasing prices are not stored here.")}
            </DialogDescription>
          </DialogHeader>
          <SupplierForm supplier={editing} onDone={() => setOpen(false)} />
        </DialogContent>
      </Dialog>
    </>
  );
}

function SupplierForm({ supplier, onDone }: { supplier: Supplier | null; onDone: () => void }) {
  const router = useRouter();
  const saveSupplier = useServerFn(saveSupplierFn);
  const { t } = useLanguage();
  const [name, setName] = useState(supplier?.name ?? "");
  const [phone, setPhone] = useState(supplier?.phone ?? "");
  const [email, setEmail] = useState(supplier?.email ?? "");
  const [address, setAddress] = useState(supplier?.address ?? "");
  const [isActive, setIsActive] = useState(supplier?.is_active ?? true);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState("");

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    setPending(true);
    setError("");
    try {
      await saveSupplier({
        data: { id: supplier?.id ?? "", name, phone, email, address, isActive },
      });
      await router.invalidate();
      onDone();
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : t("Unable to save supplier"));
      setPending(false);
    }
  };

  return (
    <form onSubmit={submit} className="space-y-4">
      <div className="space-y-2">
        <Label>{t("Name")}</Label>
        <Input
          required
          maxLength={200}
          value={name}
          onChange={(event) => setName(event.target.value)}
        />
      </div>
      <div className="grid gap-4 sm:grid-cols-2">
        <div className="space-y-2">
          <Label>{t("Phone")}</Label>
          <Input maxLength={80} value={phone} onChange={(event) => setPhone(event.target.value)} />
        </div>
        <div className="space-y-2">
          <Label>{t("Email")}</Label>
          <Input
            type="email"
            maxLength={320}
            value={email}
            onChange={(event) => setEmail(event.target.value)}
          />
        </div>
      </div>
      <div className="space-y-2">
        <Label>{t("Address")}</Label>
        <Textarea
          maxLength={1000}
          value={address}
          onChange={(event) => setAddress(event.target.value)}
        />
      </div>
      <label className="flex items-center gap-3 text-sm font-bold">
        <input
          type="checkbox"
          checked={isActive}
          onChange={(event) => setIsActive(event.target.checked)}
          className="size-4"
        />
        {t("Active supplier")}
      </label>
      {error && <p className="text-sm font-semibold text-danger">{error}</p>}
      <div className="flex justify-end gap-2">
        <Button type="button" variant="outline" onClick={onDone}>
          {t("Cancel")}
        </Button>
        <Button disabled={pending}>{pending ? t("Saving…") : t("Save supplier")}</Button>
      </div>
    </form>
  );
}

import { useMemo, useState } from "react";
import { PageHeader } from "@/components/app/facolub-ui";
import { Input } from "@/components/ui/input";
import type { DispatchHistoryRow } from "@/lib/dispatch/types";

export function DispatchHistory({ rows }: { rows: DispatchHistoryRow[] }) {
  const [query, setQuery] = useState("");
  const [status, setStatus] = useState("");
  const visible = useMemo(
    () =>
      rows.filter(
        (r) =>
          (!status || r.status === status) &&
          (!query ||
            `${r.dispatch_number} ${r.destination_name} ${r.employee_name}`
              .toLowerCase()
              .includes(query.toLowerCase())),
      ),
    [rows, query, status],
  );
  return (
    <>
      <PageHeader
        eyebrow="Dispatch"
        title="Loading history"
        description="Physical loading events, employees, vehicles, and stock traceability."
      />
      <div className="mb-5 grid gap-3 border bg-card p-4 sm:grid-cols-2">
        <Input
          placeholder="Search number, destination, employee"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
        />
        <select
          className="h-10 border bg-background px-3"
          value={status}
          onChange={(e) => setStatus(e.target.value)}
        >
          <option value="">All statuses</option>
          <option value="draft">Draft</option>
          <option value="confirmed">Confirmed</option>
          <option value="cancelled">Cancelled</option>
        </select>
      </div>
      <div className="overflow-x-auto border bg-card">
        <table className="w-full text-sm">
          <thead className="bg-secondary text-left text-xs uppercase">
            <tr>
              <th className="p-3">Dispatch</th>
              <th className="p-3">Date</th>
              <th className="p-3">Destination</th>
              <th className="p-3">Loaded</th>
              <th className="p-3">Vehicle</th>
              <th className="p-3">Employee</th>
              <th className="p-3">Status</th>
            </tr>
          </thead>
          <tbody className="divide-y">
            {visible.map((r) => (
              <tr key={r.id}>
                <td className="p-3 font-black">
                  <a className="text-primary hover:underline" href={`/facolub/dispatch/${r.id}`}>
                    {r.dispatch_number ?? "Draft"}
                  </a>
                </td>
                <td className="p-3">{r.dispatch_date}</td>
                <td className="p-3">{r.destination_name}</td>
                <td className="p-3 font-bold">{r.total_loaded}</td>
                <td className="p-3">{r.vehicle_registration || "—"}</td>
                <td className="p-3">{r.employee_name}</td>
                <td className="p-3">{r.status}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  );
}

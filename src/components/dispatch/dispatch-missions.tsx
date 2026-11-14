import { useServerFn } from "@tanstack/react-start";
import { History, MapPin, PackageCheck, Play, Truck } from "lucide-react";
import { useState } from "react";
import { PageHeader } from "@/components/app/facolub-ui";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { createDispatchDraftFn } from "@/lib/dispatch/functions";
import type { DispatchMission } from "@/lib/dispatch/types";

export function DispatchMissions({
  data,
}: {
  data: { missions: DispatchMission[]; locations: Array<{ id: string; name: string }> };
}) {
  const create = useServerFn(createDispatchDraftFn);
  const [locationId, setLocationId] = useState(data.locations[0]?.id ?? "");
  const [pending, setPending] = useState("");
  const [error, setError] = useState("");
  async function start(orderId: string) {
    setPending(orderId);
    setError("");
    try {
      const dispatch = await create({ data: { orderId, locationId } });
      window.location.href = `/facolub/dispatch/${dispatch.id}`;
    } catch (e) {
      setError(e instanceof Error ? e.message : "Unable to start loading");
      setPending("");
    }
  }
  return (
    <>
      <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <PageHeader
          eyebrow="Load / Send"
          title="Loading missions"
          description="Record the real quantity physically loaded. Orders and documents do not move stock."
        />
        <Button asChild variant="outline">
          <a href="/facolub/dispatch/history">
            <History />
            History
          </a>
        </Button>
      </div>
      <section className="mb-5 border bg-card p-4">
        <label className="text-xs font-black uppercase text-muted-foreground">
          Dispatch stock location
        </label>
        <select
          className="mt-2 h-11 w-full border bg-background px-3 sm:max-w-sm"
          value={locationId}
          onChange={(e) => setLocationId(e.target.value)}
        >
          {data.locations.map((x) => (
            <option key={x.id} value={x.id}>
              {x.name}
            </option>
          ))}
        </select>
      </section>
      {error && (
        <p
          role="alert"
          className="mb-4 border border-danger/30 bg-danger-soft p-3 text-sm font-semibold text-danger"
        >
          {error}
        </p>
      )}
      <div className="grid gap-4 lg:grid-cols-2">
        {data.missions.map((m) => (
          <article key={m.order_id} className="border bg-card p-5 shadow-sm">
            <div className="flex items-start justify-between gap-3">
              <div>
                <p className="text-xs font-black uppercase text-primary">{m.order_number}</p>
                <h2 className="mt-1 text-lg font-black">{m.destination_name}</h2>
                <p className="mt-1 flex items-center gap-1 text-sm text-muted-foreground">
                  <MapPin className="size-4" />
                  {m.destination_city || "Destination on order"}
                </p>
              </div>
              <Badge variant="secondary">
                {m.remaining_lines} line{m.remaining_lines === 1 ? "" : "s"}
              </Badge>
            </div>
            <div className="mt-5 grid grid-cols-2 gap-3 border-y py-4">
              <div>
                <p className="text-xs uppercase text-muted-foreground">Remaining</p>
                <p className="text-2xl font-black">{Number(m.remaining_total).toLocaleString()}</p>
              </div>
              <div>
                <p className="text-xs uppercase text-muted-foreground">Order date</p>
                <p className="mt-1 font-bold">{m.order_date}</p>
              </div>
            </div>
            <div className="mt-4">
              {m.draft_dispatch_id ? (
                <Button asChild className="w-full" size="lg">
                  <a href={`/facolub/dispatch/${m.draft_dispatch_id}`}>
                    <PackageCheck />
                    Continue draft
                  </a>
                </Button>
              ) : (
                <Button
                  className="w-full"
                  size="lg"
                  disabled={!locationId || pending === m.order_id}
                  onClick={() => void start(m.order_id)}
                >
                  <Play />
                  {pending === m.order_id ? "Starting…" : "Start loading"}
                </Button>
              )}
            </div>
          </article>
        ))}
        {data.missions.length === 0 && (
          <div className="col-span-full border border-dashed p-10 text-center">
            <Truck className="mx-auto size-9 text-muted-foreground" />
            <p className="mt-3 font-black">No loading mission is currently pending.</p>
          </div>
        )}
      </div>
    </>
  );
}

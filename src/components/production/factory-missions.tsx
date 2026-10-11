import { Link, useRouter } from "@tanstack/react-router";
import { useServerFn } from "@tanstack/react-start";
import { ArrowRight, Factory, LoaderCircle, Play } from "lucide-react";
import { useState } from "react";
import { EmptyState, StatusBadge } from "@/components/app/facolub-ui";
import { Button } from "@/components/ui/button";
import { prepareAndStartProductionFn } from "@/lib/production/functions";
import { productionStatusLabels, type ProductionMission } from "@/lib/production/types";

export function FactoryMissionList({ missions }: { missions: ProductionMission[] }) {
  const router = useRouter();
  const start = useServerFn(prepareAndStartProductionFn);
  const [pending, setPending] = useState("");
  const [error, setError] = useState("");

  const startMission = async (mission: ProductionMission) => {
    if (pending) return;
    setPending(mission.plan_id);
    setError("");
    try {
      const result = await start({
        data: { planId: mission.plan_id, executionId: mission.execution_id },
      });
      await router.navigate({
        to: "/facolub/production/$executionId",
        params: { executionId: result.executionId },
      });
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Unable to start production");
    } finally {
      setPending("");
    }
  };

  if (!missions.length)
    return (
      <EmptyState
        title="No production missions today"
        description="Reserved production assigned to you will appear here."
        icon={Factory}
      />
    );

  return (
    <div className="space-y-3">
      {error && (
        <p className="border border-danger/30 bg-danger-soft p-3 text-sm text-danger">{error}</p>
      )}
      {missions.map((mission) => {
        const actionable = mission.execution_status === "to_do";
        const canOpen = Boolean(mission.execution_id);
        return (
          <article
            key={`${mission.plan_id}-${mission.product_name}-${mission.format_name}`}
            className="border border-border bg-card p-4 shadow-sm"
          >
            <div className="flex items-start gap-3">
              <div className="grid size-11 shrink-0 place-items-center rounded-md bg-secondary text-primary">
                <Factory className="size-5" />
              </div>
              <div className="min-w-0 flex-1">
                <div className="flex flex-wrap items-start justify-between gap-2">
                  <div>
                    <p className="text-[11px] font-black uppercase text-primary">
                      Priority {mission.priority ?? "—"} · {mission.plan_number}
                    </p>
                    <h3 className="font-black">
                      {mission.product_name} — {mission.format_name}
                    </h3>
                  </div>
                  <StatusBadge status={productionStatusLabels[mission.execution_status]} />
                </div>
                <p className="mt-2 text-sm text-muted-foreground">
                  {mission.planned_cartons ?? "—"} cartons · {mission.planned_bottles} bottles ·
                  Materials reserved
                </p>
                <div className="mt-4 flex flex-wrap gap-2">
                  {actionable ? (
                    <Button
                      onClick={() => void startMission(mission)}
                      disabled={Boolean(pending)}
                      className="min-h-11 flex-1 sm:flex-none"
                    >
                      {pending === mission.plan_id ? (
                        <LoaderCircle className="animate-spin" />
                      ) : (
                        <Play />
                      )}
                      Start production
                    </Button>
                  ) : canOpen ? (
                    <Button asChild className="min-h-11 flex-1 sm:flex-none">
                      <Link
                        to="/facolub/production/$executionId"
                        params={{ executionId: mission.execution_id! }}
                      >
                        Open execution <ArrowRight />
                      </Link>
                    </Button>
                  ) : null}
                </div>
              </div>
            </div>
          </article>
        );
      })}
    </div>
  );
}

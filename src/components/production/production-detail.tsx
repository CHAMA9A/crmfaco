import { Link, useRouter } from "@tanstack/react-router";
import { useServerFn } from "@tanstack/react-start";
import {
  AlertTriangle,
  ArrowLeft,
  CheckCircle2,
  ClipboardCheck,
  LoaderCircle,
  Play,
  RotateCcw,
} from "lucide-react";
import { useMemo, useState, type FormEvent } from "react";
import { PageHeader, StatusBadge } from "@/components/app/facolub-ui";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { useAuthenticatedUser } from "@/lib/auth/context";
import {
  calculateProductionCompletionFn,
  completeProductionExecutionFn,
  reportProductionIssueFn,
  resolveProductionIssueFn,
  startProductionExecutionFn,
} from "@/lib/production/functions";
import {
  productionStatusLabels,
  type ProductionActual,
  type ProductionCompletionPreview,
  type ProductionExecutionPayload,
} from "@/lib/production/types";
import type { PlanningQuantityMode, ProductionIssueCategory } from "@/types/database";

const issueLabels: Record<ProductionIssueCategory, string> = {
  missing_stock: "Missing stock",
  damaged_material: "Damaged material",
  machine_issue: "Machine issue",
  wrong_quantity: "Wrong quantity",
  other: "Other",
};

export function ProductionDetail({ data }: { data: ProductionExecutionPayload }) {
  const router = useRouter();
  const { profile } = useAuthenticatedUser();
  const start = useServerFn(startProductionExecutionFn);
  const calculate = useServerFn(calculateProductionCompletionFn);
  const complete = useServerFn(completeProductionExecutionFn);
  const report = useServerFn(reportProductionIssueFn);
  const resolve = useServerFn(resolveProductionIssueFn);
  const execution = data.execution;
  const [pending, setPending] = useState("");
  const [error, setError] = useState("");
  const [showIssue, setShowIssue] = useState(false);
  const [preview, setPreview] = useState<ProductionCompletionPreview | null>(null);
  const [comment, setComment] = useState(execution.comment ?? "");
  const [actuals, setActuals] = useState<ProductionActual[]>(() =>
    data.items.map(({ item }) => ({
      executionItemId: item.id,
      quantity: item.actual_cartons ?? item.planned_cartons ?? item.planned_bottles,
      mode: item.planned_cartons ? "cartons" : "bottles",
    })),
  );
  const unresolvedIssue = useMemo(
    () => [...data.issues].reverse().find((issue) => !issue.resolved_at),
    [data.issues],
  );
  const stockItems = useMemo(
    () => new Map(data.stock_items.map((item) => [item.id, item])),
    [data.stock_items],
  );

  const run = async (label: string, action: () => Promise<unknown>) => {
    if (pending) return;
    setPending(label);
    setError("");
    try {
      await action();
      await router.invalidate();
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Unable to update production");
    } finally {
      setPending("");
    }
  };

  const updateActual = (
    id: string,
    field: "quantity" | "mode",
    value: number | PlanningQuantityMode,
  ) => {
    setPreview(null);
    setActuals((current) =>
      current.map((actual) =>
        actual.executionItemId === id ? { ...actual, [field]: value } : actual,
      ),
    );
  };

  const calculatePreview = () =>
    run("preview", async () => {
      setPreview(await calculate({ data: { executionId: execution.id, actuals } }));
    });

  const confirmCompletion = () => {
    if (!preview) return;
    if (
      !window.confirm(
        "Confirm these actual quantities? Stock consumption and finished output will be posted atomically.",
      )
    )
      return;
    void run("complete", () => complete({ data: { executionId: execution.id, actuals, comment } }));
  };

  const submitIssue = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    void run("issue", () =>
      report({
        data: {
          executionId: execution.id,
          category: String(form.get("category")) as ProductionIssueCategory,
          description: String(form.get("description") ?? ""),
        },
      }),
    );
  };

  return (
    <>
      <Button asChild variant="ghost" className="mb-3 -ml-3">
        <Link to="/facolub/production">
          <ArrowLeft /> Back to production
        </Link>
      </Button>
      <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <PageHeader
          eyebrow="Production execution"
          title={execution.execution_number}
          description={`${data.plan.plan_number} · ${new Date(`${data.plan.production_date}T00:00:00`).toLocaleDateString()}`}
        />
        <StatusBadge status={productionStatusLabels[execution.status]} />
      </div>

      {error && (
        <p className="mb-5 border border-danger/30 bg-danger-soft p-3 text-sm text-danger">
          {error}
        </p>
      )}

      {execution.status === "blocked" && unresolvedIssue && (
        <section className="mb-5 border-l-4 border-danger bg-danger-soft p-5">
          <div className="flex gap-3">
            <AlertTriangle className="mt-0.5 size-5 shrink-0 text-danger" />
            <div className="flex-1">
              <p className="text-xs font-black uppercase text-danger">Production blocked</p>
              <h2 className="mt-1 font-black">{issueLabels[unresolvedIssue.category]}</h2>
              <p className="mt-1 text-sm">{unresolvedIssue.description}</p>
              {profile.role !== "factory" && (
                <ResolveIssue
                  pending={pending === "resolve"}
                  onResolve={(note) =>
                    void run("resolve", () =>
                      resolve({
                        data: {
                          issueId: unresolvedIssue.id,
                          targetStatus: "in_progress",
                          resolutionNote: note,
                        },
                      }),
                    )
                  }
                />
              )}
            </div>
          </div>
        </section>
      )}

      <div className="grid gap-5 xl:grid-cols-[minmax(0,1.5fr)_340px]">
        <main className="space-y-5">
          {data.items.map(({ item, plan_item: planItem, resolutions }) => (
            <section key={item.id} className="border bg-card p-5 shadow-sm">
              <div className="flex flex-wrap items-start justify-between gap-3 border-b pb-4">
                <div>
                  <p className="text-xs font-black uppercase text-primary">Production line</p>
                  <h2 className="mt-1 text-xl font-black">
                    {planItem.product_name_snapshot} — {planItem.format_name_snapshot}
                  </h2>
                </div>
                <p className="text-sm font-bold">
                  Planned: {item.planned_cartons ?? "—"} cartons · {item.planned_bottles} bottles
                </p>
              </div>

              {execution.status === "in_progress" && (
                <div className="mt-5">
                  <label className="text-sm font-bold" htmlFor={`quantity-${item.id}`}>
                    Actual quantity produced
                  </label>
                  <div className="mt-2 grid grid-cols-[minmax(0,1fr)_130px] gap-2">
                    <Input
                      id={`quantity-${item.id}`}
                      type="number"
                      min="1"
                      step="1"
                      value={
                        actuals.find((actual) => actual.executionItemId === item.id)?.quantity ?? ""
                      }
                      onChange={(event) =>
                        updateActual(item.id, "quantity", Number(event.target.value))
                      }
                    />
                    <select
                      value={
                        actuals.find((actual) => actual.executionItemId === item.id)?.mode ??
                        "bottles"
                      }
                      onChange={(event) =>
                        updateActual(item.id, "mode", event.target.value as PlanningQuantityMode)
                      }
                      className="h-9 rounded-md border border-input bg-background px-3 text-sm"
                    >
                      <option value="cartons">Cartons</option>
                      <option value="bottles">Bottles</option>
                    </select>
                  </div>
                </div>
              )}

              {execution.status === "done" && (
                <div className="mt-5 grid gap-3 sm:grid-cols-3">
                  <Metric label="Actual bottles" value={item.actual_bottles ?? 0} />
                  <Metric label="Actual cartons" value={item.actual_cartons ?? 0} />
                  <Metric
                    label="Variance"
                    value={(item.actual_bottles ?? 0) - item.planned_bottles}
                  />
                </div>
              )}

              {resolutions.length > 0 && (
                <div className="mt-5 overflow-x-auto border-t pt-4">
                  <table className="w-full min-w-[560px] text-left text-sm">
                    <thead className="text-xs uppercase text-muted-foreground">
                      <tr>
                        <th className="pb-2">Material</th>
                        <th>Reserved</th>
                        <th>Consumed</th>
                        <th>Released</th>
                      </tr>
                    </thead>
                    <tbody>
                      {resolutions.map((resolution) => (
                        <tr key={resolution.id} className="border-t">
                          <td className="py-3 font-bold">
                            {stockItems.get(resolution.stock_item_id)?.name ??
                              resolution.stock_item_id}
                          </td>
                          <td>{resolution.original_quantity}</td>
                          <td className="font-bold">{resolution.consumed_quantity}</td>
                          <td>{resolution.released_quantity}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </section>
          ))}

          {execution.status === "in_progress" && preview && (
            <CompletionPreview preview={preview} data={data} />
          )}

          {data.issues.length > 0 && (
            <section className="border bg-card p-5 shadow-sm">
              <h2 className="font-black">Problems & resolutions</h2>
              <div className="mt-4 space-y-3">
                {[...data.issues].reverse().map((issue) => (
                  <article
                    key={issue.id}
                    className="border-l-4 border-warning bg-muted/40 p-3 text-sm"
                  >
                    <p className="font-bold">{issueLabels[issue.category]}</p>
                    <p className="mt-1 text-muted-foreground">{issue.description}</p>
                    {issue.resolved_at && (
                      <p className="mt-2 text-success">
                        Resolved: {issue.resolution_note || "No note"}
                      </p>
                    )}
                  </article>
                ))}
              </div>
            </section>
          )}

          {data.movements.length > 0 && (
            <section className="border bg-card p-5 shadow-sm">
              <h2 className="font-black">Linked stock movements</h2>
              <div className="mt-4 overflow-x-auto">
                <table className="w-full min-w-[640px] text-left text-sm">
                  <thead className="text-xs uppercase text-muted-foreground">
                    <tr>
                      <th className="pb-2">Item</th>
                      <th>Movement</th>
                      <th>Direction</th>
                      <th>Quantity</th>
                      <th>Time</th>
                    </tr>
                  </thead>
                  <tbody>
                    {data.movements.map((movement) => (
                      <tr key={movement.id} className="border-t">
                        <td className="py-3 font-bold">
                          {stockItems.get(movement.stock_item_id)?.name ?? movement.stock_item_id}
                        </td>
                        <td>{movement.movement_type.replaceAll("_", " ")}</td>
                        <td className="uppercase">{movement.direction}</td>
                        <td>
                          {movement.quantity} {stockItems.get(movement.stock_item_id)?.unit ?? ""}
                        </td>
                        <td>{new Date(movement.created_at).toLocaleString()}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </section>
          )}
        </main>

        <aside className="space-y-4 xl:sticky xl:top-24 xl:self-start">
          <section className="border bg-card p-5 shadow-sm">
            <p className="text-xs font-black uppercase text-primary">Actions</p>
            <div className="mt-4 grid gap-2">
              {execution.status === "to_do" && (
                <Button
                  className="min-h-11"
                  disabled={Boolean(pending)}
                  onClick={() =>
                    void run("start", () => start({ data: { executionId: execution.id } }))
                  }
                >
                  {pending === "start" ? <LoaderCircle className="animate-spin" /> : <Play />} Start
                  production
                </Button>
              )}
              {execution.status === "in_progress" && (
                <>
                  <Button
                    className="min-h-11"
                    disabled={Boolean(pending)}
                    onClick={() => void calculatePreview()}
                  >
                    {pending === "preview" ? (
                      <LoaderCircle className="animate-spin" />
                    ) : (
                      <ClipboardCheck />
                    )}{" "}
                    Preview completion
                  </Button>
                  <Button
                    variant="outline"
                    className="min-h-11"
                    onClick={() => setShowIssue((value) => !value)}
                  >
                    <AlertTriangle /> Report a problem
                  </Button>
                </>
              )}
              {preview && execution.status === "in_progress" && (
                <Button
                  className="min-h-11 bg-success text-white hover:bg-success/90"
                  disabled={Boolean(pending)}
                  onClick={confirmCompletion}
                >
                  {pending === "complete" ? (
                    <LoaderCircle className="animate-spin" />
                  ) : (
                    <CheckCircle2 />
                  )}{" "}
                  Confirm completion
                </Button>
              )}
            </div>
          </section>

          <section className="border bg-card p-5 shadow-sm">
            <p className="text-xs font-black uppercase text-primary">Timeline</p>
            <dl className="mt-3 space-y-3 text-sm">
              <Info
                label="Started"
                value={execution.started_at ? new Date(execution.started_at).toLocaleString() : "—"}
              />
              <Info
                label="Completed"
                value={
                  execution.completed_at ? new Date(execution.completed_at).toLocaleString() : "—"
                }
              />
            </dl>
          </section>

          {showIssue && execution.status === "in_progress" && (
            <form onSubmit={submitIssue} className="border border-warning/40 bg-warning-soft p-5">
              <h2 className="font-black">Report a problem</h2>
              <select
                name="category"
                className="mt-4 h-10 w-full rounded-md border bg-background px-3 text-sm"
                required
              >
                {Object.entries(issueLabels).map(([value, label]) => (
                  <option key={value} value={value}>
                    {label}
                  </option>
                ))}
              </select>
              <textarea
                name="description"
                rows={4}
                maxLength={2000}
                required
                placeholder="Describe what happened"
                className="mt-3 w-full rounded-md border bg-background p-3 text-sm"
              />
              <Button
                type="submit"
                variant="destructive"
                className="mt-3 w-full"
                disabled={Boolean(pending)}
              >
                Block and report
              </Button>
            </form>
          )}

          {execution.status === "in_progress" && (
            <section className="border bg-card p-5 shadow-sm">
              <label className="text-sm font-bold" htmlFor="completion-comment">
                Completion note
              </label>
              <textarea
                id="completion-comment"
                value={comment}
                onChange={(event) => setComment(event.target.value)}
                rows={3}
                maxLength={2000}
                className="mt-2 w-full rounded-md border bg-background p-3 text-sm"
                placeholder="Optional"
              />
            </section>
          )}
        </aside>
      </div>
    </>
  );
}

function Metric({ label, value }: { label: string; value: number }) {
  return (
    <div className="bg-secondary p-3">
      <p className="text-xs font-bold uppercase text-muted-foreground">{label}</p>
      <p className="mt-1 text-xl font-black">{value}</p>
    </div>
  );
}

function CompletionPreview({
  preview,
  data,
}: {
  preview: ProductionCompletionPreview;
  data: ProductionExecutionPayload;
}) {
  return (
    <section className="border-2 border-primary bg-card p-5 shadow-sm">
      <p className="text-xs font-black uppercase text-primary">Authoritative preview</p>
      <h2 className="mt-1 text-xl font-black">Stock impact before confirmation</h2>
      <div className="mt-4 space-y-4">
        {preview.items.map((item) => (
          <div key={item.execution_item_id} className="border p-4">
            <p className="text-xs font-black uppercase text-muted-foreground">
              {
                data.items.find(({ item: candidate }) => candidate.id === item.execution_item_id)
                  ?.plan_item.product_name_snapshot
              }{" "}
              ·{" "}
              {
                data.items.find(({ item: candidate }) => candidate.id === item.execution_item_id)
                  ?.plan_item.format_name_snapshot
              }
            </p>
            <p className="mt-1 text-sm">
              Planned: {item.planned_cartons ?? "—"} cartons · {item.planned_bottles} bottles
            </p>
            <p className="font-bold">
              Output: {item.actual_bottles} bottles · {item.actual_cartons} cartons
            </p>
            <p className="mt-1 text-sm text-success">
              Finished output:{" "}
              {data.items.find(({ item: candidate }) => candidate.id === item.execution_item_id)
                ?.plan_item.output_item_name_snapshot ?? "Finished product"}{" "}
              +{item.actual_bottles}
            </p>
            <div className="mt-3 overflow-x-auto">
              <table className="w-full min-w-[560px] text-left text-sm">
                <thead className="text-xs uppercase text-muted-foreground">
                  <tr>
                    <th className="pb-2">Material</th>
                    <th>Reserved</th>
                    <th>Consumed</th>
                    <th>Released</th>
                  </tr>
                </thead>
                <tbody>
                  {item.materials.map((material) => (
                    <tr key={material.requirement_id} className="border-t">
                      <td className="py-3 font-bold">{material.name}</td>
                      <td>
                        {material.reserved_quantity} {material.unit}
                      </td>
                      <td>
                        {material.consumed_quantity} {material.unit}
                      </td>
                      <td>
                        {material.released_quantity} {material.unit}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        ))}
      </div>
    </section>
  );
}

function ResolveIssue({
  pending,
  onResolve,
}: {
  pending: boolean;
  onResolve: (note: string) => void;
}) {
  const [note, setNote] = useState("");
  return (
    <div className="mt-4">
      <Input
        value={note}
        onChange={(event) => setNote(event.target.value)}
        placeholder="Resolution note"
        maxLength={2000}
      />
      <Button className="mt-2" disabled={pending || !note.trim()} onClick={() => onResolve(note)}>
        {pending ? <LoaderCircle className="animate-spin" /> : <RotateCcw />} Resolve and resume
      </Button>
    </div>
  );
}

function Info({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <dt className="text-xs uppercase text-muted-foreground">{label}</dt>
      <dd className="mt-1 font-semibold">{value}</dd>
    </div>
  );
}

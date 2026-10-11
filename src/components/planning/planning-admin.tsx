import { useRouter } from "@tanstack/react-router";
import { useServerFn } from "@tanstack/react-start";
import { LoaderCircle, Save, Settings2 } from "lucide-react";
import { useState, type ReactNode } from "react";
import { PageHeader } from "@/components/app/facolub-ui";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  configurePackagingRuleFn,
  savePlanningProductFn,
  saveProductFormatFn,
  saveProductionRecipeFn,
} from "@/lib/planning/functions";
import type { PlanningAdminData } from "@/lib/planning/types";
import type { ProductionComponentRole } from "@/types/database";

const roles: ProductionComponentRole[] = ["prepared_bottle", "bulk_lubricant", "seal", "carton"];
export function PlanningAdmin({ data }: { data: PlanningAdminData }) {
  const router = useRouter();
  const saveProduct = useServerFn(savePlanningProductFn);
  const saveFormat = useServerFn(saveProductFormatFn);
  const configureRule = useServerFn(configurePackagingRuleFn);
  const saveRecipe = useServerFn(saveProductionRecipeFn);
  const [productName, setProductName] = useState("");
  const [productCode, setProductCode] = useState("");
  const [linkProduct, setLinkProduct] = useState("");
  const [linkFormat, setLinkFormat] = useState("");
  const [recipeFormat, setRecipeFormat] = useState("");
  const [outputId, setOutputId] = useState("");
  const [components, setComponents] = useState<Record<ProductionComponentRole, string>>({
    prepared_bottle: "",
    bulk_lubricant: "",
    seal: "",
    carton: "",
    other: "",
  });
  const [quantities, setQuantities] = useState<Record<ProductionComponentRole, string>>({
    prepared_bottle: "1",
    bulk_lubricant: "1",
    seal: "1",
    carton: "1",
    other: "1",
  });
  const [pending, setPending] = useState(false);
  const [error, setError] = useState("");
  const run = async (work: () => Promise<unknown>) => {
    setPending(true);
    setError("");
    try {
      await work();
      await router.invalidate();
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Unable to save configuration");
    } finally {
      setPending(false);
    }
  };
  const itemsFor = (role: ProductionComponentRole) =>
    data.stockItems.filter((item) => item.category === role);
  return (
    <>
      <PageHeader
        eyebrow="Settings"
        title="Production planning"
        description="Configure products, carton capacities, component mappings, and versioned production recipes."
      />
      <div className="space-y-6">
        <section className="grid gap-5 lg:grid-cols-2">
          <Card title="Products">
            <div className="grid gap-3 sm:grid-cols-[150px_1fr_auto]">
              <Input
                placeholder="Code"
                value={productCode}
                onChange={(e) => setProductCode(e.target.value)}
              />
              <Input
                placeholder="Product name"
                value={productName}
                onChange={(e) => setProductName(e.target.value)}
              />
              <Button
                disabled={pending || !productName.trim()}
                onClick={() =>
                  void run(() =>
                    saveProduct({
                      data: { productId: null, code: productCode, name: productName },
                    }),
                  )
                }
              >
                <Save /> Save
              </Button>
            </div>
            <ul className="mt-4 grid gap-2 sm:grid-cols-2">
              {data.products.map((product) => (
                <li key={product.id} className="border bg-background p-3 font-semibold">
                  {product.name}
                  <span className="ml-2 text-xs text-muted-foreground">{product.code}</span>
                </li>
              ))}
            </ul>
          </Card>
          <Card title="Product formats">
            <div className="grid gap-3 sm:grid-cols-[1fr_1fr_auto]">
              <Select
                value={linkProduct}
                onChange={setLinkProduct}
                label="Select product"
                options={data.products.map((p) => [p.id, p.name])}
              />
              <Select
                value={linkFormat}
                onChange={setLinkFormat}
                label="Select format"
                options={data.formats.map((f) => [f.id, f.name])}
              />
              <Button
                disabled={pending || !linkProduct || !linkFormat}
                onClick={() =>
                  void run(() =>
                    saveFormat({ data: { productId: linkProduct, formatId: linkFormat } }),
                  )
                }
              >
                Link
              </Button>
            </div>
            <ul className="mt-4 grid gap-2 sm:grid-cols-2">
              {data.productFormats.map((item) => (
                <li key={item.id} className="border bg-background p-3 font-semibold">
                  {item.product_name} · {item.format_name}
                </li>
              ))}
            </ul>
          </Card>
        </section>
        <Card title="Carton capacities">
          <div className="grid gap-3 sm:grid-cols-3">
            {data.formats.map((format) => {
              const rule = data.rules.find((item) => item.format_id === format.id);
              return (
                <Capacity
                  key={`${format.id}-${rule?.id}`}
                  formatId={format.id}
                  name={format.name}
                  initial={rule?.bottles_per_carton ?? 1}
                  disabled={pending}
                  onSave={(value) =>
                    run(() =>
                      configureRule({ data: { formatId: format.id, bottlesPerCarton: value } }),
                    )
                  }
                />
              );
            })}
          </div>
        </Card>
        <Card title="Production recipe">
          <div className="grid gap-4 sm:grid-cols-2">
            <label className="space-y-2">
              <Label>Product / format</Label>
              <Select
                value={recipeFormat}
                onChange={setRecipeFormat}
                label="Select product format"
                options={data.productFormats.map((item) => [
                  item.id,
                  `${item.product_name} · ${item.format_name}`,
                ])}
              />
            </label>
            <label className="space-y-2">
              <Label>Finished product output</Label>
              <Select
                value={outputId}
                onChange={setOutputId}
                label="Select output"
                options={data.stockItems
                  .filter((item) => item.category === "finished_product")
                  .map((item) => [item.id, item.name])}
              />
            </label>
          </div>
          <div className="mt-5 grid gap-3 md:grid-cols-2">
            {roles.map((role) => (
              <div key={role} className="grid grid-cols-[1fr_110px] gap-2 border bg-background p-3">
                <label className="space-y-1">
                  <Label className="capitalize">{role.replaceAll("_", " ")}</Label>
                  <Select
                    value={components[role]}
                    onChange={(value) =>
                      setComponents((current) => ({ ...current, [role]: value }))
                    }
                    label="Select item"
                    options={itemsFor(role).map((item) => [item.id, item.name])}
                  />
                </label>
                <label className="space-y-1">
                  <Label>Per bottle</Label>
                  <Input
                    type="number"
                    min="0.001"
                    step="0.001"
                    disabled={role === "carton"}
                    value={quantities[role]}
                    onChange={(e) =>
                      setQuantities((current) => ({ ...current, [role]: e.target.value }))
                    }
                  />
                </label>
              </div>
            ))}
          </div>
          <div className="mt-4 flex justify-end">
            <Button
              size="lg"
              disabled={
                pending || !recipeFormat || !outputId || roles.some((role) => !components[role])
              }
              onClick={() =>
                void run(() =>
                  saveRecipe({
                    data: {
                      recipeId: null,
                      productFormatId: recipeFormat,
                      outputStockItemId: outputId,
                      components: roles.map((role) => ({
                        role,
                        stockItemId: components[role],
                        quantityPerBottle: Number(quantities[role]),
                      })),
                    },
                  }),
                )
              }
            >
              {pending ? <LoaderCircle className="animate-spin" /> : <Save />} Save recipe
            </Button>
          </div>
        </Card>
        <Card title="Recipe versions">
          <div className="grid gap-3 lg:grid-cols-2">
            {data.recipes.map((recipe) => {
              const pf = data.productFormats.find((item) => item.id === recipe.product_format_id);
              return (
                <article key={recipe.id} className="border bg-background p-4">
                  <div className="flex justify-between">
                    <strong>
                      {pf ? `${pf.product_name} · ${pf.format_name}` : "Unknown format"}
                    </strong>
                    <span className={recipe.is_active ? "text-success" : "text-muted-foreground"}>
                      v{recipe.version} · {recipe.is_active ? "Active" : "Inactive"}
                    </span>
                  </div>
                  <ul className="mt-3 space-y-1 text-sm">
                    {recipe.components.map((component) => (
                      <li key={component.id} className="flex justify-between">
                        <span>{component.stock_item_name}</span>
                        <span>
                          {component.component_role.replaceAll("_", " ")} ×{" "}
                          {component.quantity_per_bottle}
                        </span>
                      </li>
                    ))}
                  </ul>
                </article>
              );
            })}
          </div>
        </Card>
        {error && (
          <p className="border border-danger/30 bg-danger-soft p-4 font-semibold text-danger">
            {error}
          </p>
        )}
      </div>
    </>
  );
}

function Card({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="border bg-card p-5 shadow-sm">
      <h2 className="mb-4 flex items-center gap-2 border-b pb-3 font-black">
        <Settings2 className="size-5 text-primary" />
        {title}
      </h2>
      {children}
    </section>
  );
}
function Select({
  value,
  onChange,
  label,
  options,
}: {
  value: string;
  onChange: (value: string) => void;
  label: string;
  options: string[][];
}) {
  return (
    <select
      className="h-10 w-full rounded-md border bg-card px-3"
      value={value}
      onChange={(e) => onChange(e.target.value)}
    >
      <option value="">{label}</option>
      {options.map(([id, name]) => (
        <option key={id} value={id}>
          {name}
        </option>
      ))}
    </select>
  );
}
function Capacity({
  formatId,
  name,
  initial,
  disabled,
  onSave,
}: {
  formatId: string;
  name: string;
  initial: number;
  disabled: boolean;
  onSave: (value: number) => Promise<unknown>;
}) {
  const [value, setValue] = useState(String(initial));
  return (
    <div className="border bg-background p-4">
      <Label htmlFor={formatId}>{name}</Label>
      <div className="mt-2 flex gap-2">
        <Input
          id={formatId}
          type="number"
          min="1"
          step="1"
          value={value}
          onChange={(e) => setValue(e.target.value)}
        />
        <Button disabled={disabled || Number(value) < 1} onClick={() => void onSave(Number(value))}>
          Save
        </Button>
      </div>
    </div>
  );
}

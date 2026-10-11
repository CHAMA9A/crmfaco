import { createFileRoute } from "@tanstack/react-router";
import { RecipeAdmin } from "@/components/preparation/recipe-admin";
import { getRecipeAdminDataFn } from "@/lib/preparation/functions";

export const Route = createFileRoute("/facolub/settings/prepared-bottles")({
  loader: () => getRecipeAdminDataFn(),
  component: RecipeAdminRoute,
});
function RecipeAdminRoute() {
  return <RecipeAdmin data={Route.useLoaderData()} />;
}

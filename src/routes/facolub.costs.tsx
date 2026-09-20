import { createFileRoute } from "@tanstack/react-router";
import { PlaceholderPage } from "@/components/app/pages";
export const Route = createFileRoute("/facolub/costs")({
  head: () => ({
    meta: [
      { title: "Costs — FACOLUB" },
      { name: "description", content: "Costs workspace for FACOLUB internal operations." },
      { property: "og:title", content: "Costs — FACOLUB" },
      { property: "og:description", content: "Costs workspace for FACOLUB internal operations." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
  component: () => <PlaceholderPage module="costs" />,
});

import { createFileRoute } from "@tanstack/react-router";
import { PlaceholderPage } from "@/components/app/pages";
export const Route = createFileRoute("/facolub/analytics")({
  head: () => ({
    meta: [
      { title: "Analytics — FACOLUB" },
      { name: "description", content: "Analytics workspace for FACOLUB internal operations." },
      { property: "og:title", content: "Analytics — FACOLUB" },
      {
        property: "og:description",
        content: "Analytics workspace for FACOLUB internal operations.",
      },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
  component: () => <PlaceholderPage module="analytics" />,
});

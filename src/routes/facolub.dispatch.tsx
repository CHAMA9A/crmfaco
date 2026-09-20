import { createFileRoute } from "@tanstack/react-router";
import { PlaceholderPage } from "@/components/app/pages";
export const Route = createFileRoute("/facolub/dispatch")({
  head: () => ({
    meta: [
      { title: "Dispatch — FACOLUB" },
      { name: "description", content: "Dispatch workspace for FACOLUB internal operations." },
      { property: "og:title", content: "Dispatch — FACOLUB" },
      {
        property: "og:description",
        content: "Dispatch workspace for FACOLUB internal operations.",
      },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
  component: () => <PlaceholderPage module="dispatch" />,
});

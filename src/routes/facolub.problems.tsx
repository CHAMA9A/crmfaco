import { createFileRoute } from "@tanstack/react-router";
import { PlaceholderPage } from "@/components/app/pages";
export const Route = createFileRoute("/facolub/problems")({
  head: () => ({
    meta: [
      { title: "Problems — FACOLUB" },
      { name: "description", content: "Problems workspace for FACOLUB internal operations." },
      { property: "og:title", content: "Problems — FACOLUB" },
      {
        property: "og:description",
        content: "Problems workspace for FACOLUB internal operations.",
      },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
  component: () => <PlaceholderPage module="problems" />,
});

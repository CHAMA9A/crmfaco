import { createFileRoute } from "@tanstack/react-router";
import { ManagementHomePage } from "@/components/app/pages";
export const Route = createFileRoute("/facolub/")({
  head: () => ({
    meta: [
      { title: "FACOLUB Operations — SOMA Lubrifiants" },
      { name: "description", content: "FACOLUB management operations overview." },
      { property: "og:title", content: "FACOLUB Operations" },
      { property: "og:description", content: "FACOLUB management operations overview." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
  component: ManagementHomePage,
});

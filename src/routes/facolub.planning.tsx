import { Outlet, createFileRoute } from "@tanstack/react-router";
export const Route = createFileRoute("/facolub/planning")({
  head: () => ({
    meta: [
      { title: "Planning — FACOLUB" },
      { name: "description", content: "Planning workspace for FACOLUB internal operations." },
      { property: "og:title", content: "Planning — FACOLUB" },
      {
        property: "og:description",
        content: "Planning workspace for FACOLUB internal operations.",
      },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
  component: Outlet,
});

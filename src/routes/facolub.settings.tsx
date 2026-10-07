import { Outlet, createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/facolub/settings")({
  head: () => ({
    meta: [
      { title: "Settings — FACOLUB" },
      { name: "description", content: "Settings workspace for FACOLUB internal operations." },
      { property: "og:title", content: "Settings — FACOLUB" },
      {
        property: "og:description",
        content: "Settings workspace for FACOLUB internal operations.",
      },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
  component: () => <Outlet />,
});

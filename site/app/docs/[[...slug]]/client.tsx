"use client";

import dynamic from "next/dynamic";
import Link from "next/link";
import { useRouter } from "next/navigation";

const DocsApp = dynamic(
  () => import("@arach/dewey").then((mod) => mod.DocsApp),
  {
    ssr: false,
    loading: () => (
      <div className="flex min-h-screen items-center justify-center bg-canvas text-secondary">
        Loading docs…
      </div>
    ),
  },
);

function NextLink({ href, children, ...props }: React.ComponentProps<"a">) {
  return (
    <Link href={href || "#"} {...props}>
      {children}
    </Link>
  );
}

interface DocsClientPageProps {
  docs: Record<string, string>;
  navigation: Array<{ title: string; items: Array<{ id: string; title: string }> }>;
  initialPage: string;
  pageTitle: string;
}

export default function DocsClientPage({
  docs,
  navigation,
  initialPage,
  pageTitle,
}: DocsClientPageProps) {
  const router = useRouter();

  return (
    <DocsApp
      config={{
        name: "Vox",
        tagline: pageTitle,
        basePath: "/docs",
        homeUrl: "/",
        navigation,
        layout: {
          sidebar: true,
          toc: true,
          header: true,
          prevNext: true,
        },
      }}
      docs={docs}
      currentPage={initialPage}
      onNavigate={(pageId) => router.push(`/docs/${pageId}`)}
      providerProps={{
        theme: "warm",
        defaultDark: false,
        components: {
          Link: NextLink,
        },
      }}
    />
  );
}

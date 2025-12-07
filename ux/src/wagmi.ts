import { getDefaultConfig } from "@rainbow-me/rainbowkit";
import { base, sepolia, baseSepolia } from "wagmi/chains";

export const config = getDefaultConfig({
  appName: "Ontra finance",
  projectId: "aaf7401b57e2657344cf0c05cddab898",
  chains: [
    base,
    baseSepolia,
    sepolia,
    ...(process.env.NEXT_PUBLIC_ENABLE_TESTNETS === "true" ? [sepolia] : []),
  ],
  ssr: true,
});

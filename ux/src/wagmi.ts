import { getDefaultConfig } from "@rainbow-me/rainbowkit";
import { metaMaskWallet, rabbyWallet } from "@rainbow-me/rainbowkit/wallets";
import { sepolia } from "wagmi/chains";

export const config = getDefaultConfig({
  appName: "Ontra finance",
  projectId: "aaf7401b57e2657344cf0c05cddab898",
  chains: [
    sepolia,
    ...(process.env.NEXT_PUBLIC_ENABLE_TESTNETS === "true" ? [sepolia] : []),
  ],
  wallets: [
    {
      groupName: "Recommended",
      wallets: [metaMaskWallet, rabbyWallet],
    },
  ],
  ssr: true,
});

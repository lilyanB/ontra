"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { ConnectButton } from "@rainbow-me/rainbowkit";

export function Header() {
  const pathname = usePathname();

  const navItems = [
    { name: "Swap", path: "/" },
    { name: "Orders", path: "/orders" },
    { name: "About", path: "/about" },
  ];

  return (
    <header className="header">
      <div className="header-content">
        <div className="header-left">
          <div className="logo">
            <span className="logo-icon">🦄</span>
            <span className="logo-text">Ontra</span>
          </div>
          <nav className="nav">
            {navItems.map((item) => (
              <Link
                key={item.path}
                href={item.path}
                className={`nav-link ${pathname === item.path ? "active" : ""}`}
              >
                {item.name}
              </Link>
            ))}
          </nav>
        </div>
        <div className="header-right">
          <ConnectButton />
        </div>
      </div>
    </header>
  );
}

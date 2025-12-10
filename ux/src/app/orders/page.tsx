"use client";

import { useState, useMemo, useEffect } from "react";
import { useAccount } from "wagmi";
import { parseUnits, formatUnits } from "viem";
import {
  useCreateTrailingStop,
  useApproveToken,
  useTokenAllowance,
} from "@/hooks/useOntraContract";
import { TOKENS, POOL_KEY } from "@/config/contracts";
import Toast from "@/components/Toast";
import { useUserOrders } from "@/hooks/useUserOrders";

interface TrailingStopOrder {
  id: string;
  token: string;
  amount: string;
  trailingPercent: string;
  status: "active" | "triggered" | "cancelled";
  createdAt: string;
  owner?: string;
}

function OrdersPage() {
  const [activeTab, setActiveTab] = useState<"my-orders" | "contract-orders">(
    "my-orders"
  );

  const [toast, setToast] = useState<{
    message: string;
    type: "pending" | "success" | "error";
  } | null>(null);

  const [myOrders, setMyOrders] = useState<TrailingStopOrder[]>([
    {
      id: "1",
      token: "WETH",
      amount: "1.5",
      trailingPercent: "10",
      status: "active",
      createdAt: "2025-12-01",
    },
    {
      id: "2",
      token: "USDC",
      amount: "5000",
      trailingPercent: "10",
      status: "active",
      createdAt: "2025-12-03",
    },
  ]);

  const [contractOrders, setContractOrders] = useState<TrailingStopOrder[]>([
    {
      id: "c1",
      token: "WETH",
      amount: "2.3",
      trailingPercent: "5",
      status: "active",
      createdAt: "2025-11-28",
      owner: "0x1234...5678",
    },
    {
      id: "c2",
      token: "USDC",
      amount: "5000",
      trailingPercent: "5",
      status: "active",
      createdAt: "2025-11-30",
      owner: "0xabcd...efgh",
    },
    {
      id: "c3",
      token: "WETH",
      amount: "0.1",
      trailingPercent: "15",
      status: "triggered",
      createdAt: "2025-12-05",
      owner: "0x9876...5432",
    },
  ]);

  const [formData, setFormData] = useState({
    tokenToDeposit: "",
    amount: "",
    trailingPercent: "5",
  });

  // Simulated pool prices (to be replaced with real contract data)
  // Price represents how much of the other token you get per 1 unit of the selected token
  const poolPrices = {
    USDC: { pair: "WETH", rate: 0.00040816 }, // 1 USDC = 0.00040816 WETH
    WETH: { pair: "USDC", rate: 2450.0 }, // 1 WETH = 2450 USDC
  };

  // Calculate liquidation prices based on trailing percentage
  const liquidationPrices = useMemo(() => {
    if (!formData.tokenToDeposit) {
      return {
        5: { price: "0.00", pair: "" },
        10: { price: "0.00", pair: "" },
        15: { price: "0.00", pair: "" },
      };
    }

    const poolPrice =
      poolPrices[formData.tokenToDeposit as keyof typeof poolPrices];
    const currentRate = poolPrice.rate;

    const calculate = (percent: number) => {
      const liquidationRate = currentRate * (1 - percent / 100);
      return {
        price: liquidationRate.toLocaleString("en-US", {
          minimumFractionDigits: 2,
          maximumFractionDigits: 6,
        }),
        pair: poolPrice.pair,
      };
    };

    return {
      5: calculate(5),
      10: calculate(10),
      15: calculate(15),
    };
  }, [formData.tokenToDeposit]);
  const getStatusColor = (status: string) => {
    switch (status) {
      case "active":
        return "#4ade80";
      case "triggered":
        return "#fbbf24";
      case "cancelled":
        return "#ef4444";
      default:
        return "#6b7280";
    }
  };

  const handleCancelOrder = (orderId: string) => {
    setMyOrders(
      myOrders.map((order) =>
        order.id === orderId
          ? { ...order, status: "cancelled" as const }
          : order
      )
    );
  };

  const { address } = useAccount();
  const {
    createTrailingStop,
    hash: createHash,
    isPending: isCreating,
    isConfirming: isCreatingConfirming,
    isConfirmed: isCreated,
    isConfirmError: isCreateError,
    error: createError,
    receiptError: createReceiptError,
  } = useCreateTrailingStop();

  const {
    approveToken,
    isPending: isApproving,
    isConfirming: isApprovingConfirming,
    isConfirmed: isApproved,
    isConfirmError: isApproveError,
  } = useApproveToken();

  const { allowance, refetch: refetchAllowance } = useTokenAllowance(
    formData.tokenToDeposit as "USDC" | "WETH" | undefined,
    address
  );

  const { userOrders, isLoading: isLoadingOrders, refetch: refetchOrders } = useUserOrders();

  // Refetch allowance when approval is confirmed
  useEffect(() => {
    if (isApproved) {
      refetchAllowance();
    }
  }, [isApproved, refetchAllowance]);

  // Show approval status
  useEffect(() => {
    if (isApprovingConfirming) {
      setToast({ message: "Approval transaction pending...", type: "pending" });
    }
  }, [isApprovingConfirming]);

  useEffect(() => {
    if (isApproved) {
      setToast({ message: "Token approved successfully!", type: "success" });
    }
  }, [isApproved]);

  useEffect(() => {
    if (isApproveError) {
      setToast({ message: "Approval transaction failed", type: "error" });
    }
  }, [isApproveError]);

  // Show creation status
  useEffect(() => {
    if (isCreatingConfirming) {
      setToast({ message: "Creating trailing stop order...", type: "pending" });
    }
  }, [isCreatingConfirming]);

  // Reset form and refetch orders when order is created
  useEffect(() => {
    if (isCreated) {
      setToast({
        message: "Trailing stop order created successfully!",
        type: "success",
      });
      setFormData({ tokenToDeposit: "", amount: "", trailingPercent: "5" });
      // Refetch orders from contract
      setTimeout(() => refetchOrders(), 2000); // Wait 2s for blockchain confirmation
    }
  }, [isCreated, refetchOrders]);

  useEffect(() => {
    if (isCreateError) {
      const errorMsg = createReceiptError?.message || "Transaction reverted";
      const shortHash = createHash
        ? `${createHash.slice(0, 10)}...${createHash.slice(-8)}`
        : "";
      setToast({
        message: `${errorMsg}${
          shortHash ? ` (${shortHash})` : ""
        }. Check Sepolia scan for details.`,
        type: "error",
      });
    }
  }, [isCreateError, createReceiptError, createHash]);

  // Show errors
  useEffect(() => {
    if (createError) {
      setToast({ message: `Error: ${createError.message}`, type: "error" });
    }
  }, [createError]);

  const needsApproval = useMemo(() => {
    if (!formData.tokenToDeposit || !formData.amount || !allowance) {
      return false;
    }
    const token = TOKENS[formData.tokenToDeposit as "USDC" | "WETH"];
    const amountBigInt = parseUnits(formData.amount, token.decimals);
    return allowance < amountBigInt;
  }, [formData.tokenToDeposit, formData.amount, allowance]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    if (!address) {
      alert("Please connect your wallet");
      return;
    }

    if (needsApproval) {
      // First approve the token
      await approveToken(
        formData.tokenToDeposit as "USDC" | "WETH",
        formData.amount
      );
    } else {
      // Create the trailing stop order
      await createTrailingStop(
        formData.tokenToDeposit as "USDC" | "WETH",
        formData.amount,
        formData.trailingPercent as "5" | "10" | "15"
      );
    }
  };

  // Convert blockchain orders to display format
  const blockchainOrders: TrailingStopOrder[] = useMemo(() => {
    console.log("User orders from contract:", userOrders);
    return userOrders.map((order) => {
      const tierPercent = order.tier === 0 ? "5" : order.tier === 1 ? "10" : "15";
      const token = order.isLong ? "USDC" : "WETH";
      const tokenDecimals = order.isLong ? 6 : 18;
      
      // Calculate user's amount based on shares
      let amount = "0";
      if (order.poolData) {
        const totalShares = order.isLong 
          ? order.poolData.totalSharesLong 
          : order.poolData.totalSharesShort;
        const totalTokens = order.isLong 
          ? order.poolData.totalToken0Long 
          : order.poolData.totalToken1Short;
        
        if (totalShares > BigInt(0)) {
          const userAmount = (order.shares * totalTokens) / totalShares;
          amount = formatUnits(userAmount, tokenDecimals);
        }
      }

      const isExecuted = order.isLong 
        ? (order.poolData?.executedToken1 ?? BigInt(0)) > BigInt(0)
        : (order.poolData?.executedToken0 ?? BigInt(0)) > BigInt(0);

      return {
        id: `${order.tier}-${order.isLong}-${order.epoch}`,
        token,
        amount,
        trailingPercent: tierPercent,
        status: isExecuted ? "triggered" : "active",
        createdAt: new Date().toISOString().split("T")[0],
      } as TrailingStopOrder;
    });
  }, [userOrders]);

  const currentOrders = activeTab === "my-orders" ? blockchainOrders : contractOrders;

  return (
    <>
      {toast && (
        <Toast
          message={toast.message}
          type={toast.type}
          onClose={() => setToast(null)}
        />
      )}
      <div className="page-container">
        <div className="orders-layout">
          <div className="create-order-section">
            <div className="form-container">
              <h2>Create Trailing Stop Loss</h2>
              <p className="form-description">
                Set up a new trailing stop loss order to protect your position
              </p>

              {formData.tokenToDeposit && (
                <div className="current-price-display">
                  <span className="price-label">
                    Current {formData.tokenToDeposit} Price:
                  </span>
                  <span className="price-value">
                    {poolPrices[
                      formData.tokenToDeposit as keyof typeof poolPrices
                    ].rate.toLocaleString("en-US", {
                      minimumFractionDigits: 2,
                      maximumFractionDigits: 6,
                    })}{" "}
                    {
                      poolPrices[
                        formData.tokenToDeposit as keyof typeof poolPrices
                      ].pair
                    }
                  </span>
                </div>
              )}

              <form onSubmit={handleSubmit} className="order-form">
                <div className="form-group">
                  <label htmlFor="tokenToDeposit">Token to Deposit</label>
                  <select
                    id="tokenToDeposit"
                    value={formData.tokenToDeposit}
                    onChange={(e) =>
                      setFormData({
                        ...formData,
                        tokenToDeposit: e.target.value,
                      })
                    }
                    required
                  >
                    <option value="">Select a token</option>
                    <option value="USDC">USDC</option>
                    <option value="WETH">WETH</option>
                  </select>
                </div>

                <div className="form-group">
                  <label htmlFor="amount">Amount</label>
                  <input
                    type="number"
                    id="amount"
                    step="0.000001"
                    value={formData.amount}
                    onChange={(e) =>
                      setFormData({ ...formData, amount: e.target.value })
                    }
                    placeholder="0.0"
                    required
                  />
                </div>

                <div className="form-group">
                  <label>Trailing Percentage (%)</label>
                  <div className="radio-group">
                    <label className="radio-option">
                      <input
                        type="radio"
                        name="trailingPercent"
                        value="5"
                        checked={formData.trailingPercent === "5"}
                        onChange={(e) =>
                          setFormData({
                            ...formData,
                            trailingPercent: e.target.value,
                          })
                        }
                      />
                      <div className="radio-content">
                        <span className="radio-percent">5%</span>
                        {formData.tokenToDeposit && (
                          <span className="liquidation-price">
                            Liq: {liquidationPrices[5].price}{" "}
                            {liquidationPrices[5].pair}
                          </span>
                        )}
                      </div>
                    </label>
                    <label className="radio-option">
                      <input
                        type="radio"
                        name="trailingPercent"
                        value="10"
                        checked={formData.trailingPercent === "10"}
                        onChange={(e) =>
                          setFormData({
                            ...formData,
                            trailingPercent: e.target.value,
                          })
                        }
                      />
                      <div className="radio-content">
                        <span className="radio-percent">10%</span>
                        {formData.tokenToDeposit && (
                          <span className="liquidation-price">
                            Liq: {liquidationPrices[10].price}{" "}
                            {liquidationPrices[10].pair}
                          </span>
                        )}
                      </div>
                    </label>
                    <label className="radio-option">
                      <input
                        type="radio"
                        name="trailingPercent"
                        value="15"
                        checked={formData.trailingPercent === "15"}
                        onChange={(e) =>
                          setFormData({
                            ...formData,
                            trailingPercent: e.target.value,
                          })
                        }
                      />
                      <div className="radio-content">
                        <span className="radio-percent">15%</span>
                        {formData.tokenToDeposit && (
                          <span className="liquidation-price">
                            Liq: {liquidationPrices[15].price}{" "}
                            {liquidationPrices[15].pair}
                          </span>
                        )}
                      </div>
                    </label>
                  </div>
                  <span className="form-hint">
                    Stop loss will trigger when price drops by this percentage
                    from the highest price
                  </span>
                </div>

                <button
                  type="submit"
                  className="submit-button"
                  disabled={
                    isApproving ||
                    isApprovingConfirming ||
                    isCreating ||
                    isCreatingConfirming ||
                    !address
                  }
                >
                  {!address
                    ? "Connect Wallet"
                    : isApproving || isApprovingConfirming
                    ? "Approving..."
                    : isCreating || isCreatingConfirming
                    ? "Creating Order..."
                    : needsApproval
                    ? "Approve Token"
                    : "Create Order"}
                </button>
                {createError && (
                  <div
                    style={{
                      color: "#ef4444",
                      marginTop: "0.5rem",
                      fontSize: "0.875rem",
                    }}
                  >
                    Error: {createError.message}
                  </div>
                )}
              </form>
            </div>
          </div>

          <div className="orders-list-section">
            <div className="orders-header">
              <h1>Trailing Stop Loss Orders</h1>
              <p className="orders-description">
                Monitor and manage all trailing stop loss orders
              </p>
            </div>

            <div className="tabs-container">
              <button
                className={`tab ${activeTab === "my-orders" ? "active" : ""}`}
                onClick={() => setActiveTab("my-orders")}
              >
                My Orders ({myOrders.length})
              </button>
              <button
                className={`tab ${
                  activeTab === "contract-orders" ? "active" : ""
                }`}
                onClick={() => setActiveTab("contract-orders")}
              >
                Contract Orders ({contractOrders.length})
              </button>
            </div>

            {currentOrders.length === 0 ? (
              <div className="empty-state">
                <div className="empty-icon">📊</div>
                <h3>No orders yet</h3>
                <p>
                  {activeTab === "my-orders"
                    ? "Create your first trailing stop loss order"
                    : "No orders on the contract"}
                </p>
              </div>
            ) : (
              <div className="orders-list">
                {currentOrders.map((order) => (
                  <div key={order.id} className="order-card">
                    <div className="order-row">
                      <div className="order-info">
                        <div className="order-token">{order.token}</div>
                        <div className="order-amount">
                          Amount: {order.amount}
                        </div>
                        {order.owner && (
                          <div className="order-owner">
                            Owner: {order.owner}
                          </div>
                        )}
                      </div>
                      <div
                        className="order-status"
                        style={{ color: getStatusColor(order.status) }}
                      >
                        {order.status.toUpperCase()}
                      </div>
                    </div>

                    <div className="order-details">
                      <div className="order-detail-item">
                        <span className="detail-label">Trailing %</span>
                        <span className="detail-value">
                          {order.trailingPercent}%
                        </span>
                      </div>
                      <div className="order-detail-item">
                        <span className="detail-label">Created</span>
                        <span className="detail-value">{order.createdAt}</span>
                      </div>
                    </div>

                    {order.status === "active" && activeTab === "my-orders" && (
                      <div className="order-actions">
                        <button
                          onClick={() => handleCancelOrder(order.id)}
                          className="cancel-button"
                        >
                          Cancel Order
                        </button>
                      </div>
                    )}
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      </div>
    </>
  );
}

export default OrdersPage;

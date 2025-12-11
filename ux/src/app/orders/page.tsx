"use client";

import { useState, useMemo, useEffect } from "react";
import { useAccount } from "wagmi";
import { parseUnits, formatUnits } from "viem";
import {
  useCreateTrailingStop,
  useApproveToken,
  useTokenAllowance,
  useTierExecutionPrices,
} from "@/hooks/useOntraContract";
import { TOKENS, POOL_KEY } from "@/config/contracts";
import Toast from "@/components/Toast";
import { useUserOrders } from "@/hooks/useUserOrders";
import { getExecutionPrice, formatCurrentPrice } from "@/utils/tickToPrice";

interface TrailingStopOrder {
  id: string;
  token: string;
  amount: string;
  trailingPercent: string;
  status: "active" | "triggered" | "cancelled";
  createdAt: string;
  owner?: string;
  executionPrice?: string;
}

function OrdersPage() {
  const [activeTab, setActiveTab] = useState<"my-orders" | "contract-orders">(
    "my-orders"
  );

  const [toast, setToast] = useState<{
    message: string;
    type: "pending" | "success" | "error";
  } | null>(null);

  const [formData, setFormData] = useState({
    tokenToDeposit: "",
    amount: "",
    trailingPercent: "5",
  });

  // Get real execution prices from contract for each tier
  const { tier5, tier10, tier15, currentTick, isLong } = useTierExecutionPrices(
    formData.tokenToDeposit as "USDC" | "WETH" | undefined
  );

  // Format current price from contract tick
  const currentPrice = useMemo(() => {
    if (!formData.tokenToDeposit || currentTick === undefined) {
      return "Loading...";
    }
    return formatCurrentPrice(
      currentTick,
      formData.tokenToDeposit as "USDC" | "WETH"
    );
  }, [currentTick, formData.tokenToDeposit]);

  // Format execution prices for display
  const executionPrices = useMemo(() => {
    if (!formData.tokenToDeposit) {
      return {
        5: "N/A",
        10: "N/A",
        15: "N/A",
      };
    }

    return {
      5: getExecutionPrice(tier5, isLong, currentTick, 5),
      10: getExecutionPrice(tier10, isLong, currentTick, 10),
      15: getExecutionPrice(tier15, isLong, currentTick, 15),
    };
  }, [formData.tokenToDeposit, tier5, tier10, tier15, currentTick, isLong]);

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
    // TODO: Implement cancel order with withdrawTrailingStop
    console.log("Cancel order:", orderId);
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

  const {
    userOrders,
    isLoading: isLoadingOrders,
    refetch: refetchOrders,
  } = useUserOrders();

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
    return userOrders.map((order) => {
      const tierPercent =
        order.tier === 0 ? "5" : order.tier === 1 ? "10" : "15";
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

      // Get execution price from pool data
      const executionPrice = getExecutionPrice(order.poolData, order.isLong);

      return {
        id: `${order.tier}-${order.isLong}-${order.epoch}`,
        token,
        amount,
        trailingPercent: tierPercent,
        status: isExecuted ? "triggered" : "active",
        createdAt: new Date().toISOString().split("T")[0],
        executionPrice,
      } as TrailingStopOrder;
    });
  }, [userOrders]);

  const currentOrders = blockchainOrders;

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
                  <span className="price-value">{currentPrice}</span>
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
                            Exec: {executionPrices[5]}
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
                            Exec: {executionPrices[10]}
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
                            Exec: {executionPrices[15]}
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
              <button className="tab active">
                My Orders ({blockchainOrders.length})
              </button>
            </div>

            {currentOrders.length === 0 ? (
              <div className="empty-state">
                <div className="empty-icon">📊</div>
                <h3>No orders yet</h3>
                <p>Create your first trailing stop loss order</p>
              </div>
            ) : (
              <div className="orders-list">
                {currentOrders.map((order: TrailingStopOrder) => (
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
                        <span className="detail-label">Execution Price</span>
                        <span
                          className="detail-value"
                          style={{ fontWeight: 600, color: "#10b981" }}
                        >
                          {order.executionPrice || "N/A"}
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

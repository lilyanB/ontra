"use client";

import { useState } from "react";

interface TrailingStopOrder {
  id: string;
  token: string;
  amount: string;
  currentPrice: string;
  stopPrice: string;
  trailingPercent: string;
  status: "active" | "triggered" | "cancelled";
  createdAt: string;
}

function OrdersPage() {
  const [orders, setOrders] = useState<TrailingStopOrder[]>([
    {
      id: "1",
      token: "ETH/USDC",
      amount: "1.5",
      currentPrice: "2,450",
      stopPrice: "2,205",
      trailingPercent: "10",
      status: "active",
      createdAt: "2025-12-01",
    },
    {
      id: "2",
      token: "BTC/USDC",
      amount: "0.05",
      currentPrice: "42,000",
      stopPrice: "37,800",
      trailingPercent: "10",
      status: "active",
      createdAt: "2025-12-03",
    },
  ]);

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
    setOrders(
      orders.map((order) =>
        order.id === orderId
          ? { ...order, status: "cancelled" as const }
          : order
      )
    );
  };

  return (
    <div className="page-container">
      <div className="orders-container">
        <div className="orders-header">
          <h1>Trailing Stop Loss Orders</h1>
          <p className="orders-description">
            Manage your trailing stop loss orders to protect your positions
          </p>
        </div>

        {orders.length === 0 ? (
          <div className="empty-state">
            <div className="empty-icon">📊</div>
            <h3>No orders yet</h3>
            <p>Create your first trailing stop loss order</p>
          </div>
        ) : (
          <div className="orders-list">
            {orders.map((order) => (
              <div key={order.id} className="order-card">
                <div className="order-row">
                  <div className="order-info">
                    <div className="order-token">{order.token}</div>
                    <div className="order-amount">Amount: {order.amount}</div>
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
                    <span className="detail-label">Current Price</span>
                    <span className="detail-value">${order.currentPrice}</span>
                  </div>
                  <div className="order-detail-item">
                    <span className="detail-label">Stop Price</span>
                    <span className="detail-value">${order.stopPrice}</span>
                  </div>
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

                {order.status === "active" && (
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
  );
}

export default OrdersPage;

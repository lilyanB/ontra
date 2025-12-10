"use client";

interface ToastProps {
  message: string;
  type: "pending" | "success" | "error";
  onClose: () => void;
}

export default function Toast({ message, type, onClose }: ToastProps) {
  const bgColor = {
    pending: "#3b82f6",
    success: "#10b981",
    error: "#ef4444",
  }[type];

  const icon = {
    pending: "⏳",
    success: "✅",
    error: "❌",
  }[type];

  return (
    <div
      style={{
        position: "fixed",
        top: "20px",
        right: "20px",
        backgroundColor: bgColor,
        color: "white",
        padding: "1rem 1.5rem",
        borderRadius: "8px",
        boxShadow: "0 4px 6px rgba(0, 0, 0, 0.1)",
        zIndex: 1000,
        display: "flex",
        alignItems: "center",
        gap: "0.75rem",
        maxWidth: "400px",
        animation: "slideIn 0.3s ease-out",
      }}
    >
      <span style={{ fontSize: "1.25rem" }}>{icon}</span>
      <span style={{ flex: 1 }}>{message}</span>
      <button
        onClick={onClose}
        style={{
          background: "none",
          border: "none",
          color: "white",
          cursor: "pointer",
          fontSize: "1.25rem",
          padding: "0",
          lineHeight: "1",
        }}
      >
        ×
      </button>
      <style jsx>{`
        @keyframes slideIn {
          from {
            transform: translateX(100%);
            opacity: 0;
          }
          to {
            transform: translateX(0);
            opacity: 1;
          }
        }
      `}</style>
    </div>
  );
}

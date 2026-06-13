"use client";

import { useState, Suspense } from "react";
import { useSearchParams } from "next/navigation";

function LoginForm() {
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const searchParams = useSearchParams();
  const from = searchParams.get("from") ?? "/";

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError("");
    const res = await fetch("/api/auth/login", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ password }),
    });
    if (res.ok) {
      window.location.href = from;
    } else {
      setError("Incorrect password.");
      setLoading(false);
    }
  }

  return (
    <div style={{
      minHeight: "100vh",
      background: "#0d0d0d",
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
      padding: "1.5rem",
      fontFamily: "-apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif",
    }}>
      <div style={{
        background: "#141414",
        border: "1px solid rgba(255,255,255,0.08)",
        borderRadius: "12px",
        padding: "2.5rem 2rem",
        width: "100%",
        maxWidth: "360px",
        textAlign: "center",
      }}>
        <div style={{ fontSize: "2rem", marginBottom: "0.75rem" }}>&#9670;</div>
        <h1 style={{
          color: "#fff", fontSize: "1.4rem",
          fontWeight: 800, marginBottom: "0.5rem",
        }}>LeadFinder</h1>
        <p style={{
          color: "rgba(255,255,255,0.4)",
          fontSize: "13px", marginBottom: "1.75rem",
        }}>Home services lead extraction</p>

        {error && (
          <div style={{
            background: "rgba(232,69,10,0.1)",
            border: "1px solid rgba(232,69,10,0.3)",
            color: "#ff8a5c", fontSize: "13px",
            padding: "10px 14px", marginBottom: "1rem",
            borderRadius: "6px",
          }}>{error}</div>
        )}

        <form onSubmit={handleSubmit} style={{ display: "flex", flexDirection: "column", gap: "10px" }}>
          <input
            type="password"
            placeholder="Enter password"
            value={password}
            onChange={e => setPassword(e.target.value)}
            autoFocus
            required
            style={{
              width: "100%",
              padding: "13px 16px",
              fontSize: "15px",
              border: "1px solid rgba(255,255,255,0.12)",
              background: "#161616",
              color: "#fff",
              outline: "none",
              borderRadius: "6px",
              textAlign: "center",
              boxSizing: "border-box",
            }}
          />
          <button
            type="submit"
            disabled={loading || !password}
            style={{
              width: "100%",
              padding: "13px",
              background: loading || !password ? "rgba(255,255,255,0.1)" : "#e8521a",
              color: loading || !password ? "rgba(255,255,255,0.3)" : "#fff",
              border: "none",
              borderRadius: "6px",
              fontSize: "13px",
              fontWeight: 800,
              textTransform: "uppercase",
              letterSpacing: "0.08em",
              cursor: loading || !password ? "default" : "pointer",
              transition: "background 0.12s",
            }}
          >
            {loading ? "Signing in..." : "Sign in"}
          </button>
        </form>
      </div>
    </div>
  );
}

export default function LoginPage() {
  return (
    <Suspense>
      <LoginForm />
    </Suspense>
  );
}

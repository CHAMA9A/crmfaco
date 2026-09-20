import { Link } from "@tanstack/react-router";
import { useServerFn } from "@tanstack/react-start";
import { ArrowLeft, CheckCircle2, LockKeyhole, Mail, ShieldCheck } from "lucide-react";
import { useEffect, useRef, useState, type FormEvent, type ReactNode } from "react";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  exchangeRecoveryCodeFn,
  requestPasswordResetFn,
  updateRecoveredPasswordFn,
} from "@/lib/auth/functions";

function AuthCard({ children }: { children: ReactNode }) {
  return (
    <main className="grid min-h-screen place-items-center bg-secondary/40 px-5 py-10">
      <section className="w-full max-w-md rounded-xl border bg-background p-6 shadow-sm sm:p-8">
        <div className="mb-8 flex items-center gap-3">
          <div className="grid size-10 place-items-center rounded-md bg-brand text-brand-foreground">
            <span className="font-black">S</span>
          </div>
          <div>
            <p className="font-bold">SOMA Lubrifiants</p>
            <p className="text-xs text-muted-foreground">Secure account recovery</p>
          </div>
        </div>
        {children}
      </section>
    </main>
  );
}

export function ForgotPasswordPage() {
  const requestReset = useServerFn(requestPasswordResetFn);
  const [pending, setPending] = useState(false);
  const [sent, setSent] = useState(false);
  const [error, setError] = useState("");

  const submit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (pending) return;
    setPending(true);
    setError("");
    const form = new FormData(event.currentTarget);
    try {
      await requestReset({ data: { email: String(form.get("email") ?? "") } });
      setSent(true);
    } catch {
      setError("The recovery request could not be completed. Please try again later.");
    } finally {
      setPending(false);
    }
  };

  return (
    <AuthCard>
      <ShieldCheck className="size-6 text-primary" />
      <h1 className="mt-4 text-2xl font-bold">Reset your password</h1>
      {sent ? (
        <div className="mt-6 space-y-5">
          <div className="rounded-lg border border-primary/30 bg-primary/5 p-4">
            <CheckCircle2 className="size-5 text-primary" />
            <p className="mt-3 text-sm leading-6">
              If an account exists for that email address, a password-reset link has been sent.
            </p>
          </div>
          <Link
            to="/login"
            className="inline-flex items-center gap-2 text-sm font-semibold text-primary"
          >
            <ArrowLeft className="size-4" /> Back to sign in
          </Link>
        </div>
      ) : (
        <>
          <p className="mt-2 text-sm leading-6 text-muted-foreground">
            Enter your account email. For security, the response is identical whether or not the
            address exists.
          </p>
          <form onSubmit={submit} className="mt-6 space-y-5">
            <div className="space-y-2">
              <Label htmlFor="recovery-email">Email</Label>
              <div className="relative">
                <Mail className="absolute left-3 top-3 size-4 text-muted-foreground" />
                <Input
                  id="recovery-email"
                  name="email"
                  type="email"
                  autoComplete="email"
                  required
                  className="h-11 pl-10"
                />
              </div>
            </div>
            {error && (
              <p role="alert" className="text-sm font-medium text-danger">
                {error}
              </p>
            )}
            <Button type="submit" size="lg" className="h-12 w-full" disabled={pending}>
              {pending ? "Sending…" : "Send reset link"}
            </Button>
            <Link
              to="/login"
              className="inline-flex items-center gap-2 text-sm font-semibold text-primary"
            >
              <ArrowLeft className="size-4" /> Back to sign in
            </Link>
          </form>
        </>
      )}
    </AuthCard>
  );
}

export function RecoveryCallbackPage({ code }: { code: string | undefined }) {
  const exchangeCode = useServerFn(exchangeRecoveryCodeFn);
  const started = useRef(false);
  const [failed, setFailed] = useState(!code);

  useEffect(() => {
    if (!code || started.current) return;
    started.current = true;
    void exchangeCode({ data: { code } })
      .then((result) => {
        if (result.ok) window.location.replace("/reset-password");
        else setFailed(true);
      })
      .catch(() => setFailed(true));
  }, [code, exchangeCode]);

  return (
    <AuthCard>
      <ShieldCheck className="size-6 text-primary" />
      <h1 className="mt-4 text-2xl font-bold">Verifying recovery link</h1>
      {failed ? (
        <div className="mt-5 space-y-5">
          <p role="alert" className="text-sm leading-6 text-danger">
            This recovery link is invalid or has expired. Request a new link and try again.
          </p>
          <Link
            to="/forgot-password"
            className="text-sm font-semibold text-primary hover:underline"
          >
            Request another link
          </Link>
        </div>
      ) : (
        <p className="mt-3 text-sm text-muted-foreground">
          Please wait while the link is verified…
        </p>
      )}
    </AuthCard>
  );
}

export function ResetPasswordPage() {
  const updatePassword = useServerFn(updateRecoveredPasswordFn);
  const [pending, setPending] = useState(false);
  const [complete, setComplete] = useState(false);
  const [error, setError] = useState("");

  const submit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (pending) return;
    setError("");
    const form = new FormData(event.currentTarget);
    const password = String(form.get("password") ?? "");
    const confirmation = String(form.get("confirmation") ?? "");
    if (password !== confirmation) {
      setError("The passwords do not match.");
      return;
    }

    setPending(true);
    try {
      const result = await updatePassword({ data: { password } });
      if (result.ok) setComplete(true);
      else setError("The recovery session is invalid or has expired. Request a new link.");
    } catch {
      setError("The password could not be updated. Use at least 12 characters and try again.");
    } finally {
      setPending(false);
    }
  };

  return (
    <AuthCard>
      <LockKeyhole className="size-6 text-primary" />
      <h1 className="mt-4 text-2xl font-bold">Choose a new password</h1>
      {complete ? (
        <div className="mt-6 space-y-5">
          <p className="text-sm leading-6">
            Your password has been updated. Sign in with the new password.
          </p>
          <Button asChild className="w-full">
            <Link to="/login">Return to sign in</Link>
          </Button>
        </div>
      ) : (
        <form onSubmit={submit} className="mt-6 space-y-5">
          <div className="space-y-2">
            <Label htmlFor="new-password">New password</Label>
            <Input
              id="new-password"
              name="password"
              type="password"
              autoComplete="new-password"
              minLength={12}
              maxLength={128}
              required
            />
            <p className="text-xs text-muted-foreground">Use at least 12 characters.</p>
          </div>
          <div className="space-y-2">
            <Label htmlFor="confirm-password">Confirm new password</Label>
            <Input
              id="confirm-password"
              name="confirmation"
              type="password"
              autoComplete="new-password"
              minLength={12}
              maxLength={128}
              required
            />
          </div>
          {error && (
            <p role="alert" className="text-sm font-medium text-danger">
              {error}
            </p>
          )}
          <Button type="submit" size="lg" className="h-12 w-full" disabled={pending}>
            {pending ? "Updating…" : "Update password"}
          </Button>
        </form>
      )}
    </AuthCard>
  );
}

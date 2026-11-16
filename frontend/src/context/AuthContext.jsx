import { createContext, useContext, useEffect, useState } from "react";
import { supabase } from "../lib/supabase";
import { flushPendingConsent } from "../lib/legalConsent";
import { promptGoogleIdToken } from "../lib/googleIdentity";

const AuthContext = createContext({});

export function AuthProvider({ children }) {
  const [user, setUser] = useState(null);
  const [loading, setLoading] = useState(() => Boolean(supabase));

  useEffect(() => {
    if (!supabase) return;

    supabase.auth.getSession().then(({ data: { session } }) => {
      setUser(session?.user ?? null);
      setLoading(false);
      // Google dönüşü: bağlantıdaki oturum bu abonelikten önce işlenmiş olabilir.
      if (session?.user) flushPendingConsent(session.user.id);
    });

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, session) => {
      setUser(session?.user ?? null);
      // Bekleyen Google onayı yoksa hiçbir şey yapmaz. Supabase dinleyicide beklemeyi önermez: ayrı tura bırakılır.
      if (session?.user) setTimeout(() => flushPendingConsent(session.user.id), 0);
    });

    return () => subscription.unsubscribe();
  }, []);

  const signUp = async (email, password, fullName) => {
    if (!supabase) return { error: { message: "Supabase not configured" }, needsEmailConfirmation: false };
    const { data, error } = await supabase.auth.signUp({
      email,
      password,
      options: { data: { full_name: fullName } },
    });
    if (error) return { data, error, needsEmailConfirmation: false };
    const session = data?.session;
    const user = data?.user;
    const needsEmailConfirmation = Boolean(user && !session);
    return { data, error: null, needsEmailConfirmation };
  };

  const signIn = async (email, password) => {
    if (!supabase) return { error: { message: "Supabase not configured" } };
    const { data, error } = await supabase.auth.signInWithPassword({
      email,
      password,
    });
    return { data, error };
  };

  /**
   * Google hesabıyla giriş ya da kayıt. Önce sitede açılan Google penceresi (GIS) denenir: "rebiovil.com" ve
   * uygulama adı görünür, oturum sayfadan ayrılmadan açılır (`signedIn: true`). Pencere kapatılırsa
   * `canceled: true`. Pencere gösterilemezse eski yol: sayfa Google'a gider, oturumla `/auth?next=…` adresine döner.
   */
  const signInWithGoogle = async (next = "/dashboard") => {
    if (!supabase) return { error: { message: "Supabase not configured" } };
    const gis = await promptGoogleIdToken();
    if (gis.canceled) return { canceled: true };
    if (gis.idToken) {
      const { data, error } = await supabase.auth.signInWithIdToken({
        provider: "google",
        token: gis.idToken,
        nonce: gis.nonce,
      });
      return { data, error, signedIn: !error };
    }
    const redirectTo = `${window.location.origin}/auth?next=${encodeURIComponent(next)}`;
    const { data, error } = await supabase.auth.signInWithOAuth({
      provider: "google",
      options: { redirectTo, queryParams: { prompt: "select_account" } },
    });
    return { data, error };
  };

  const signOut = async () => {
    if (!supabase) return;
    await supabase.auth.signOut();
    setUser(null);
  };

  const refreshUser = async () => {
    if (!supabase) return;
    const {
      data: { session },
    } = await supabase.auth.getSession();
    setUser(session?.user ?? null);
  };

  return (
    <AuthContext.Provider
      value={{ user, loading, signUp, signIn, signInWithGoogle, signOut, refreshUser }}
    >
      {children}
    </AuthContext.Provider>
  );
}

// eslint-disable-next-line react-refresh/only-export-components -- context hook
export const useAuth = () => useContext(AuthContext);

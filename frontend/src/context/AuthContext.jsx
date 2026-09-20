import { createContext, useContext, useEffect, useState } from "react";
import { supabase } from "../lib/supabase";

const AuthContext = createContext({});

export function AuthProvider({ children }) {
  const [user, setUser] = useState(null);
  const [loading, setLoading] = useState(() => Boolean(supabase));

  useEffect(() => {
    if (!supabase) return;

    supabase.auth.getSession().then(({ data: { session } }) => {
      setUser(session?.user ?? null);
      setLoading(false);
    });

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, session) => {
      setUser(session?.user ?? null);
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
      value={{ user, loading, signUp, signIn, signOut, refreshUser }}
    >
      {children}
    </AuthContext.Provider>
  );
}

// eslint-disable-next-line react-refresh/only-export-components -- context hook
export const useAuth = () => useContext(AuthContext);

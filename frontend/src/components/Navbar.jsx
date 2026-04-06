import { useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { useAuth } from "../context/AuthContext";
import { Leaf, Menu, X, LogOut, Crown } from "lucide-react";
import { useTranslation } from "react-i18next";
import LanguageSelect from "./LanguageSelect";

export default function Navbar() {
  const { user, signOut } = useAuth();
  const navigate = useNavigate();
  const [menuOpen, setMenuOpen] = useState(false);
  const { t } = useTranslation();

  const handleSignOut = async () => {
    await signOut();
    navigate("/");
  };

  return (
    <nav className="sticky top-0 z-50 glass border-b border-gray-100/50">
      <div className="max-w-6xl mx-auto px-4 h-16 flex items-center justify-between">
        <Link to="/" className="flex items-center gap-2 group">
          <div className="w-9 h-9 bg-gradient-to-br from-teal-500 to-teal-600 rounded-xl flex items-center justify-center shadow-lg shadow-teal-500/20 group-hover:shadow-teal-500/40 transition-shadow">
            <Leaf className="w-5 h-5 text-white" />
          </div>
          <span className="text-xl font-bold text-gray-900">Rebi</span>
        </Link>

        {/* Desktop */}
        <div className="hidden md:flex items-center gap-4">
          <LanguageSelect />
          {user ? (
            <>
              <Link
                to="/dashboard"
                className="text-gray-600 hover:text-teal-600 font-medium transition-colors"
              >
                {t("nav.dashboard")}
              </Link>
              <Link
                to="/dashboard/profile"
                className="text-gray-600 hover:text-teal-600 font-medium text-sm"
              >
                {t("nav.profile")}
              </Link>
              <Link
                to="/dashboard/subscribe"
                className="text-amber-700 hover:text-amber-900 font-medium text-sm flex items-center gap-1"
              >
                <Crown className="w-4 h-4" /> {t("nav.plus")}
              </Link>
              <Link
                to="/dashboard/analyze"
                className="btn-primary !py-2 !px-4 !text-sm"
              >
                {t("nav.newAnalyze")}
              </Link>
              <button
                onClick={handleSignOut}
                className="text-gray-400 hover:text-red-500 transition-colors p-2"
                aria-label={t("nav.logout")}
              >
                <LogOut className="w-5 h-5" />
              </button>
            </>
          ) : (
            <Link to="/auth" className="btn-primary !py-2 !px-5 !text-sm">
              {t("nav.login")}
            </Link>
          )}
        </div>

        {/* Mobile Hamburger */}
        <button
          onClick={() => setMenuOpen(!menuOpen)}
          className="md:hidden p-2 text-gray-600"
        >
          {menuOpen ? <X className="w-6 h-6" /> : <Menu className="w-6 h-6" />}
        </button>
      </div>

      {/* Mobile Menu */}
      {menuOpen && (
        <div className="md:hidden border-t border-gray-100 bg-white px-4 py-4 space-y-3">
          <div className="pb-2">
            <LanguageSelect />
          </div>
          {user ? (
            <>
              <Link
                to="/dashboard"
                onClick={() => setMenuOpen(false)}
                className="block py-2 text-gray-700 font-medium"
              >
                {t("nav.dashboard")}
              </Link>
              <Link
                to="/dashboard/profile"
                onClick={() => setMenuOpen(false)}
                className="block py-2 text-gray-700 font-medium"
              >
                {t("nav.profile")}
              </Link>
              <Link
                to="/dashboard/subscribe"
                onClick={() => setMenuOpen(false)}
                className="block py-2 text-amber-700 font-medium"
              >
                {t("nav.plus")}
              </Link>
              <Link
                to="/dashboard/analyze"
                onClick={() => setMenuOpen(false)}
                className="block py-2 text-teal-600 font-medium"
              >
                {t("nav.newAnalyze")}
              </Link>
              <button
                onClick={() => {
                  handleSignOut();
                  setMenuOpen(false);
                }}
                className="block py-2 text-red-500 font-medium"
              >
                {t("nav.logout")}
              </button>
            </>
          ) : (
            <Link
              to="/auth"
              onClick={() => setMenuOpen(false)}
              className="btn-primary w-full"
            >
              {t("nav.login")}
            </Link>
          )}
        </div>
      )}
    </nav>
  );
}

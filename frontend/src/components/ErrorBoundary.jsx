import { Component } from "react";

export default class ErrorBoundary extends Component {
  constructor(props) {
    super(props);
    this.state = { hasError: false, error: null, errorInfo: null };
  }

  static getDerivedStateFromError(error) {
    return { hasError: true, error };
  }

  componentDidCatch(error, errorInfo) {
    console.error("React Error Boundary:", error, errorInfo);
    this.setState({ errorInfo });
  }

  render() {
    if (this.state.hasError) {
      const isDev = import.meta.env.DEV;
      return (
        <div className="min-h-screen flex items-center justify-center bg-teal-50 px-4">
          <div className="bg-white rounded-3xl p-8 max-w-md w-full shadow-lg text-center">
            <div className="w-16 h-16 bg-red-100 rounded-2xl flex items-center justify-center mx-auto mb-4">
              <span className="text-3xl">😥</span>
            </div>
            <h2 className="text-xl font-bold text-gray-900 mb-2">Bir Sorun Oluştu</h2>
            <p className="text-gray-500 text-sm mb-4">Sayfa yüklenirken bir hata meydana geldi.</p>
            {isDev && this.state.error && (
              <div className="text-left bg-red-50 rounded-xl p-3 mb-4 max-h-40 overflow-auto">
                <p className="text-xs font-mono text-red-700 break-words">{this.state.error.toString()}</p>
                {this.state.errorInfo?.componentStack && (
                  <p className="text-[10px] font-mono text-red-500 mt-2 break-words whitespace-pre-wrap">{this.state.errorInfo.componentStack.slice(0, 500)}</p>
                )}
              </div>
            )}
            <div className="flex gap-3 justify-center">
              <button onClick={() => { this.setState({ hasError: false, error: null, errorInfo: null }); }}
                className="bg-gray-200 text-gray-700 px-5 py-2.5 rounded-2xl font-medium text-sm hover:bg-gray-300 transition-colors">
                Tekrar Dene
              </button>
              <button onClick={() => { window.location.href = "/"; }}
                className="bg-teal-600 text-white px-5 py-2.5 rounded-2xl font-medium text-sm hover:bg-teal-700 transition-colors">
                Ana Sayfaya Dön
              </button>
            </div>
          </div>
        </div>
      );
    }
    return this.props.children;
  }
}

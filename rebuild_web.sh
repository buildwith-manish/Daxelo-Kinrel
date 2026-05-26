#!/bin/bash
# Rebuild Flutter web and copy to Next.js public directory
set -e

FLUTTER_APP="/home/z/my-project/Daxelo-Kinrel-App"
PUBLIC_DIR="/home/z/my-project/public/flutter"

echo "🔨 Building Flutter web..."
cd "$FLUTTER_APP"
/home/z/flutter/bin/flutter build web --release

echo "📂 Copying to Next.js public directory..."
rm -rf "$PUBLIC_DIR"
mkdir -p "$PUBLIC_DIR"
cp -r build/web/* "$PUBLIC_DIR/"

echo "🔧 Applying custom Flutter web configuration..."

# 1. Replace index.html with our custom version (no service worker, better loading)
cat > "$PUBLIC_DIR/index.html" << 'HTML'
<!DOCTYPE html>
<html>
<head>
  <base href="/flutter/">
  <meta charset="UTF-8">
  <meta content="IE=Edge" http-equiv="X-UA-Compatible">
  <meta name="description" content="KINREL - Family Relationship Intelligence Platform">
  <meta name="mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-status-bar-style" content="black">
  <meta name="apple-mobile-web-app-title" content="kinrel">
  <link rel="apple-touch-icon" href="icons/Icon-192.png">
  <link rel="icon" type="image/png" href="favicon.png"/>
  <title>KINREL</title>
  <style>
    body { margin: 0; padding: 0; background: #13141E; }
    #loading-indicator {
      position: fixed; inset: 0; display: flex; justify-content: center;
      align-items: center; background: #13141E; color: #F5F0EE;
      font-family: system-ui, sans-serif; flex-direction: column;
      gap: 16px; z-index: 9999;
    }
    .spinner {
      width: 40px; height: 40px; border: 3px solid #333;
      border-top: 3px solid #E8612A; border-radius: 50%;
      animation: spin 1s linear infinite;
    }
    @keyframes spin { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }
  </style>
</head>
<body>
  <div id="loading-indicator">
    <div class="spinner"></div>
    <p style="font-size:14px;opacity:0.8">Loading KINREL...</p>
  </div>
  <script src="flutter.js"></script>
  <script>
    _flutter.buildConfig = BUILD_CONFIG_PLACEHOLDER;
    window.addEventListener('flutter-first-frame', function() {
      var loader = document.getElementById('loading-indicator');
      if (loader) {
        loader.style.opacity = '0';
        loader.style.transition = 'opacity 0.3s ease-out';
        setTimeout(function() { loader.remove(); }, 300);
      }
      if (window.parent !== window) {
        window.parent.postMessage({ type: 'flutter-ready' }, '*');
      }
    });
    _flutter.loader.load();
  </script>
</body>
</html>
HTML

# 2. Extract build config from the original flutter_bootstrap.js and inject it
BUILD_CONFIG=$(grep -o '"engineRevision":"[^"]*","builds":\[.*\]' "$PUBLIC_DIR/flutter_bootstrap.js" | head -1)
if [ -n "$BUILD_CONFIG" ]; then
  BUILD_CONFIG_JSON="{\"${BUILD_CONFIG}}"
  sed -i "s|BUILD_CONFIG_PLACEHOLDER|${BUILD_CONFIG_JSON}|g" "$PUBLIC_DIR/index.html"
  echo "  ✅ Injected build config"
fi

# 3. Remove .env from public assets (served via middleware for security)
rm -f "$PUBLIC_DIR/assets/.env"

echo "✅ Flutter web build copied to $PUBLIC_DIR"
echo "   The Next.js dev server will automatically pick up the changes."

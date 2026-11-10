package fr.tvkosova.app;

import android.app.Activity;
import android.graphics.Bitmap;
import android.os.Bundle;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowManager;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;

/**
 * Ouvre la page TV Kosova en plein écran, sans curseur : la télécommande
 * (flèches, OK, Retour, CH+/CH−) pilote directement la page.
 */
public class MainActivity extends Activity {

    static final String ADRESSE = "https://hugofloriab-cell.github.io/Florijan-Veselaj/tv/";

    private FrameLayout racine;
    private WebView web;
    private View videoPleinEcran;
    private WebChromeClient.CustomViewCallback finPleinEcran;
    private WebChromeClient chrome;

    @Override
    protected void onCreate(Bundle etat) {
        super.onCreate(etat);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);

        racine = new FrameLayout(this);
        racine.setBackgroundColor(0xFF0B1220);
        web = new WebView(this);
        web.setBackgroundColor(0xFF0B1220);
        racine.addView(web, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        setContentView(racine);
        masquerBarres();

        WebSettings r = web.getSettings();
        r.setJavaScriptEnabled(true);
        r.setDomStorageEnabled(true);
        r.setMediaPlaybackRequiresUserGesture(false);
        // Autorise les flux en http (TV Dielli, TV Opoja…) depuis la page https.
        r.setMixedContentMode(WebSettings.MIXED_CONTENT_ALWAYS_ALLOW);
        // Permet à la page de savoir qu'elle tourne dans l'appli.
        r.setUserAgentString(r.getUserAgentString() + " TVKosovaApp/1");

        web.setWebViewClient(new WebViewClient() {
            @Override
            public void onReceivedError(WebView v, WebResourceRequest req, WebResourceError err) {
                if (req.isForMainFrame()) afficherHorsLigne();
            }
        });

        chrome = new WebChromeClient() {
            @Override
            public void onShowCustomView(View vue, CustomViewCallback fin) {
                if (videoPleinEcran != null) { fin.onCustomViewHidden(); return; }
                videoPleinEcran = vue;
                finPleinEcran = fin;
                racine.addView(vue, new FrameLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
                web.setVisibility(View.GONE);
            }

            @Override
            public void onHideCustomView() {
                if (videoPleinEcran == null) return;
                racine.removeView(videoPleinEcran);
                videoPleinEcran = null;
                web.setVisibility(View.VISIBLE);
                if (finPleinEcran != null) finPleinEcran.onCustomViewHidden();
                finPleinEcran = null;
                web.requestFocus();
            }

            /** Pas de grosse icône « lecture » grise avant que la vidéo démarre. */
            @Override
            public Bitmap getDefaultVideoPoster() {
                return Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888);
            }
        };
        web.setWebChromeClient(chrome);

        if (etat == null) web.loadUrl(ADRESSE);
        else web.restoreState(etat);
        web.requestFocus();
    }

    private void afficherHorsLigne() {
        String page = "<html><body style='margin:0;height:100vh;display:grid;place-items:center;"
                + "background:#0b1220;color:#e8edf6;font:22px sans-serif;text-align:center'>"
                + "<div><p>Pas de connexion à internet.</p>"
                + "<button autofocus onclick=\"location.href='" + ADRESSE + "'\" "
                + "style='font:inherit;padding:12px 24px;border-radius:10px;border:0;"
                + "background:#e3a008'>Réessayer</button></div></body></html>";
        web.loadDataWithBaseURL(null, page, "text/html", "utf-8", null);
    }

    private void masquerBarres() {
        getWindow().getDecorView().setSystemUiVisibility(
                View.SYSTEM_UI_FLAG_FULLSCREEN
                        | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                        | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                        | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                        | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                        | View.SYSTEM_UI_FLAG_LAYOUT_STABLE);
    }

    @Override
    public void onWindowFocusChanged(boolean aLeFocus) {
        super.onWindowFocusChanged(aLeFocus);
        if (aLeFocus) masquerBarres();
    }

    /** Retour : sort du plein écran, puis réaffiche la liste, puis quitte. */
    @Override
    @SuppressWarnings("deprecation")
    public void onBackPressed() {
        if (videoPleinEcran != null) {
            chrome.onHideCustomView();
            return;
        }
        web.evaluateJavascript("window.tvRetour ? tvRetour() : false", resultat -> {
            if (!"true".equals(resultat)) finish();
        });
    }

    @Override
    protected void onSaveInstanceState(Bundle etat) {
        super.onSaveInstanceState(etat);
        web.saveState(etat);
    }

    @Override
    protected void onPause() {
        super.onPause();
        web.onPause();
    }

    @Override
    protected void onResume() {
        super.onResume();
        web.onResume();
    }

    @Override
    protected void onDestroy() {
        web.destroy();
        super.onDestroy();
    }
}

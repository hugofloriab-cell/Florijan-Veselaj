package fr.tvkosova.app;

import android.app.Activity;
import android.graphics.Color;
import android.os.Bundle;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowManager;
import android.webkit.JavascriptInterface;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;

import androidx.annotation.OptIn;
import androidx.media3.common.MediaItem;
import androidx.media3.common.MimeTypes;
import androidx.media3.common.PlaybackException;
import androidx.media3.common.Player;
import androidx.media3.common.VideoSize;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.datasource.DefaultHttpDataSource;
import androidx.media3.datasource.HttpDataSource;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory;
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector;
import androidx.media3.ui.AspectRatioFrameLayout;
import androidx.media3.ui.PlayerView;

import java.util.Locale;

/**
 * TV Kosova : la page web (liste des chaînes, bandeau) est affichée par-dessus
 * le lecteur vidéo natif d'Android (ExoPlayer). La page commande le lecteur par
 * l'objet JavaScript « TVKosova » et reçoit ses événements par tvEvenement().
 * La télécommande pilote directement la page : pas de curseur.
 */
@OptIn(markerClass = UnstableApi.class)
public class MainActivity extends Activity {

    static final String ADRESSE = "https://hugofloriab-cell.github.io/Florijan-Veselaj/tv/";

    private WebView web;
    private PlayerView vue;
    private ExoPlayer lecteur;
    private String agent;

    @Override
    protected void onCreate(Bundle etat) {
        super.onCreate(etat);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);

        FrameLayout racine = new FrameLayout(this);
        racine.setBackgroundColor(Color.BLACK);

        // Lecteur natif, en dessous.
        vue = new PlayerView(this);
        vue.setUseController(false);
        vue.setFocusable(false);
        vue.setResizeMode(AspectRatioFrameLayout.RESIZE_MODE_FIT);
        vue.setShutterBackgroundColor(Color.BLACK);
        racine.addView(vue, plein());

        // Page web transparente, au-dessus.
        web = new WebView(this);
        web.setBackgroundColor(Color.TRANSPARENT);
        racine.addView(web, plein());
        setContentView(racine);
        masquerBarres();

        WebSettings r = web.getSettings();
        r.setJavaScriptEnabled(true);
        r.setDomStorageEnabled(true);
        r.setMediaPlaybackRequiresUserGesture(false);
        r.setMixedContentMode(WebSettings.MIXED_CONTENT_ALWAYS_ALLOW);
        agent = r.getUserAgentString();
        // Permet à la page de savoir qu'elle tourne dans l'appli.
        r.setUserAgentString(agent + " TVKosovaApp/2");
        web.addJavascriptInterface(new Pont(), "TVKosova");

        web.setWebViewClient(new WebViewClient() {
            @Override
            public void onReceivedError(WebView v, WebResourceRequest req, WebResourceError err) {
                if (req.isForMainFrame()) afficherHorsLigne();
            }
        });

        creerLecteur();

        if (etat == null) web.loadUrl(ADRESSE);
        else web.restoreState(etat);
        web.requestFocus();
    }

    private static FrameLayout.LayoutParams plein() {
        return new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT);
    }

    private void creerLecteur() {
        // Toujours la meilleure qualité que la télé sait décoder.
        DefaultTrackSelector selecteur = new DefaultTrackSelector(this);
        selecteur.setParameters(selecteur.buildUponParameters()
                .setForceHighestSupportedBitrate(true));

        // Certains serveurs refusent les lecteurs qui ne se présentent pas
        // comme un navigateur.
        DefaultHttpDataSource.Factory http = new DefaultHttpDataSource.Factory()
                .setUserAgent(agent)
                .setAllowCrossProtocolRedirects(true)
                .setConnectTimeoutMs(15000)
                .setReadTimeoutMs(15000);

        lecteur = new ExoPlayer.Builder(this)
                .setTrackSelector(selecteur)
                .setMediaSourceFactory(new DefaultMediaSourceFactory(this).setDataSourceFactory(http))
                .build();
        lecteur.setPlayWhenReady(true);
        vue.setPlayer(lecteur);

        lecteur.addListener(new Player.Listener() {
            @Override
            public void onPlaybackStateChanged(int etat) {
                if (etat == Player.STATE_BUFFERING) evenement("'attente'");
            }

            @Override
            public void onIsPlayingChanged(boolean enLecture) {
                if (enLecture) evenement("'lecture'");
            }

            @Override
            public void onVideoSizeChanged(VideoSize taille) {
                if (taille.height > 0) evenement("'qualite', " + taille.height);
            }

            @Override
            public void onPlayerError(PlaybackException e) {
                // Direct trop en retard sur le serveur : on rejoint le direct.
                if (e.errorCode == PlaybackException.ERROR_CODE_BEHIND_LIVE_WINDOW) {
                    lecteur.seekToDefaultPosition();
                    lecteur.prepare();
                    return;
                }
                int codeHttp = 0;
                for (Throwable t = e; t != null; t = t.getCause()) {
                    if (t instanceof HttpDataSource.InvalidResponseCodeException) {
                        codeHttp = ((HttpDataSource.InvalidResponseCodeException) t).responseCode;
                        break;
                    }
                }
                boolean decodage = e.errorCode >= 4000 && e.errorCode < 5000;
                evenement("'erreur', '" + (decodage ? "decodage" : "reseau") + "', " + codeHttp);
            }
        });
    }

    private void evenement(String args) {
        web.evaluateJavascript("window.tvEvenement && tvEvenement(" + args + ")", null);
    }

    /** Méthodes appelées par la page. */
    private class Pont {
        @JavascriptInterface
        public void jouer(String url) {
            runOnUiThread(() -> {
                MediaItem.Builder m = new MediaItem.Builder().setUri(url);
                String u = url.toLowerCase(Locale.ROOT);
                // Tout ce qui n'est pas un fichier vidéo est traité comme un
                // direct HLS (y compris les adresses en .php ou sans extension).
                if (!u.matches(".*\\.(mp4|mkv|webm|ts|mpd)(\\?.*)?$")) {
                    m.setMimeType(MimeTypes.APPLICATION_M3U8);
                }
                lecteur.setMediaItem(m.build());
                lecteur.prepare();
                lecteur.play();
            });
        }

        @JavascriptInterface
        public void arreter() {
            runOnUiThread(() -> lecteur.stop());
        }

        @JavascriptInterface
        public void basculerPause() {
            runOnUiThread(() -> {
                if (lecteur.isPlaying()) lecteur.pause(); else lecteur.play();
            });
        }
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

    /** Retour : réaffiche la liste si elle est masquée, sinon quitte. */
    @Override
    @SuppressWarnings("deprecation")
    public void onBackPressed() {
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
    protected void onStart() {
        super.onStart();
        web.onResume();
        if (lecteur != null && lecteur.getMediaItemCount() > 0) {
            lecteur.prepare();
            lecteur.play();
        }
    }

    /** Appli quittée ou télé en veille : on coupe le flux. */
    @Override
    protected void onStop() {
        super.onStop();
        web.onPause();
        if (lecteur != null) lecteur.stop();
    }

    @Override
    protected void onDestroy() {
        if (lecteur != null) lecteur.release();
        web.destroy();
        super.onDestroy();
    }
}

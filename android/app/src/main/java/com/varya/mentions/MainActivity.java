package com.varya.mentions;

import android.app.Activity;
import android.graphics.Color;
import android.graphics.Insets;
import android.os.Bundle;
import android.view.WindowInsets;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;
import android.window.OnBackInvokedDispatcher;

public class MainActivity extends Activity {
    private WebView webView;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        FrameLayout root = new FrameLayout(this);
        root.setBackgroundColor(Color.parseColor("#FFE3F1"));

        webView = new WebView(this);
        webView.setBackgroundColor(Color.parseColor("#FFE3F1"));
        WebSettings s = webView.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true); // localStorage — тут хранятся отметки
        s.setAllowFileAccess(true);
        webView.setWebViewClient(new WebViewClient());
        root.addView(webView);

        // С Android 15 приложение рисуется под системными панелями — отступаем от них
        root.setOnApplyWindowInsetsListener((v, insets) -> {
            Insets bars = insets.getInsets(WindowInsets.Type.systemBars() | WindowInsets.Type.displayCutout());
            v.setPadding(bars.left, bars.top, bars.right, bars.bottom);
            return WindowInsets.CONSUMED;
        });

        setContentView(root);
        webView.loadUrl("file:///android_asset/index.html");

        // «Назад»: сначала закрывает окошко с кнопками, потом выходит
        getOnBackInvokedDispatcher().registerOnBackInvokedCallback(
                OnBackInvokedDispatcher.PRIORITY_DEFAULT,
                () -> webView.evaluateJavascript(
                        "window.closeModalIfOpen ? closeModalIfOpen() : false",
                        result -> {
                            if (!"true".equals(result)) finish();
                        }));
    }

    @Override
    protected void onPause() {
        super.onPause();
        webView.onPause();
    }

    @Override
    protected void onResume() {
        super.onResume();
        webView.onResume();
    }
}

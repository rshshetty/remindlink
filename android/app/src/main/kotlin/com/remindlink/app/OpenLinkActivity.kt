package com.remindlink.app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle

class OpenLinkActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val url = intent.getStringExtra("url")
        if (!url.isNullOrEmpty()) {
            try {
                val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
        finish()
    }
}
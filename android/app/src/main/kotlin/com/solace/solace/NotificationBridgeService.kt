package com.solace.solace

import android.app.Notification
import android.app.RemoteInput
import android.content.Intent
import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONArray
import org.json.JSONObject

/**
 * 通知监听桥接服务（可选模块，默认关闭）。
 *
 * 能力边界（严格）：
 * - 只读通知栏已有的标题/正文摘要与“可回复/可播放控制”的动作存在性，
 *   不读任何 App 内文字、不截屏、不模拟点击屏幕坐标。
 * - 代回：只在用户主动点的那一条通知上，用系统 RemoteInput 回复；
 *   回复内容由用户/角色在 Solace 里写好，服务只负责递送。
 * - 音乐控制：只点音乐通知自带的“播放/暂停”动作，不碰其他按钮。
 * - 服务本身不联网、不上传，通知摘要只留在本机内存里。
 *
 * 开启方式：用户在系统设置 → 通知访问里手动授予；
 * 程序内无法代开，开关只负责“是否使用”，不代表已授权。
 */
class NotificationBridgeService : NotificationListenerService() {

    data class ActiveNotification(
        val key: String,
        val packageName: String,
        val title: String,
        val text: String,
        val hasReplyAction: Boolean,
        val hasMediaAction: Boolean
    )

    companion object {
        private var instance: NotificationBridgeService? = null
        private val active = mutableMapOf<String, StatusBarNotification>()
        private val summaries = mutableMapOf<String, ActiveNotification>()
        private var listenerConnected = false

        fun isListenerConnected(): Boolean = listenerConnected

        fun snapshot(): List<ActiveNotification> = summaries.values.toList()

        fun snapshotJson(): String {
            val arr = JSONArray()
            for (n in summaries.values) {
                arr.put(JSONObject().apply {
                    put("key", n.key)
                    put("packageName", n.packageName)
                    put("title", n.title)
                    put("text", n.text)
                    put("hasReplyAction", n.hasReplyAction)
                    put("hasMediaAction", n.hasMediaAction)
                })
            }
            return arr.toString()
        }

        /**
         * 在指定通知上用 RemoteInput 回复 [text]。
         * 只找带 RemoteInput 的动作；没有可回复动作返回 false。
         */
        fun reply(key: String, text: String): Boolean {
            val ctx = instance ?: return false
            val sbn = active[key] ?: return false
            val actions = sbn.notification.actions ?: return false
            for (action in actions) {
                val remoteInputs = action.remoteInputs ?: continue
                if (remoteInputs.isEmpty()) continue
                return try {
                    val intent = Intent()
                    val results = Bundle()
                    for (ri in remoteInputs) {
                        results.putCharSequence(ri.resultKey, text)
                    }
                    RemoteInput.addResultsToIntent(remoteInputs, intent, results)
                    action.actionIntent.send(ctx, 0, intent)
                    true
                } catch (_: Exception) {
                    false
                }
            }
            return false
        }

        /**
         * 切换音乐播放/暂停：只点音乐通知自带的播放/暂停动作。
         * 找不到这类通知返回 false，不碰其他任何按钮。
         */
        fun toggleMedia(): Boolean {
            val ctx = instance ?: return false
            for ((_, sbn) in active) {
                val actions = sbn.notification.actions ?: continue
                for (action in actions) {
                    val title = action.title?.toString() ?: continue
                    if (title.contains("播放") || title.contains("暂停") ||
                        title.equals("Play", ignoreCase = true) ||
                        title.equals("Pause", ignoreCase = true)
                    ) {
                        return try {
                            action.actionIntent.send(ctx, 0, null)
                            true
                        } catch (_: Exception) {
                            false
                        }
                    }
                }
            }
            return false
        }
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onDestroy() {
        if (instance == this) instance = null
        super.onDestroy()
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        listenerConnected = true
    }

    override fun onListenerDisconnected() {
        listenerConnected = false
        active.clear()
        summaries.clear()
        super.onListenerDisconnected()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        active[sbn.key] = sbn
        summaries[sbn.key] = summarize(sbn)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        active.remove(sbn.key)
        summaries.remove(sbn.key)
    }

    private fun summarize(sbn: StatusBarNotification): ActiveNotification {
        val extras = sbn.notification.extras
        val title =
            extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val rawText =
            extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
        val actions = sbn.notification.actions ?: emptyArray()
        var hasReply = false
        var hasMedia = false
        for (a in actions) {
            if (a.remoteInputs != null && a.remoteInputs.isNotEmpty()) {
                hasReply = true
            }
            val t = a.title?.toString() ?: ""
            if (t.contains("播放") || t.contains("暂停") ||
                t.equals("Play", ignoreCase = true) ||
                t.equals("Pause", ignoreCase = true)
            ) {
                hasMedia = true
            }
        }
        return ActiveNotification(
            key = sbn.key,
            packageName = sbn.packageName,
            title = if (title.length > 60) title.take(60) else title,
            text = if (rawText.length > 100) rawText.take(100) else rawText,
            hasReplyAction = hasReply,
            hasMediaAction = hasMedia
        )
    }
}

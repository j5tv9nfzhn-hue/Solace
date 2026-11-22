package com.solace.solace

import android.app.AlarmManager
import android.app.AppOpsManager
import android.app.admin.DevicePolicyManager
import android.app.usage.UsageStatsManager
import android.content.ComponentName
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Build
import android.os.BatteryManager
import android.os.Process
import android.app.WallpaperManager
import android.graphics.BitmapFactory
import android.provider.AlarmClock
import android.provider.CalendarContract
import android.provider.MediaStore
import android.provider.Settings
import android.view.KeyEvent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.content.pm.PackageManager
import android.graphics.Color
import java.io.File
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private var volumeChannel: MethodChannel? = null


    override fun onCreate(savedInstanceState: Bundle?) {
        // Flutter's saved theme preference is available before the first frame.
        // Match the native launch window to it so dark mode never flashes white.
        applySavedLaunchBackground()
        super.onCreate(savedInstanceState)

    }

    private fun applySavedLaunchBackground() {
        val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        val themeMode = prefs.getString("flutter.app_theme_mode", null)
        val isDark = themeMode == "2" ||
            (themeMode != "1" && (resources.configuration.uiMode and
                android.content.res.Configuration.UI_MODE_NIGHT_MASK) ==
                android.content.res.Configuration.UI_MODE_NIGHT_YES)
        val background = if (isDark) Color.rgb(16, 17, 20) else Color.rgb(247, 248, 250)
        window.setBackgroundDrawable(android.graphics.drawable.ColorDrawable(background))
    }



    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)


        volumeChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.solace.solace/volume_key"
        )

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.solace.solace/settings"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openAppSettings" -> {
                    try {
                        val intent = Intent(
                            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.parse("package:$packageName")
                        )
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("FAILED", e.message, null)
                    }
                }
                "canRequestPackageInstalls" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        result.success(packageManager.canRequestPackageInstalls())
                    } else result.success(true)
                }
                "openInstallSourceSettings" -> {
                    try {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                            Uri.parse("package:$packageName")
                        )
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.solace.solace/battery"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getBatteryInfo" -> {
                    try {
                        result.success(getBatteryInfo())
                    } catch (e: Exception) {
                        result.error("BATTERY_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // 保存图片到系统相册（MediaStore，Android 10+ 兼容）
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.solace.solace/gallery"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveImageToGallery" -> {
                    try {
                        val filePath = call.argument<String>("filePath") ?: ""
                        val saved = saveImageToGallery(filePath)
                        result.success(saved)
                    } catch (e: Exception) {
                        result.error("SAVE_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }


        // ─── 作息陪伴 MethodChannel（本地，零外传；只做锁屏 + 使用时长感知） ───
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.solace.solace/wellbeing"
        ).setMethodCallHandler { call, result ->
            handleWellbeingMethodCall(call, result)
        }

        // ─── 真实感上下文 MethodChannel（本地；日历只读标题+开始时间） ───
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.solace.solace/reality"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "queryCalendarToday" -> {
                    try {
                        result.success(queryCalendarToday())
                    } catch (e: SecurityException) {
                        result.error("NO_CALENDAR_PERMISSION", "日历权限未授予", null)
                    } catch (e: Exception) {
                        result.error("CALENDAR_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // ─── 确定性工具 MethodChannel（本地；只发系统 Intent / 调系统服务，
        //       不读屏、不模拟点击、不自动支付/提交） ───
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.solace.solace/automation"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setAlarm" -> {
                    try {
                        val hour = call.argument<Int>("hour") ?: -1
                        val minute = call.argument<Int>("minute") ?: -1
                        val message = call.argument<String>("message") ?: ""
                        if (hour !in 0..23 || minute !in 0..59) {
                            result.error("BAD_TIME", "闹钟时间不对", null)
                            return@setMethodCallHandler
                        }
                        val intent = Intent(AlarmClock.ACTION_SET_ALARM).apply {
                            putExtra(AlarmClock.EXTRA_HOUR, hour)
                            putExtra(AlarmClock.EXTRA_MINUTES, minute)
                            putExtra(AlarmClock.EXTRA_MESSAGE, message)
                            putExtra(AlarmClock.EXTRA_SKIP_UI, false)
                        }
                        if (intent.resolveActivity(packageManager) != null) {
                            startActivity(intent)
                            result.success(true)
                        } else {
                            result.error("NO_ALARM_APP", "系统没有可用的时钟应用", null)
                        }
                    } catch (e: Exception) {
                        result.error("ALARM_FAILED", e.message, null)
                    }
                }
                "addCalendarEvent" -> {
                    try {
                        val title = call.argument<String>("title") ?: ""
                        val begin = call.argument<Number>("startMillis")?.toLong() ?: 0L
                        val end = call.argument<Number>("endMillis")?.toLong() ?: 0L
                        val description = call.argument<String>("description") ?: ""
                        if (title.isBlank() || begin <= 0L || end <= begin) {
                            result.error("BAD_EVENT", "日历事件缺标题或起止时间", null)
                            return@setMethodCallHandler
                        }
                        val intent = Intent(Intent.ACTION_INSERT).apply {
                            data = CalendarContract.Events.CONTENT_URI
                            putExtra(CalendarContract.Events.TITLE, title)
                            putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, begin)
                            putExtra(CalendarContract.EXTRA_EVENT_END_TIME, end)
                            if (description.isNotBlank()) {
                                putExtra(
                                    CalendarContract.Events.DESCRIPTION,
                                    description
                                )
                            }
                        }
                        if (intent.resolveActivity(packageManager) != null) {
                            startActivity(intent)
                            result.success(true)
                        } else {
                            result.error("NO_CALENDAR_APP", "系统没有可用的日历应用", null)
                        }
                    } catch (e: Exception) {
                        result.error("CALENDAR_FAILED", e.message, null)
                    }
                }
                "setWallpaper" -> {
                    try {
                        val path = call.argument<String>("filePath") ?: ""
                        val bitmap = BitmapFactory.decodeFile(path)
                        if (bitmap == null) {
                            result.error("BAD_IMAGE", "图片解码失败", null)
                            return@setMethodCallHandler
                        }
                        WallpaperManager.getInstance(this).setBitmap(bitmap)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("WALLPAPER_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // ─── 通知监听桥接 MethodChannel（可选模块；系统授权只能用户手动开） ───
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.solace.solace/notification_bridge"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isListenerEnabled" -> {
                    try {
                        val enabled = Settings.Secure.getString(
                            contentResolver,
                            "enabled_notification_listeners"
                        ) ?: ""
                        val component = ComponentName(
                            this,
                            NotificationBridgeService::class.java
                        ).flattenToString()
                        result.success(enabled.contains(component))
                    } catch (e: Exception) {
                        result.error("LISTENER_CHECK_FAILED", e.message, null)
                    }
                }
                "openListenerSettings" -> {
                    try {
                        startActivity(
                            Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                        )
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("FAILED", e.message, null)
                    }
                }
                "getRecentNotifications" -> {
                    try {
                        result.success(NotificationBridgeService.snapshotJson())
                    } catch (e: Exception) {
                        result.error("LISTENER_FAILED", e.message, null)
                    }
                }
                "replyToNotification" -> {
                    try {
                        val key = call.argument<String>("key") ?: ""
                        val text = call.argument<String>("text") ?: ""
                        if (key.isBlank() || text.isBlank()) {
                            result.error("BAD_ARGS", "通知 key 或回复内容为空", null)
                        } else {
                            result.success(
                                NotificationBridgeService.reply(key, text)
                            )
                        }
                    } catch (e: Exception) {
                        result.error("REPLY_FAILED", e.message, null)
                    }
                }
                "toggleMediaPlayback" -> {
                    try {
                        result.success(NotificationBridgeService.toggleMedia())
                    } catch (e: Exception) {
                        result.error("MEDIA_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // ─── 无障碍可选模块 MethodChannel（默认关闭；只开 App 页面，绝不自动点击） ───
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.solace.solace/accessibility"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isServiceEnabled" -> {
                    try {
                        val enabled = Settings.Secure.getString(
                            contentResolver,
                            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
                        ) ?: ""
                        val component = ComponentName(
                            this,
                            SolaceAccessibilityService::class.java
                        ).flattenToString()
                        result.success(enabled.contains(component))
                    } catch (e: Exception) {
                        result.error("ACCESSIBILITY_CHECK_FAILED", e.message, null)
                    }
                }
                "openAccessibilitySettings" -> {
                    try {
                        startActivity(
                            Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                        )
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("FAILED", e.message, null)
                    }
                }
                "openAppPage" -> {
                    try {
                        // 模块总闸：Dart 侧开关存在 FlutterSharedPreferences 里，
                        // 关着就拒绝，连 Intent 也不发。
                        val prefs = getSharedPreferences(
                            "FlutterSharedPreferences", MODE_PRIVATE
                        )
                        val moduleEnabled = prefs.getBoolean(
                            "flutter.accessibility_automation_enabled", false
                        )
                        if (!moduleEnabled) {
                            result.error("MODULE_DISABLED", "无障碍模块未开启", null)
                            return@setMethodCallHandler
                        }
                        val packageName = call.argument<String>("packageName")
                            ?.trim() ?: ""
                        val uri = call.argument<String>("uri")?.trim() ?: ""
                        if (packageName.isBlank()) {
                            result.error("BAD_ARGS", "App 包名为空", null)
                            return@setMethodCallHandler
                        }
                        // 只打开目标页面，停在打开页即止：不读屏、不找节点、
                        // 不调 performAction、不自动点任何按钮。
                        val intent = if (uri.isNotBlank()) {
                            Intent(Intent.ACTION_VIEW, Uri.parse(uri)).apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                setPackage(packageName)
                            }
                        } else {
                            packageManager.getLaunchIntentForPackage(packageName)
                                ?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        if (intent == null ||
                            intent.resolveActivity(packageManager) == null
                        ) {
                            result.error("APP_NOT_FOUND", "找不到目标 App 或页面", null)
                        } else {
                            startActivity(intent)
                            result.success(true)
                        }
                    } catch (e: Exception) {
                        result.error("OPEN_APP_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // ─── 微信机器人前台保活 ───
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.solace.solace/wechat_bot_foreground"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startForeground" -> {
                    try {
                        val title = call.argument<String>("title") ?: "微信机器人"
                        val body = call.argument<String>("body") ?: "在线"
                        val intent = Intent(this, WechatBotForegroundService::class.java).apply {
                            action = WechatBotForegroundService.ACTION_START
                            putExtra(WechatBotForegroundService.EXTRA_TITLE, title)
                            putExtra(WechatBotForegroundService.EXTRA_BODY, body)
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("FOREGROUND_FAILED", e.message, null)
                    }
                }
                "stopForeground" -> {
                    val intent = Intent(this, WechatBotForegroundService::class.java).apply {
                        action = WechatBotForegroundService.ACTION_STOP
                    }
                    startService(intent)
                    result.success(true)
                }
                "requestIgnoreBatteryOptimization" -> {
                    // 请求忽略电池优化（白名单），防止国产 ROM 在后台杀前台服务
                    try {
                        val pm = getSystemService(POWER_SERVICE) as android.os.PowerManager
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                                val intent = Intent(
                                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                    Uri.parse("package:$packageName")
                                )
                                startActivity(intent)
                            }
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("BATTERY_OPT_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }


    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (keyCode == KeyEvent.KEYCODE_VOLUME_UP) {
            volumeChannel?.invokeMethod("volume_up", null)
            return true
        }
        if (keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) {
            volumeChannel?.invokeMethod("volume_down", null)
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    // ─── 作息陪伴方法处理（本地锁屏 + 使用时长感知，零数据外传） ───

    private fun wellbeingAdmin(): ComponentName =
        ComponentName(this, WellbeingAdminReceiver::class.java)

    private fun handleWellbeingMethodCall(
        call: MethodCall,
        result: MethodChannel.Result
    ) {
        try {
            val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
            when (call.method) {
                // 是否已授予「设备管理员（仅锁屏）」
                "isAdminActive" -> {
                    result.success(dpm.isAdminActive(wellbeingAdmin()))
                }
                // 拉起系统的设备管理员授权页（用户主动同意才生效）
                "requestAdmin" -> {
                    val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
                        putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, wellbeingAdmin())
                        putExtra(
                            DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                            "授予后，Solace 才能在你设定的休息时段温柔地为你锁屏。仅锁屏，你用自己的密码即可解开，可随时在系统设置里撤销。"
                        )
                    }
                    startActivity(intent)
                    result.success(true)
                }
                // 本地触发锁屏（仅在已授权时可用）
                "lockNow" -> {
                    if (dpm.isAdminActive(wellbeingAdmin())) {
                        dpm.lockNow()
                        result.success(true)
                    } else {
                        result.error("NO_ADMIN", "设备管理员未授权", null)
                    }
                }
                // 是否已授予「使用情况访问」
                "hasUsageAccess" -> {
                    result.success(hasUsageStatsPermission())
                }
                // 拉起系统的「使用情况访问」授权页
                "requestUsageAccess" -> {
                    startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                    result.success(true)
                }
                // 查询最近 N 分钟的前台使用时长（按包名聚合，只有包名+毫秒时长）
                "queryUsage" -> {
                    if (!hasUsageStatsPermission()) {
                        result.error("NO_USAGE_ACCESS", "使用情况访问未授权", null)
                        return
                    }
                    val windowMinutes = call.argument<Int>("windowMinutes") ?: 30
                    result.success(queryForegroundUsage(windowMinutes))
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("WELLBEING_ERROR", e.message, null)
        }
    }

    private fun hasUsageStatsPermission(): Boolean {
        return try {
            val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                appOps.unsafeCheckOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    Process.myUid(),
                    packageName
                )
            } else {
                @Suppress("DEPRECATION")
                appOps.checkOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    Process.myUid(),
                    packageName
                )
            }
            mode == AppOpsManager.MODE_ALLOWED
        } catch (e: Exception) {
            false
        }
    }

    /**
     * 汇总最近 windowMinutes 分钟内各前台应用的使用时长。
     * 返回 {packageName, appName, totalMs, lastUsed}，不读取任何应用内文字/内容。
     */
    private fun queryForegroundUsage(windowMinutes: Int): String {
        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val pm = packageManager
        val end = System.currentTimeMillis()
        val begin = end - windowMinutes * 60_000L
        val stats = usm.queryUsageStats(
            UsageStatsManager.INTERVAL_BEST, begin, end
        ) ?: emptyList()
        val arr = JSONArray()
        for (s in stats) {
            if (s.totalTimeInForeground <= 0) continue
            val appName = try {
                val ai = pm.getApplicationInfo(s.packageName, 0)
                pm.getApplicationLabel(ai).toString()
            } catch (_: Exception) {
                s.packageName
            }
            arr.put(JSONObject().apply {
                put("packageName", s.packageName)
                put("appName", appName)
                put("totalMs", s.totalTimeInForeground)
                put("lastUsed", s.lastTimeUsed)
            })
        }
        return arr.toString()
    }

    // ─── 真实感上下文：今日日程（只读标题 + 开始时间，不读描述/地点/参与人） ───

    private fun queryCalendarToday(): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            checkSelfPermission(android.Manifest.permission.READ_CALENDAR) !=
                PackageManager.PERMISSION_GRANTED
        ) {
            throw SecurityException("日历权限未授予")
        }
        val dayStart = java.util.Calendar.getInstance().apply {
            set(java.util.Calendar.HOUR_OF_DAY, 0)
            set(java.util.Calendar.MINUTE, 0)
            set(java.util.Calendar.SECOND, 0)
            set(java.util.Calendar.MILLISECOND, 0)
        }.timeInMillis
        val dayEnd = dayStart + 24 * 60 * 60 * 1000L
        val projection = arrayOf(
            CalendarContract.Events.TITLE,
            CalendarContract.Events.DTSTART
        )
        val selection =
            "${CalendarContract.Events.DTSTART} >= ? AND ${CalendarContract.Events.DTSTART} < ?"
        val cursor = contentResolver.query(
            CalendarContract.Events.CONTENT_URI,
            projection,
            selection,
            arrayOf(dayStart.toString(), dayEnd.toString()),
            "${CalendarContract.Events.DTSTART} ASC"
        ) ?: return "[]"
        val arr = JSONArray()
        cursor.use {
            val titleIdx = it.getColumnIndex(CalendarContract.Events.TITLE)
            val startIdx = it.getColumnIndex(CalendarContract.Events.DTSTART)
            var count = 0
            while (it.moveToNext() && count < 10) {
                val title = if (titleIdx >= 0) it.getString(titleIdx) ?: "" else ""
                if (title.isBlank()) continue
                val start = if (startIdx >= 0) it.getLong(startIdx) else 0L
                arr.put(JSONObject().apply {
                    put("title", if (title.length > 40) title.take(40) else title)
                    put("startMillis", start)
                })
                count++
            }
        }
        return arr.toString()
    }

    // ─── 已有方法 ───

    private fun getBatteryInfo(): Map<String, Any> {
        val batteryIntent = registerReceiver(
            null,
            IntentFilter(Intent.ACTION_BATTERY_CHANGED)
        )
        val level = batteryIntent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = batteryIntent?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        val percentage = if (level >= 0 && scale > 0) (level * 100 / scale) else 0
        val status = batteryIntent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                status == BatteryManager.BATTERY_STATUS_FULL
        val plugged = batteryIntent?.getIntExtra(BatteryManager.EXTRA_PLUGGED, -1) ?: -1
        val chargeSource = when (plugged) {
            BatteryManager.BATTERY_PLUGGED_AC -> "ac"
            BatteryManager.BATTERY_PLUGGED_USB -> "usb"
            BatteryManager.BATTERY_PLUGGED_WIRELESS -> "wireless"
            else -> "none"
        }
        return mapOf(
            "percentage" to percentage,
            "isCharging" to isCharging,
            "isFull" to (status == BatteryManager.BATTERY_STATUS_FULL),
            "chargeSource" to chargeSource
        )
    }

    private fun saveImageToGallery(filePath: String): Boolean {
        return try {
            val file = java.io.File(filePath)
            if (!file.exists()) return false

            val fileName = "Solace_${System.currentTimeMillis()}.png"
            val contentValues = ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, fileName)
                put(MediaStore.Images.Media.MIME_TYPE, "image/png")
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    put(MediaStore.Images.Media.IS_PENDING, 1)
                }
            }

            val resolver = contentResolver
            val imageCollectionUri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            } else {
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            }

            val insertedUri = resolver.insert(imageCollectionUri, contentValues) ?: return false

            resolver.openOutputStream(insertedUri)?.use { outputStream ->
                file.inputStream().use { inputStream ->
                    inputStream.copyTo(outputStream)
                }
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                contentValues.clear()
                contentValues.put(MediaStore.Images.Media.IS_PENDING, 0)
                resolver.update(insertedUri, contentValues, null, null)
            }

            true
        } catch (e: Exception) {
            false
        }
    }

    // ─── 通知监听方法处理 ───

}
